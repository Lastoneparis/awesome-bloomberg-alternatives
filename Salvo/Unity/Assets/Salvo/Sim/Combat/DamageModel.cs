namespace Salvo.Sim
{
    /// <summary>Why a player lost health. Kept so the kill feed and the stats can tell the
    /// difference without inspecting the weapon.</summary>
    public enum DamageCause : byte
    {
        Gunfire,
        Melee,
        Explosion,
        Falling,
        World,      // out of bounds, crushed, drowned
    }

    /// <summary>
    /// One resolved damage event. Produced only by the server.
    /// </summary>
    public struct DamageEvent
    {
        public PlayerId Attacker;
        public PlayerId Victim;
        public ContentId WeaponId;
        public DamageCause Cause;
        public HitRegion Region;

        /// <summary>Health actually removed, after armour and after clamping to what the
        /// victim had left. This is the number the damage numbers show.</summary>
        public float HealthDamage;
        public float ArmourDamage;

        public float DistanceMetres;
        public bool WasFatal;
        public Vec3 Point;
        public Vec3 Direction;
        public int Tick;

        public bool IsSelfInflicted => Attacker == Victim || !Attacker.IsValid;
    }

    /// <summary>
    /// The health and armour a player currently has.
    /// </summary>
    public struct VitalsState
    {
        public float Health;
        public float MaxHealth;
        public float Armour;
        public bool IsAlive;

        /// <summary>Seconds since the last damage. Drives regeneration.</summary>
        public float TimeSinceDamage;
        /// <summary>Seconds of spawn protection left.</summary>
        public float SpawnProtection;

        public static VitalsState Spawn(GameModeDefinition mode) => new VitalsState
        {
            Health = mode.StartingHealth,
            MaxHealth = mode.StartingHealth,
            Armour = mode.StartingArmour,
            IsAlive = true,
            TimeSinceDamage = 0f,
            SpawnProtection = mode.SpawnProtectionSeconds,
        };

        public void Tick(GameModeDefinition mode, float dt)
        {
            if (!IsAlive) return;
            SpawnProtection = System.Math.Max(0f, SpawnProtection - dt);
            TimeSinceDamage += dt;

            if (mode.HealthRegenerates && Health < MaxHealth
                && TimeSinceDamage >= mode.RegenDelaySeconds)
            {
                Health = System.Math.Min(MaxHealth, Health + mode.RegenPerSecond * dt);
            }
        }
    }

    /// <summary>
    /// Turns "this weapon hit this player there, from this far" into health lost.
    /// </summary>
    /// <remarks>
    /// This runs on the server and nowhere else that matters. A client may call it to draw a
    /// predicted hit marker, but the client's answer is never sent anywhere and never believed
    /// — §13 of the brief is explicit that damage, health and kills are server truth. The
    /// separation is enforced structurally: this is a pure function of server-held state, so
    /// there is no path by which a client-supplied number could reach it.
    /// </remarks>
    public static class DamageModel
    {
        /// <summary>Fraction of incoming damage armour absorbs before its own durability is
        /// spent. Not per-weapon: weapons express their answer to armour through
        /// <see cref="WeaponDefinition.ArmourPiercing"/>.</summary>
        public const float ArmourAbsorption = 0.5f;

        /// <summary>
        /// Computes a damage event. Does not apply it — applying is the caller's job, so that
        /// the mode gets to veto (friendly fire, spawn protection, warm-up) before any health
        /// actually moves.
        /// </summary>
        public static DamageEvent Resolve(PlayerId attacker, PlayerId victim,
                                          WeaponDefinition weapon, HitRegion region,
                                          float distanceMetres, VitalsState vitals,
                                          Vec3 point, Vec3 direction, int tick)
        {
            float raw = weapon.DamageAtRange(distanceMetres);
            raw *= region == HitRegion.Head ? weapon.HeadshotMultiplier
                                            : region.DamageMultiplier();

            SplitAcrossArmour(raw, vitals.Armour, weapon.ArmourPiercing,
                              out float toHealth, out float toArmour);

            // Clamped so the event reports what was actually taken. An event claiming 90
            // damage against a player who had 20 health would make every damage number and
            // every "damage dealt" statistic in the game wrong.
            float appliedHealth = System.Math.Min(toHealth, System.Math.Max(0f, vitals.Health));
            float appliedArmour = System.Math.Min(toArmour, System.Math.Max(0f, vitals.Armour));

            return new DamageEvent
            {
                Attacker = attacker,
                Victim = victim,
                WeaponId = weapon.Id,
                Cause = weapon.Class == WeaponClass.Melee ? DamageCause.Melee : DamageCause.Gunfire,
                Region = region,
                HealthDamage = appliedHealth,
                ArmourDamage = appliedArmour,
                DistanceMetres = distanceMetres,
                WasFatal = vitals.Health - toHealth <= 0f,
                Point = point,
                Direction = direction,
                Tick = tick,
            };
        }

        /// <summary>
        /// Divides incoming damage between health and armour.
        /// </summary>
        /// <remarks>
        /// Armour reduces damage but is consumed doing so, and a weapon's armour-piercing
        /// value is the fraction that ignores it entirely. The consequence worth stating: a
        /// high armour-piercing weapon is not simply stronger, it is stronger specifically
        /// against armoured targets and no better against bare ones — which is what makes it a
        /// trade-off rather than an upgrade.
        /// </remarks>
        public static void SplitAcrossArmour(float raw, float armour, float piercing,
                                             out float toHealth, out float toArmour)
        {
            piercing = SalvoMath.Clamp01(piercing);
            if (armour <= 0f)
            {
                toHealth = raw;
                toArmour = 0f;
                return;
            }

            float piercingPortion = raw * piercing;
            float blockablePortion = raw - piercingPortion;

            float absorbed = blockablePortion * ArmourAbsorption;
            // Armour can only absorb what it has left; the overflow goes straight through.
            float actuallyAbsorbed = System.Math.Min(absorbed, armour);
            float overflow = absorbed - actuallyAbsorbed;

            toArmour = actuallyAbsorbed;
            toHealth = piercingPortion + (blockablePortion - absorbed) + overflow;
        }

        /// <summary>
        /// Fall damage. Below the safe speed it is free; above the lethal speed it kills
        /// outright; between the two it ramps.
        /// </summary>
        public static float FallDamage(float impactSpeed, MovementTuning tuning, float maxHealth)
        {
            if (impactSpeed <= tuning.SafeFallSpeed) return 0f;
            float t = SalvoMath.InverseLerp(tuning.SafeFallSpeed, tuning.LethalFallSpeed, impactSpeed);
            // Squared, so a fall that is slightly too long is a scratch and a genuinely long
            // one is fatal, rather than every overlong fall costing roughly the same.
            return maxHealth * SalvoMath.Clamp01(t * t);
        }

        /// <summary>
        /// Applies a resolved event to a player's vitals. Returns true if it was the killing
        /// blow — the single place death is decided, so a mode cannot accidentally kill a
        /// player twice.
        /// </summary>
        public static bool Apply(ref VitalsState vitals, DamageEvent damage)
        {
            if (!vitals.IsAlive) return false;

            vitals.Armour = System.Math.Max(0f, vitals.Armour - damage.ArmourDamage);
            vitals.Health -= damage.HealthDamage;
            vitals.TimeSinceDamage = 0f;

            if (vitals.Health <= 0f)
            {
                vitals.Health = 0f;
                vitals.IsAlive = false;
                return true;
            }
            return false;
        }
    }
}
