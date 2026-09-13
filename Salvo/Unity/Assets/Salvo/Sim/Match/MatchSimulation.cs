using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>
    /// Something that happened this tick and that presentation or the network layer needs to
    /// know about. The simulation produces these; it never draws, plays a sound or sends a
    /// packet itself.
    /// </summary>
    public enum MatchEventKind : byte
    {
        Spawned, Died, Damaged, Fired, Reloaded, WeaponSwitched, Footstep,
        BulletImpact, RoundStarted, RoundEnded, MatchEnded, PhaseChanged,
    }

    public struct MatchEvent
    {
        public MatchEventKind Kind;
        public int Tick;
        public PlayerId Player;
        public PlayerId OtherPlayer;
        public ContentId ContentId;
        public Vec3 Position;
        public Vec3 Normal;
        public float Value;
        public HitRegion Region;
        public SurfaceKind Surface;
        public bool Flag;
    }

    /// <summary>
    /// The authoritative game. One instance is one match.
    /// </summary>
    /// <remarks>
    /// This is the loop, and it is deliberately not "the game manager". It owns the things every
    /// mode shares — the tick order, movement, weapons, damage, respawn timers, lag-compensation
    /// history — and delegates every rule that varies to <see cref="IGameMode"/>. It does not
    /// know what team deathmatch is.
    ///
    /// <para><b>Tick order matters and is not arbitrary.</b> Inputs are applied, then movement,
    /// then poses are recorded for lag compensation, then weapons fire against those poses, then
    /// damage is applied, then the mode is asked what it makes of the result. Recording poses
    /// after movement but before firing is the important one: a shot fired this tick is judged
    /// against where everyone is now, not where they were before they moved.</para>
    ///
    /// <para>Every mutation of health, ammunition, score or position happens here or in code
    /// this calls. There is no path from a network message to any of it except through
    /// <see cref="SubmitInput"/>, which accepts intent and nothing else. That is the structural
    /// form of the brief's rule that the client is never trusted: not a check that could be
    /// forgotten, but an absence of the function that would be needed to break it.</para>
    /// </remarks>
    public sealed class MatchSimulation
    {
        private readonly List<PlayerRuntime> _players = new List<PlayerRuntime>();
        private readonly Dictionary<int, PlayerRuntime> _byId = new Dictionary<int, PlayerRuntime>();
        private readonly List<MatchEvent> _events = new List<MatchEvent>();
        private readonly LagCompensation _history = new LagCompensation();
        private readonly LoadoutResolver _resolver;
        private readonly Dictionary<string, float> _spawnLastUsed = new Dictionary<string, float>();

        private readonly List<ShotResult> _shotScratch = new List<ShotResult>();
        private readonly List<PlayerId> _idScratch = new List<PlayerId>();
        private readonly List<Team> _teamScratch = new List<Team>();
        private readonly List<ShootableTarget> _targetScratch = new List<ShootableTarget>();

        private int _nextPlayerId;

        public GameContent Content { get; }
        public MapDefinition Map { get; }
        public CollisionWorld World { get; }
        public IGameMode Mode { get; }
        public MovementTuning Tuning { get; }

        public int Tick { get; private set; }
        public float ElapsedSeconds => Tick * FixedClock.TickInterval;
        public MatchPhase Phase { get; private set; } = MatchPhase.Warmup;
        public int RoundNumber { get; private set; }
        public MatchOutcome Outcome { get; private set; } = MatchOutcome.Undecided;

        /// <summary>Seeds every random draw in the match. Sent to clients at match start so
        /// they can predict spread; regenerated per match so patterns are not reusable.</summary>
        public uint MatchSeed { get; }

        public IReadOnlyList<PlayerRuntime> Players => _players;

        /// <summary>
        /// What happened during the most recent <see cref="Start"/> or <see cref="Step"/>.
        /// </summary>
        /// <remarks>
        /// Cleared at the top of every <see cref="Step"/>, so a caller must drain it after each
        /// call — <see cref="Start"/> included. The initial spawns are emitted by
        /// <see cref="Start"/>, and a caller that only reads after <see cref="Step"/> will never
        /// see a single player enter the match.
        /// </remarks>
        public IReadOnlyList<MatchEvent> Events => _events;
        public LagCompensation History => _history;

        private float _phaseTimer;

        public MatchSimulation(GameContent content, MapDefinition map, IGameMode mode,
                               uint matchSeed, MovementTuning tuning = null)
        {
            Content = content ?? throw new System.ArgumentNullException(nameof(content));
            Map = map ?? throw new System.ArgumentNullException(nameof(map));
            Mode = mode ?? throw new System.ArgumentNullException(nameof(mode));
            World = new CollisionWorld(map);
            Tuning = tuning ?? new MovementTuning();
            MatchSeed = matchSeed;
            _resolver = new LoadoutResolver(content);
        }

        // ---- players ------------------------------------------------------------------

        public PlayerRuntime AddPlayer(string name, Team team, Loadout loadout, bool isBot = false,
                                       ContentId botDifficulty = default)
        {
            if (_players.Count >= Mode.Definition.MaxPlayers)
                throw new System.InvalidOperationException(
                    $"mode '{Mode.Definition.Id}' allows {Mode.Definition.MaxPlayers} players");

            var player = new PlayerRuntime
            {
                Id = new PlayerId(_nextPlayerId++),
                Name = name ?? "",
                Team = team,
                IsBot = isBot,
                Loadout = loadout,
                BotDifficultyId = botDifficulty,
            };
            _players.Add(player);
            _byId[player.Id.Raw] = player;
            return player;
        }

        public PlayerRuntime Find(PlayerId id) =>
            _byId.TryGetValue(id.Raw, out PlayerRuntime player) ? player : null;

        public void RemovePlayer(PlayerId id)
        {
            PlayerRuntime player = Find(id);
            if (player == null) return;
            // Removed from the roster but kept in the list as disconnected, so that a kill feed
            // and a scoreboard can still name whoever they were.
            player.IsConnected = false;
            player.Vitals.IsAlive = false;
            _history.Forget(id);
        }

        /// <summary>
        /// The only way intent enters the simulation. Takes a command, nothing else — no
        /// position, no health, no hit claim.
        /// </summary>
        public void SubmitInput(PlayerId id, PlayerInput input)
        {
            PlayerRuntime player = Find(id);
            if (player == null || !player.IsConnected) return;
            player.Input = input;
        }

        // ---- lifecycle ----------------------------------------------------------------

        public void Start()
        {
            Tick = 0;
            RoundNumber = 0;
            Outcome = MatchOutcome.Undecided;
            _events.Clear();
            _history.Clear();
            _spawnLastUsed.Clear();

            Mode.OnMatchStart(this);
            foreach (PlayerRuntime player in _players) SpawnPlayer(player);

            SetPhase(Mode.Definition.WarmupSeconds > 0f ? MatchPhase.Warmup : MatchPhase.Live,
                     Mode.Definition.WarmupSeconds);
            if (Mode.Definition.IsRoundBased) BeginRound();
        }

        private void SetPhase(MatchPhase phase, float seconds)
        {
            Phase = phase;
            _phaseTimer = seconds;
            Emit(new MatchEvent { Kind = MatchEventKind.PhaseChanged, Tick = Tick, Value = seconds });
        }

        private void BeginRound()
        {
            RoundNumber++;
            foreach (PlayerRuntime player in _players)
                if (player.IsConnected) SpawnPlayer(player);
            Mode.OnRoundStart(this, RoundNumber);
            Emit(new MatchEvent { Kind = MatchEventKind.RoundStarted, Tick = Tick, Value = RoundNumber });
            SetPhase(Mode.Definition.FreezeSeconds > 0f ? MatchPhase.Freeze : MatchPhase.Live,
                     Mode.Definition.FreezeSeconds);
        }

        public void SpawnPlayer(PlayerRuntime player)
        {
            if (!SpawnSelector.TryChoose(this, player, out SpawnPoint spawn))
            {
                // Every spawn scored as unusable, or the map has none. Refusing to spawn is the
                // honest outcome — placing the player at the origin would drop them into
                // whatever happens to be there.
                return;
            }
            player.Spawn(spawn, Mode.Definition, _resolver);
            _history.Record(player.Id, Tick, player.Movement, isAlive: true);
            Emit(new MatchEvent
            {
                Kind = MatchEventKind.Spawned, Tick = Tick, Player = player.Id,
                Position = spawn.Position,
            });
        }

        // ---- the tick -----------------------------------------------------------------

        /// <summary>
        /// Advances the match by exactly one fixed tick.
        /// </summary>
        public void Step()
        {
            _events.Clear();
            float dt = FixedClock.TickInterval;

            bool frozen = Phase == MatchPhase.Freeze || Phase == MatchPhase.RoundEnd
                       || Phase == MatchPhase.MatchEnd;

            // 1. Movement. Frozen players still have their view applied — being unable to look
            //    around during a freeze is disorienting and buys nothing.
            for (int i = 0; i < _players.Count; i++)
            {
                PlayerRuntime player = _players[i];
                if (!player.IsConnected) continue;
                if (!player.IsAlive) { TickDead(player, dt); continue; }

                PlayerInput input = player.Input;
                if (frozen)
                {
                    input.MoveForward = 0;
                    input.MoveRight = 0;
                    input.Buttons &= InputButtons.Aim | InputButtons.Crouch;
                }

                MovementSimulation.Step(ref player.Movement, input, World, Tuning,
                                        player.SpeedMultiplier, dt);
                if (player.Movement.SteppedThisTick)
                {
                    Emit(new MatchEvent
                    {
                        Kind = MatchEventKind.Footstep, Tick = Tick, Player = player.Id,
                        Position = player.Movement.Position, Surface = player.Movement.GroundSurface,
                        Flag = input.Held(InputButtons.Walk),
                    });
                }
                ApplyFallDamage(player);
            }

            // 2. Record poses. After movement, before any shot is resolved: a shot fired this
            //    tick must be judged against where everyone actually is now.
            for (int i = 0; i < _players.Count; i++)
            {
                PlayerRuntime player = _players[i];
                if (!player.IsConnected) continue;
                _history.Record(player.Id, Tick, player.Movement, player.IsAlive);
            }

            // 3. Weapons and shots.
            if (!frozen)
            {
                for (int i = 0; i < _players.Count; i++)
                {
                    PlayerRuntime player = _players[i];
                    if (!player.IsConnected || !player.IsAlive) continue;
                    TickWeapons(player, dt);
                }
            }

            // 4. Vitals and respawn.
            for (int i = 0; i < _players.Count; i++)
            {
                PlayerRuntime player = _players[i];
                if (!player.IsConnected) continue;
                player.Vitals.Tick(Mode.Definition, dt);
                player.TimeSinceLastAttacked += dt;
                player.PreviousInput = player.Input;
            }

            // 5. The mode's turn.
            if (Phase == MatchPhase.Live) Mode.OnTick(this, dt);
            AdvancePhase(dt);

            Tick++;
        }

        private void TickDead(PlayerRuntime player, float dt)
        {
            if (player.RespawnRemaining > 0f)
                player.RespawnRemaining = System.Math.Max(0f, player.RespawnRemaining - dt);

            if (Phase != MatchPhase.Live && Phase != MatchPhase.Warmup) return;
            if (Mode.TryChooseRespawn(this, player, out SpawnPoint spawn))
            {
                player.Spawn(spawn, Mode.Definition, _resolver);
                Emit(new MatchEvent
                {
                    Kind = MatchEventKind.Spawned, Tick = Tick, Player = player.Id,
                    Position = spawn.Position,
                });
                NoteSpawnUsed(spawn);
            }
        }

        private void ApplyFallDamage(PlayerRuntime player)
        {
            if (player.Movement.LandingImpactSpeed <= 0f) return;
            float damage = DamageModel.FallDamage(player.Movement.LandingImpactSpeed, Tuning,
                                                  player.Vitals.MaxHealth);
            if (damage <= 0f) return;

            var fall = new DamageEvent
            {
                Attacker = player.Id, Victim = player.Id, Cause = DamageCause.Falling,
                HealthDamage = System.Math.Min(damage, player.Vitals.Health),
                Point = player.Movement.Position, Tick = Tick,
            };
            if (DamageModel.Apply(ref player.Vitals, fall)) KillPlayer(player, null, fall);
            Emit(new MatchEvent
            {
                Kind = MatchEventKind.Damaged, Tick = Tick, Player = player.Id,
                OtherPlayer = player.Id, Value = fall.HealthDamage,
                Position = player.Movement.Position,
            });
        }

        private void TickWeapons(PlayerRuntime player, float dt)
        {
            HandleWeaponSwitch(player);

            WeaponDefinition weapon = player.HeldDefinition;
            if (weapon == null) return;

            ref WeaponState state = ref player.Weapons[(int)player.HeldSlot];
            bool triggerDown = player.Input.Held(InputButtons.Fire);

            if (player.Input.Held(InputButtons.Reload) && state.CanReload(weapon)
                && !state.IsReloading)
            {
                state.BeginReload(weapon);
                Emit(new MatchEvent
                {
                    Kind = MatchEventKind.Reloaded, Tick = Tick, Player = player.Id,
                    ContentId = weapon.Id,
                });
            }

            if (triggerDown && state.CanFire(weapon))
            {
                FireWeapon(player, weapon, ref state);
            }
            else if (triggerDown && state.IsEmpty && !state.IsReloading && state.CanReload(weapon))
            {
                // Pulling the trigger on an empty magazine reloads. A small courtesy that
                // removes a class of "why am I not shooting" moments on a touchscreen.
                state.BeginReload(weapon);
            }

            state.Tick(weapon, triggerDown, dt);

            // Holstered weapons still recover, so switching away and back is not a way to reset
            // a spray faster than waiting.
            for (int slot = 0; slot < 3; slot++)
            {
                if (slot == (int)player.HeldSlot) continue;
                if (player.ResolvedWeapons[slot] == null) continue;
                player.Weapons[slot].Tick(player.ResolvedWeapons[slot], false, dt);
            }
        }

        private void HandleWeaponSwitch(PlayerRuntime player)
        {
            byte desired = player.Input.DesiredSlot;
            if (desired > 2) return;
            var slot = (WeaponSlot)desired;
            if (slot == player.HeldSlot) return;
            if (player.ResolvedWeapons[desired] == null) return;

            player.HeldSlot = slot;
            player.Weapons[desired].BeginDraw(player.ResolvedWeapons[desired]);
            Emit(new MatchEvent
            {
                Kind = MatchEventKind.WeaponSwitched, Tick = Tick, Player = player.Id,
                ContentId = player.ResolvedWeapons[desired].Id,
            });
        }

        private void FireWeapon(PlayerRuntime player, WeaponDefinition weapon, ref WeaponState state)
        {
            float spread = state.CurrentSpread(weapon, player.Movement, player.IsAiming);
            state.ConsumeShot(weapon);

            // Seeded from the match, the tick and the shooter. The client can reproduce all
            // three, which is what lets it predict where its own pellets went; it cannot
            // reproduce anyone else's without also knowing their tick and id, which it does.
            // That is fine: knowing where a bullet will go is not knowing where a player is.
            var random = DeterministicRandom.Seeded(MatchSeed, (uint)Tick, (uint)player.Id.Raw);

            int rewindTick = LagCompensation.RewindTarget(Tick, player.LatencySeconds);
            IReadOnlyList<ShootableTarget> targets = BuildTargets(player, rewindTick);

            _shotScratch.Clear();
            Ballistics.Fire(weapon, player.Id, player.Team, player.EyePosition, player.Movement.View,
                            spread, World, targets, ref random, Mode.Definition.FriendlyFire,
                            _shotScratch);

            Emit(new MatchEvent
            {
                Kind = MatchEventKind.Fired, Tick = Tick, Player = player.Id,
                ContentId = weapon.Id, Position = player.EyePosition,
                Value = state.Magazine,
            });

            for (int i = 0; i < _shotScratch.Count; i++) ResolveShot(player, weapon, _shotScratch[i]);
        }

        private IReadOnlyList<ShootableTarget> BuildTargets(PlayerRuntime shooter, int rewindTick)
        {
            // A bot has no latency to compensate for, and rewinding for one would hand it a
            // free advantage over the humans it is playing against.
            if (shooter.IsBot || shooter.LatencySeconds <= 0f)
            {
                _targetScratch.Clear();
                for (int i = 0; i < _players.Count; i++)
                {
                    PlayerRuntime other = _players[i];
                    if (!other.IsConnected) continue;
                    _targetScratch.Add(new ShootableTarget
                    {
                        Id = other.Id, Team = other.Team, IsAlive = other.IsAlive,
                        Hitboxes = other.Hitboxes,
                    });
                }
                return _targetScratch;
            }

            _idScratch.Clear();
            _teamScratch.Clear();
            for (int i = 0; i < _players.Count; i++)
            {
                if (!_players[i].IsConnected) continue;
                _idScratch.Add(_players[i].Id);
                _teamScratch.Add(_players[i].Team);
            }
            return _history.RewindTargets(rewindTick, _idScratch, _teamScratch);
        }

        private void ResolveShot(PlayerRuntime shooter, WeaponDefinition weapon, ShotResult shot)
        {
            if (shot.HitWorld)
            {
                Emit(new MatchEvent
                {
                    Kind = MatchEventKind.BulletImpact, Tick = Tick, Player = shooter.Id,
                    Position = shot.End, Normal = shot.Normal, Surface = shot.Surface,
                });
                return;
            }
            if (!shot.HitPlayer) return;

            PlayerRuntime victim = Find(shot.Victim);
            if (victim == null || !victim.IsAlive) return;
            if (victim.Vitals.SpawnProtection > 0f) return;

            DamageEvent damage = DamageModel.Resolve(shooter.Id, victim.Id, weapon, shot.Region,
                                                     shot.DistanceMetres, victim.Vitals,
                                                     shot.End, shot.Normal, Tick);

            // The assist candidate is whoever hurt them before this shooter did, so a player who
            // did most of the work still gets credit when someone else lands the last round.
            if (victim.LastAttacker.IsValid && victim.LastAttacker != shooter.Id)
                victim.AssistCandidate = victim.LastAttacker;
            victim.LastAttacker = shooter.Id;
            victim.TimeSinceLastAttacked = 0f;
            shooter.Score.DamageDealt += damage.HealthDamage;

            bool fatal = DamageModel.Apply(ref victim.Vitals, damage);
            Emit(new MatchEvent
            {
                Kind = MatchEventKind.Damaged, Tick = Tick, Player = victim.Id,
                OtherPlayer = shooter.Id, Value = damage.HealthDamage, Region = shot.Region,
                Position = shot.End, Normal = shot.Normal, ContentId = weapon.Id,
            });

            if (fatal) KillPlayer(victim, shooter, damage);
        }

        private void KillPlayer(PlayerRuntime victim, PlayerRuntime killer, DamageEvent damage)
        {
            victim.Die();

            if (killer != null && killer != victim)
            {
                bool friendly = killer.Team == victim.Team && victim.Team != Team.None;
                // A team kill is still a death for the victim, but never a kill for the killer.
                if (!friendly) killer.CreditKill(damage.Region == HitRegion.Head);

                PlayerRuntime assister = Find(victim.AssistCandidate);
                if (assister != null && assister != killer && assister.Team != victim.Team)
                    assister.Score.Assists++;
            }

            victim.RespawnRemaining = Mode.Definition.RespawnDelaySeconds;

            Emit(new MatchEvent
            {
                Kind = MatchEventKind.Died, Tick = Tick, Player = victim.Id,
                OtherPlayer = killer?.Id ?? PlayerId.None, Region = damage.Region,
                ContentId = damage.WeaponId, Position = victim.Movement.Position,
            });

            Mode.OnPlayerKilled(this, victim, killer, damage);
        }

        // ---- phases -------------------------------------------------------------------

        private void AdvancePhase(float dt)
        {
            if (Phase == MatchPhase.MatchEnd) return;

            if (_phaseTimer > 0f)
            {
                _phaseTimer = System.Math.Max(0f, _phaseTimer - dt);
                if (_phaseTimer > 0f) return;

                if (Phase == MatchPhase.Warmup || Phase == MatchPhase.Freeze)
                {
                    SetPhase(MatchPhase.Live, 0f);
                    return;
                }
                if (Phase == MatchPhase.RoundEnd)
                {
                    BeginRound();
                    return;
                }
            }

            if (Phase != MatchPhase.Live) return;

            MatchOutcome matchEnd = Mode.CheckMatchEnd(this);
            if (matchEnd.IsDecided)
            {
                Outcome = matchEnd;
                SetPhase(MatchPhase.MatchEnd, 0f);
                Emit(new MatchEvent { Kind = MatchEventKind.MatchEnded, Tick = Tick });
                return;
            }

            if (Mode.Definition.IsRoundBased)
            {
                MatchOutcome roundEnd = Mode.CheckRoundEnd(this);
                if (roundEnd.IsDecided)
                {
                    Emit(new MatchEvent { Kind = MatchEventKind.RoundEnded, Tick = Tick });
                    SetPhase(MatchPhase.RoundEnd, 3f);
                }
            }
        }

        // ---- helpers ------------------------------------------------------------------

        public void Emit(MatchEvent matchEvent) => _events.Add(matchEvent);

        private static string SpawnKey(SpawnPoint spawn) =>
            $"{spawn.Position.X:F2},{spawn.Position.Y:F2},{spawn.Position.Z:F2}";

        public void NoteSpawnUsed(SpawnPoint spawn) => _spawnLastUsed[SpawnKey(spawn)] = ElapsedSeconds;

        public float SecondsSinceSpawnUsed(SpawnPoint spawn) =>
            _spawnLastUsed.TryGetValue(SpawnKey(spawn), out float when)
                ? ElapsedSeconds - when
                : float.MaxValue;

        public int LivingCount(Team team)
        {
            int count = 0;
            for (int i = 0; i < _players.Count; i++)
                if (_players[i].IsConnected && _players[i].IsAlive && _players[i].Team == team)
                    count++;
            return count;
        }
    }
}
