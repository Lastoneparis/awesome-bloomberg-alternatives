using System.Collections.Generic;

namespace Salvo.Sim
{
    public enum BotGoal : byte
    {
        Idle,
        /// <summary>Moving toward somewhere interesting with nothing to shoot at.</summary>
        Advance,
        Engage,
        Reload,
        /// <summary>Breaking contact — hurt, or out of ammunition mid-fight.</summary>
        Retreat,
    }

    /// <summary>
    /// Produces a <see cref="PlayerInput"/> for one bot, once per tick.
    /// </summary>
    /// <remarks>
    /// <b>The bot outputs a command and nothing else.</b> It cannot set its own position, health
    /// or ammunition, and it has no privileged access to the simulation: it goes through the same
    /// <see cref="MatchSimulation.SubmitInput"/> a networked player does. That is what makes bot
    /// difficulty honest — an Expert bot is not stronger, it is a better player of the same game.
    ///
    /// <para><b>Difficulty degrades senses and hands, never the rules.</b> Every knob in
    /// <see cref="BotDifficultyDefinition"/> makes a bot slower to notice, slower to turn, or
    /// less precise. None of them make it hit harder or take less damage, and there is nowhere
    /// in this class they could: the damage model never sees a bot flag.</para>
    ///
    /// <para>An easy bot is not a bot with random aim. Random aim reads as a broken opponent
    /// rather than a weak one. Instead an easy bot has a long reaction time, turns slowly, has a
    /// narrow view cone and a short sight range, and its aim error decays toward zero while it
    /// keeps a target — so it starts a fight badly and gets better during it, the way a slow
    /// player does.</para>
    ///
    /// <para>Navigation is direct steering with local obstacle avoidance, not pathfinding. On the
    /// open arenas this phase ships, that is sufficient and honest; a map with a dead end would
    /// trap a bot in it. A navigation graph is Phase 9 in PROJECT_PLAN.md, and until it exists
    /// <see cref="MapDefinition"/> should not gain a map that needs one.</para>
    /// </remarks>
    public sealed class BotBrain
    {
        private readonly BotDifficultyDefinition _difficulty;
        private DeterministicRandom _random;

        public BotGoal Goal { get; private set; } = BotGoal.Idle;
        public PlayerId TargetId { get; private set; } = PlayerId.None;

        /// <summary>Seconds the current target has been visible. Reaction is measured against
        /// this, so a bot cannot react to something it has only just seen.</summary>
        private float _targetVisibleFor;
        private float _timeSinceTargetSeen = float.MaxValue;
        private Vec3 _lastKnownTargetPosition;

        private ViewAngles _aim;
        /// <summary>The error currently baked into the aim, in radians. Re-rolled periodically
        /// rather than per tick: a per-tick re-roll is a jitter, not a miss.</summary>
        private float _aimErrorPitch;
        private float _aimErrorYaw;
        private float _aimErrorAge;

        private Vec3 _moveGoal;
        private float _goalAge;
        private float _strafeSign = 1f;
        private float _strafeAge;
        private float _triggerRestRemaining;

        public BotBrain(BotDifficultyDefinition difficulty, uint seed)
        {
            _difficulty = difficulty ?? throw new System.ArgumentNullException(nameof(difficulty));
            _random = new DeterministicRandom(seed);
        }

        /// <summary>
        /// Decides what this bot does this tick.
        /// </summary>
        public PlayerInput Think(MatchSimulation match, PlayerRuntime self, float dt)
        {
            if (!self.IsAlive)
            {
                Goal = BotGoal.Idle;
                TargetId = PlayerId.None;
                return PlayerInput.Quantised(match.Tick, 0f, 0f, self.Movement.View, InputButtons.None);
            }

            _aim = self.Movement.View;
            PlayerRuntime target = Perceive(match, self, dt);
            ChooseGoal(match, self, target, dt);

            var buttons = InputButtons.None;
            float moveForward = 0f;
            float moveRight = 0f;

            switch (Goal)
            {
                case BotGoal.Engage:
                    AimAt(match, self, target, dt);
                    buttons |= DecideFire(self, target, dt);
                    Strafe(self, target, dt, ref moveForward, ref moveRight);
                    break;

                case BotGoal.Reload:
                    buttons |= InputButtons.Reload;
                    AimAtLastKnown(self, dt);
                    SeekCover(match, self, ref moveForward, ref moveRight, dt);
                    break;

                case BotGoal.Retreat:
                    AimAtLastKnown(self, dt);
                    SeekCover(match, self, ref moveForward, ref moveRight, dt);
                    break;

                case BotGoal.Advance:
                    Advance(match, self, ref moveForward, ref moveRight, dt);
                    break;
            }

            // Bots walk when they have nothing to chase, so that a player can hear an advancing
            // bot but not an idling one — the same information a human opponent gives away.
            if (Goal == BotGoal.Idle) moveForward = 0f;

            return PlayerInput.Quantised(match.Tick, moveRight, moveForward, _aim, buttons,
                                         (byte)self.HeldSlot);
        }

        // ---- perception ---------------------------------------------------------------

        /// <summary>
        /// Finds the best enemy this bot can currently justify knowing about.
        /// </summary>
        /// <remarks>
        /// Everything here is a restriction. A bot that skipped this function would know where
        /// every enemy was at all times, which is the default state of a naive bot and the
        /// reason naive bots feel like cheats.
        /// </remarks>
        private PlayerRuntime Perceive(MatchSimulation match, PlayerRuntime self, float dt)
        {
            PlayerRuntime best = null;
            float bestScore = float.NegativeInfinity;

            Vec3 eye = self.EyePosition;
            Vec3 forward = self.Movement.View.Forward;
            float cosHalfCone = (float)System.Math.Cos(
                _difficulty.ViewConeDegrees * 0.5f * SalvoMath.DegToRad);

            IReadOnlyList<PlayerRuntime> players = match.Players;
            for (int i = 0; i < players.Count; i++)
            {
                PlayerRuntime other = players[i];
                if (other == self || !other.IsAlive || !other.IsConnected) continue;
                if (!other.Team.IsHostileTo(self.Team) && self.Team != Team.None) continue;

                Vec3 toTarget = other.EyePosition - eye;
                float distance = toTarget.Length;
                if (distance > _difficulty.SightRangeMetres)
                {
                    // Out of sight range, but a bot can still hear someone close and noisy.
                    if (distance > _difficulty.HearingRangeMetres) continue;
                    if (other.Movement.HorizontalSpeed < 1f) continue;
                }
                else
                {
                    if (Vec3.Dot(toTarget / distance, forward) < cosHalfCone) continue;
                    if (!match.World.HasLineOfSight(eye, other.EyePosition)) continue;
                }

                // Nearer is better, and whoever is already being tracked gets a bonus so the
                // bot does not switch target every time two enemies trade places.
                float score = -distance + (other.Id == TargetId ? 12f : 0f);
                if (score > bestScore) { bestScore = score; best = other; }
            }

            if (best == null)
            {
                _timeSinceTargetSeen += dt;
                _targetVisibleFor = 0f;
                // The target is remembered for a moment after it disappears, so a bot does not
                // instantly forget someone who stepped behind a crate.
                if (_timeSinceTargetSeen > 3f) TargetId = PlayerId.None;
                return TargetId.IsValid ? match.Find(TargetId) : null;
            }

            if (best.Id != TargetId)
            {
                TargetId = best.Id;
                _targetVisibleFor = 0f;
                // A fresh target gets a fresh aim error, so acquiring someone new costs the bot
                // the same settling time every time.
                RollAimError(1f);
            }
            _targetVisibleFor += dt;
            _timeSinceTargetSeen = 0f;
            _lastKnownTargetPosition = best.EyePosition;
            return best;
        }

        private bool HasReacted => _targetVisibleFor >= _difficulty.ReactionSeconds;

        // ---- goals --------------------------------------------------------------------

        private void ChooseGoal(MatchSimulation match, PlayerRuntime self, PlayerRuntime target,
                                float dt)
        {
            WeaponDefinition weapon = self.HeldDefinition;
            WeaponState state = self.HeldWeapon;

            if (weapon != null && state.IsEmpty && state.CanReload(weapon))
            {
                Goal = BotGoal.Reload;
                return;
            }

            float healthFraction = self.Vitals.MaxHealth > 0f
                ? self.Vitals.Health / self.Vitals.MaxHealth : 1f;
            // Retreat tendency is a difficulty knob, and it is a competence knob in both
            // directions: a bot that never retreats dies in fights it could have survived, and
            // one that always retreats never contests anything.
            if (healthFraction < 0.3f * (0.5f + _difficulty.RetreatTendency) && target != null)
            {
                Goal = BotGoal.Retreat;
                return;
            }

            Goal = target != null && HasReacted ? BotGoal.Engage
                 : target != null ? BotGoal.Advance
                 : BotGoal.Advance;
        }

        // ---- aiming -------------------------------------------------------------------

        private void RollAimError(float scale)
        {
            _aimErrorPitch = _random.NextGaussian() * _difficulty.AimErrorRadians * scale;
            _aimErrorYaw = _random.NextGaussian() * _difficulty.AimErrorRadians * scale;
            _aimErrorAge = 0f;
        }

        private void AimAt(MatchSimulation match, PlayerRuntime self, PlayerRuntime target, float dt)
        {
            if (target == null) { AimAtLastKnown(self, dt); return; }

            _aimErrorAge += dt;
            // Re-rolled a few times a second. Any faster and the error reads as a tremor rather
            // than as imprecision.
            if (_aimErrorAge > 0.3f)
            {
                // Error shrinks the longer the bot has held this target: the settling curve that
                // makes a weak bot start a fight badly and improve during it, rather than simply
                // being wrong at random forever.
                float settle = 1f / (1f + _targetVisibleFor * 1.5f);
                RollAimError(System.Math.Max(0.25f, settle));
            }

            // Aim at the chest, not the eyes. A bot that aims at the head by default lands
            // headshots at a rate no human matches, and it is the single change that most makes
            // bots feel unfair.
            PlayerHitboxes boxes = target.Hitboxes;
            Vec3 point = boxes.Torso.Centre;

            ViewAngles ideal = ViewAngles.LookingAt(self.EyePosition, point);
            var desired = new ViewAngles(ideal.Pitch + _aimErrorPitch, ideal.Yaw + _aimErrorYaw);
            TurnToward(desired, dt);
        }

        private void AimAtLastKnown(PlayerRuntime self, float dt)
        {
            if (_timeSinceTargetSeen > 5f) return;
            TurnToward(ViewAngles.LookingAt(self.EyePosition, _lastKnownTargetPosition), dt);
        }

        /// <summary>
        /// Rotates the aim toward a target angle at the difficulty's turn rate.
        /// </summary>
        /// <remarks>
        /// The turn rate is the cap that makes flick shots impossible for a low-difficulty bot,
        /// and it has to be applied to the shortest way round — turning the long way through
        /// 350° instead of 10° is the classic wrap-around bug, and it looks like the bot
        /// spinning on the spot.
        /// </remarks>
        private void TurnToward(ViewAngles desired, float dt)
        {
            float maxStep = _difficulty.TurnSpeedRadiansPerSecond * dt;
            float yawDelta = SalvoMath.AngleDelta(_aim.Yaw, desired.Yaw);
            float pitchDelta = SalvoMath.AngleDelta(_aim.Pitch, desired.Pitch);

            float yaw = _aim.Yaw + SalvoMath.Clamp(yawDelta, -maxStep, maxStep);
            float pitch = _aim.Pitch + SalvoMath.Clamp(pitchDelta, -maxStep, maxStep);
            _aim = new ViewAngles(pitch, yaw);
        }

        // ---- firing -------------------------------------------------------------------

        private InputButtons DecideFire(PlayerRuntime self, PlayerRuntime target, float dt)
        {
            if (target == null || !HasReacted) return InputButtons.None;

            WeaponDefinition weapon = self.HeldDefinition;
            if (weapon == null) return InputButtons.None;

            // Do not shoot at something that is not actually in front of the barrel. Without
            // this a bot fires through walls the moment it decides to engage, because deciding
            // to engage and being aimed at the target are different things.
            Vec3 toTarget = target.Hitboxes.Torso.Centre - self.EyePosition;
            float distance = toTarget.Length;
            if (distance < 1e-3f) return InputButtons.None;
            float alignment = Vec3.Dot(toTarget / distance, _aim.Forward);
            float requiredAlignment = (float)System.Math.Cos(System.Math.Max(0.02f,
                weapon.HipSpreadRadians * 3f + _difficulty.AimErrorRadians));
            if (alignment < requiredAlignment) return InputButtons.None;

            // Trigger discipline: pause between bursts rather than emptying the magazine in one
            // pull. This is what stops a high-difficulty bot from being a laser — its spray
            // climbs exactly like a player's, and a bot that never releases the trigger would
            // be less accurate, not more.
            if (_triggerRestRemaining > 0f)
            {
                _triggerRestRemaining -= dt;
                return InputButtons.Aim;
            }
            if (self.HeldWeapon.ShotsInBurst > 0
                && _random.NextBool(_difficulty.TriggerDisciplineChance * dt * 10f))
            {
                _triggerRestRemaining = _random.NextFloat(0.12f, 0.35f);
                return InputButtons.Aim;
            }

            // Aiming down sights at range, hip fire up close — the same trade a player makes.
            InputButtons buttons = InputButtons.Fire;
            if (distance > 12f) buttons |= InputButtons.Aim;
            return buttons;
        }

        // ---- movement -----------------------------------------------------------------

        private void Strafe(PlayerRuntime self, PlayerRuntime target, float dt,
                            ref float forward, ref float right)
        {
            if (target == null) return;

            _strafeAge += dt;
            if (_strafeAge > 0.8f)
            {
                _strafeAge = 0f;
                if (_random.NextBool(0.4f)) _strafeSign = -_strafeSign;
            }

            float distance = Vec3.Distance(self.Movement.Position, target.Movement.Position);
            // Close the gap when far, back off when uncomfortably close, strafe in between.
            // Cover preference decides how much of the time is spent moving rather than
            // standing still trading shots.
            if (distance > 25f) forward = 0.8f;
            else if (distance < 6f) forward = -0.6f;
            else forward = 0f;

            right = _strafeSign * SalvoMath.Lerp(0.3f, 1f, _difficulty.CoverPreference);
        }

        private void SeekCover(MatchSimulation match, PlayerRuntime self,
                               ref float forward, ref float right, float dt)
        {
            // No cover reasoning yet — backing away from the last known threat is the honest
            // approximation until the navigation graph exists to find real cover with.
            forward = -0.8f;
            right = _strafeSign * 0.4f;
        }

        private void Advance(MatchSimulation match, PlayerRuntime self,
                             ref float forward, ref float right, float dt)
        {
            _goalAge += dt;
            if (_goalAge > 4f || Vec3.Distance(self.Movement.Position, _moveGoal) < 2f)
                PickGoal(match, self);

            Vec3 toGoal = (_moveGoal - self.Movement.Position).Flattened;
            if (toGoal.HorizontalLength < 0.5f) { forward = 0f; return; }

            TurnToward(ViewAngles.LookingAt(self.EyePosition,
                                            _moveGoal + new Vec3(0f, 1.5f, 0f)), dt);
            forward = 1f;

            // Local avoidance: if something is close ahead, slide around it. Enough for open
            // geometry; a dead end would still hold a bot until its goal times out, which is
            // why PickGoal has a timeout at all.
            Vec3 probeFrom = self.EyePosition;
            Vec3 ahead = probeFrom + _aim.FlatForward * 2.5f;
            if (match.World.Trace(probeFrom, ahead, TraceMask.Solid).Hit)
            {
                right = _strafeSign;
                forward = 0.5f;
                _strafeAge += dt;
                if (_strafeAge > 1.2f) { _strafeAge = 0f; _strafeSign = -_strafeSign; }
            }
        }

        private void PickGoal(MatchSimulation match, PlayerRuntime self)
        {
            _goalAge = 0f;

            // Objectives first, weighted by the difficulty's objective focus: a bot that ignores
            // the objective is not "easy", it is playing a different game from the humans.
            List<ObjectiveZone> objectives = match.Map.Objectives;
            if (objectives.Count > 0 && _random.NextBool(_difficulty.ObjectiveFocus))
            {
                _moveGoal = objectives[_random.NextInt(objectives.Count)].Centre;
                return;
            }

            // Otherwise head for an enemy spawn, which is reliably where enemies come from.
            var candidates = new List<SpawnPoint>();
            foreach (SpawnPoint spawn in match.Map.Spawns)
                if (spawn.Team != self.Team) candidates.Add(spawn);

            if (candidates.Count > 0)
            {
                _moveGoal = candidates[_random.NextInt(candidates.Count)].Position;
                return;
            }

            // Nothing to head for: wander within the map bounds rather than standing still.
            Aabb bounds = match.Map.Bounds;
            _moveGoal = new Vec3(
                _random.NextFloat(bounds.Min.X, bounds.Max.X),
                self.Movement.Position.Y,
                _random.NextFloat(bounds.Min.Z, bounds.Max.Z));
        }
    }
}
