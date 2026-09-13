namespace Salvo.Sim
{
    public enum WeaponPhase : byte
    {
        Ready,
        Firing,       // inside the cooldown between shots
        Reloading,
        Drawing,
        Holstering,
    }

    /// <summary>
    /// The mutable state of one weapon in one player's hands.
    /// </summary>
    /// <remarks>
    /// A struct with no reference to its own <see cref="WeaponDefinition"/>. That looks awkward
    /// — every method takes the definition as a parameter — and it is deliberate: the state is
    /// snapshotted and rewound every tick for reconciliation and lag compensation, and a
    /// reference held inside it would be copied around with it and could go stale against a
    /// content reload. The definition is passed in, so there is exactly one authority on which
    /// weapon this is: the loadout.
    /// </remarks>
    public struct WeaponState
    {
        public ContentId WeaponId;
        public WeaponPhase Phase;

        public int Magazine;
        public int Reserve;

        /// <summary>Seconds until the next shot is allowed.</summary>
        public float Cooldown;
        /// <summary>Seconds left in a reload, draw or holster.</summary>
        public float ActionRemaining;

        /// <summary>Seconds since the last round left the barrel. Gates spread recovery.</summary>
        public float TimeSinceShot;

        /// <summary>Accumulated inaccuracy in radians, on top of the base spread.</summary>
        public float Spread;
        /// <summary>Shots fired without releasing the trigger. Indexes the spray pattern.</summary>
        public int ShotsInBurst;
        /// <summary>Rounds left in the current burst, for burst-fire weapons.</summary>
        public int BurstRemaining;
        /// <summary>True while the trigger has been held since the last shot. Semi-automatic
        /// weapons need this: without it, holding fire empties the magazine.</summary>
        public bool TriggerHeld;

        /// <summary>Accumulated recoil applied to the view, in radians. Recovered over time.
        /// Kept separately from the player's aim so that recovery returns the view to where
        /// the player was pointing, not to where the recoil happened to leave it.</summary>
        public float RecoilPitch;
        public float RecoilYaw;

        public bool IsReloading => Phase == WeaponPhase.Reloading;
        public bool IsEmpty => Magazine <= 0;
        public bool HasAnyAmmo => Magazine > 0 || Reserve > 0;

        public static WeaponState Fresh(WeaponDefinition weapon) => new WeaponState
        {
            WeaponId = weapon.Id,
            Phase = WeaponPhase.Ready,
            Magazine = weapon.MagazineSize,
            Reserve = weapon.ReserveAmmo,
            Spread = 0f,
            BurstRemaining = 0,
        };

        /// <summary>
        /// Total cone half-angle for the next shot, in radians.
        /// </summary>
        /// <remarks>
        /// Computed from state rather than stored so it cannot drift out of sync with the
        /// player's stance. The penalties add rather than multiply: a player who is airborne,
        /// sprinting and hip-firing should be hopeless, and multiplying three penalties under
        /// one would make them accurate instead.
        /// </remarks>
        public float CurrentSpread(WeaponDefinition weapon, MovementState movement, bool aiming)
        {
            float baseSpread = aiming ? weapon.AdsSpreadRadians : weapon.HipSpreadRadians;
            float total = baseSpread + Spread;

            if (!movement.IsGrounded) total += weapon.AirborneSpreadPenalty;
            else if (movement.HorizontalSpeed > 0.5f)
            {
                // Scaled by how fast they are actually going, so easing off the stick to line
                // up a shot is a real and immediate choice rather than a binary.
                float speedFraction = SalvoMath.Clamp01(movement.HorizontalSpeed / 5.6f);
                total += weapon.MovingSpreadPenalty * speedFraction;
            }

            if (movement.CrouchAmount > 0f)
            {
                total *= SalvoMath.Lerp(1f, weapon.CrouchSpreadMultiplier, movement.CrouchAmount);
            }

            return System.Math.Min(total, weapon.MaxSpreadRadians);
        }

        /// <summary>True when the weapon would fire if the trigger were pulled right now.</summary>
        public bool CanFire(WeaponDefinition weapon)
        {
            if (Phase == WeaponPhase.Reloading || Phase == WeaponPhase.Drawing
                || Phase == WeaponPhase.Holstering) return false;
            if (Cooldown > 0f) return false;
            if (Magazine <= 0) return false;
            // Semi, bolt and pump actions need the trigger released between shots. Automatic
            // and burst do not — for burst, the burst itself continues without a fresh pull.
            if (TriggerHeld && weapon.FireMode != FireMode.Automatic
                && !(weapon.FireMode == FireMode.Burst && BurstRemaining > 0)) return false;
            return true;
        }

        /// <remarks>
        /// <paramref name="weapon"/> is the <em>resolved</em> definition — attachments have
        /// already been folded in by <see cref="AttachmentDefinition.ApplyTo"/>, so an extended
        /// magazine is simply a larger <see cref="WeaponDefinition.MagazineSize"/> and needs no
        /// special case here.
        /// </remarks>
        public bool CanReload(WeaponDefinition weapon) =>
            Phase != WeaponPhase.Reloading && Phase != WeaponPhase.Drawing
            && Magazine < weapon.MagazineSize && Reserve > 0;

        public void BeginReload(WeaponDefinition weapon)
        {
            Phase = WeaponPhase.Reloading;
            ActionRemaining = Magazine <= 0 ? weapon.EmptyReloadSeconds : weapon.ReloadSeconds;
            ShotsInBurst = 0;
            BurstRemaining = 0;
        }

        public void BeginDraw(WeaponDefinition weapon)
        {
            Phase = WeaponPhase.Drawing;
            ActionRemaining = weapon.DrawSeconds;
            ShotsInBurst = 0;
            BurstRemaining = 0;
            Spread = 0f;
            TimeSinceShot = weapon.DrawSeconds;
        }

        /// <summary>
        /// Completes a reload. Split from <see cref="BeginReload"/> so the tick loop decides
        /// when it finishes, which is what makes a reload interruptible by a weapon switch.
        /// </summary>
        public void FinishReload(WeaponDefinition weapon)
        {
            if (weapon.ReloadsOneRoundAtATime)
            {
                // Shell-by-shell weapons load one and re-enter the reload, so the player can
                // break off and fire with a partial tube.
                int wanted = System.Math.Min(1, weapon.MagazineSize - Magazine);
                int taken = System.Math.Min(wanted, Reserve);
                Magazine += taken;
                Reserve -= taken;
                if (Magazine < weapon.MagazineSize && Reserve > 0)
                {
                    ActionRemaining = weapon.ReloadSeconds;
                    return;
                }
            }
            else
            {
                int wanted = weapon.MagazineSize - Magazine;
                int taken = System.Math.Min(wanted, Reserve);
                Magazine += taken;
                Reserve -= taken;
            }
            Phase = WeaponPhase.Ready;
            ActionRemaining = 0f;
        }

        /// <summary>
        /// Consumes one shot's worth of state: ammunition, cooldown, spread and recoil.
        /// Returns the spray-pattern offset for this shot.
        /// </summary>
        public SprayPoint ConsumeShot(WeaponDefinition weapon)
        {
            Magazine--;
            Cooldown = weapon.SecondsBetweenShots;
            TimeSinceShot = 0f;
            Phase = WeaponPhase.Firing;
            TriggerHeld = true;

            if (weapon.FireMode == FireMode.Burst)
            {
                if (BurstRemaining <= 0) BurstRemaining = weapon.BurstCount;
                BurstRemaining--;
                // The pause between bursts is longer than the pause between rounds within one.
                if (BurstRemaining <= 0) Cooldown = weapon.BurstDelaySeconds;
            }

            SprayPoint offset = SprayOffsetAt(weapon, ShotsInBurst);
            ShotsInBurst++;
            Spread = System.Math.Min(Spread + weapon.SpreadPerShot,
                                     System.Math.Max(0f, weapon.MaxSpreadRadians - weapon.AdsSpreadRadians));

            RecoilPitch += weapon.RecoilVerticalRadians * offset.Vertical;
            RecoilYaw += weapon.RecoilHorizontalRadians * offset.Horizontal;
            return offset;
        }

        /// <summary>
        /// The spray pattern entry for a shot index.
        /// </summary>
        /// <remarks>
        /// A weapon with an authored pattern uses it, and past the end of the pattern the last
        /// entry repeats — which is what makes a long spray learnable rather than a random
        /// walk. A weapon with no pattern gets a plain upward climb, so that content authors
        /// can leave the array empty and still get a weapon that behaves.
        /// </remarks>
        public static SprayPoint SprayOffsetAt(WeaponDefinition weapon, int shotIndex)
        {
            if (weapon.SprayPattern != null && weapon.SprayPattern.Length > 0)
            {
                int index = SalvoMath.Clamp(shotIndex, 0, weapon.SprayPattern.Length - 1);
                return weapon.SprayPattern[index];
            }
            return new SprayPoint(1f, 0f);
        }

        /// <summary>
        /// Advances timers and recovery by one tick. Called for the held weapon every tick,
        /// and for holstered weapons too — a stowed weapon still recovers its spread.
        /// </summary>
        public void Tick(WeaponDefinition weapon, bool triggerDown, float dt)
        {
            if (!triggerDown)
            {
                TriggerHeld = false;
                // Letting go resets the pattern. This is the whole reason burst-firing is a
                // skill: the first shot of every pull is the accurate one.
                ShotsInBurst = 0;
                BurstRemaining = 0;
            }

            if (Cooldown > 0f)
            {
                Cooldown = System.Math.Max(0f, Cooldown - dt);
            }

            if (ActionRemaining > 0f)
            {
                ActionRemaining = System.Math.Max(0f, ActionRemaining - dt);
                if (ActionRemaining <= 0f)
                {
                    if (Phase == WeaponPhase.Reloading) FinishReload(weapon);
                    else Phase = WeaponPhase.Ready;
                }
            }
            else if (Phase == WeaponPhase.Firing && Cooldown <= 0f)
            {
                Phase = WeaponPhase.Ready;
            }

            TimeSinceShot += dt;
            // Recovery waits out the delay. During sustained fire the delay never elapses, so
            // the spray climbs; once the player stops, it unwinds quickly.
            if (TimeSinceShot >= weapon.SpreadRecoveryDelaySeconds)
                Spread = System.Math.Max(0f, Spread - weapon.SpreadRecoveryPerSecond * dt);
            RecoilPitch = SalvoMath.MoveTowards(RecoilPitch, 0f,
                                                weapon.RecoilRecoveryPerSecond * dt * 0.02f);
            RecoilYaw = SalvoMath.MoveTowards(RecoilYaw, 0f,
                                              weapon.RecoilRecoveryPerSecond * dt * 0.02f);
        }
    }
}
