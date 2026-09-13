namespace Salvo.Sim
{
    /// <summary>What a player has done this match. Server-owned; clients receive it.</summary>
    public struct PlayerScore
    {
        public int Kills;
        public int Deaths;
        public int Assists;
        /// <summary>Objective score, separate from kills so a mode can reward playing the
        /// objective without pretending it was a kill.</summary>
        public int ObjectiveScore;
        public float DamageDealt;
        public int Headshots;
        public int CurrentStreak;
        public int BestStreak;

        public int TotalScore => Kills * 100 + Assists * 50 + ObjectiveScore;
        public float KillDeathRatio => Deaths == 0 ? Kills : (float)Kills / Deaths;
    }

    /// <summary>
    /// Everything the simulation knows about one participant.
    /// </summary>
    /// <remarks>
    /// A class, not a struct, unlike most of the simulation's state. It is mutated in place
    /// every tick by several systems and is far too large to keep copying; the pieces that
    /// genuinely need rewinding for reconciliation — <see cref="Movement"/> and the weapon
    /// states — are structs inside it and can be snapshotted on their own.
    ///
    /// <para>A bot and a human are the same type. The only difference is
    /// <see cref="IsBot"/> and where <see cref="Input"/> comes from: a human's arrives over the
    /// network, a bot's is produced by <see cref="BotBrain"/>. Everything downstream — movement,
    /// weapons, damage — cannot tell them apart, which is the only way to be sure bots are
    /// playing the same game as the players.</para>
    /// </remarks>
    public sealed class PlayerRuntime
    {
        public PlayerId Id;
        /// <summary>Display name. Never used as a localisation key and never interpolated into
        /// one — it is user content and goes into UI as a parameter.</summary>
        public string Name = "";
        public Team Team = Team.None;
        public bool IsBot;
        public bool IsConnected = true;

        public Loadout Loadout;
        public ContentId BotDifficultyId;

        public MovementState Movement;
        public VitalsState Vitals;
        public PlayerScore Score;

        /// <summary>One state per slot, so switching weapons preserves each one's magazine.</summary>
        public readonly WeaponState[] Weapons = new WeaponState[3];
        public WeaponSlot HeldSlot = WeaponSlot.Primary;

        /// <summary>The command being simulated this tick.</summary>
        public PlayerInput Input;
        public PlayerInput PreviousInput;

        /// <summary>Seconds until this player respawns. Zero when alive or when the mode does
        /// not respawn.</summary>
        public float RespawnRemaining;

        /// <summary>Server-measured round-trip time, used for lag compensation. Measured, never
        /// reported by the client — a client that could name its own latency could name a large
        /// one and shoot at where everyone was a second ago.</summary>
        public float LatencySeconds;

        /// <summary>Who last hurt this player and when, so a kill can be credited and assists
        /// awarded without searching a damage log.</summary>
        public PlayerId LastAttacker = PlayerId.None;
        public float TimeSinceLastAttacked = float.MaxValue;
        public PlayerId AssistCandidate = PlayerId.None;

        /// <summary>Resolved weapon definitions, one per slot. Populated at spawn so the
        /// catalogue is consulted once rather than per shot.</summary>
        public readonly WeaponDefinition[] ResolvedWeapons = new WeaponDefinition[3];

        public ref WeaponState HeldWeapon => ref Weapons[(int)HeldSlot];
        public WeaponDefinition HeldDefinition => ResolvedWeapons[(int)HeldSlot];

        public bool IsAlive => Vitals.IsAlive;
        public bool IsAiming => Input.Held(InputButtons.Aim);

        public Vec3 EyePosition => Movement.EyePosition;
        public PlayerHitboxes Hitboxes => PlayerHitboxes.For(Movement);

        /// <summary>
        /// The movement speed multiplier for a weapon and an aim state.
        /// </summary>
        /// <remarks>
        /// Static, and shared by the server and by every predicting client, because this is
        /// exactly the kind of small derived value that two implementations will compute
        /// slightly differently and then disagree about forever.
        ///
        /// <para>It takes the aim state as a parameter rather than reading a player's current
        /// one, and that is the whole point. A client replaying an input from six ticks ago must
        /// use the aim state <em>of that input</em>, not whatever the player is doing now.
        /// Aiming halves movement speed, so getting this wrong diverges client and server by
        /// half a tick of travel on every tick where the player was aiming and is no longer, or
        /// the reverse — which is most of a firefight.</para>
        /// </remarks>
        public static float SpeedMultiplierFor(WeaponDefinition weapon, bool aiming)
        {
            if (weapon == null) return 1f;
            float multiplier = weapon.MoveSpeedMultiplier;
            if (aiming) multiplier *= weapon.AdsMoveSpeedMultiplier;
            // Reloading does not slow a player down. It is already a commitment; adding a
            // speed penalty on top punishes the same decision twice.
            return multiplier;
        }

        /// <summary>The multiplier for the input this player is currently simulating.</summary>
        public float SpeedMultiplier => SpeedMultiplierFor(HeldDefinition, IsAiming);

        /// <summary>The multiplier this player would have for an arbitrary command. Used by a
        /// predicting client when replaying its own input history.</summary>
        public float SpeedMultiplierForInput(PlayerInput input) =>
            SpeedMultiplierFor(ResolvedWeapons[(int)HeldSlot],
                               input.Held(InputButtons.Aim));

        /// <summary>
        /// Puts the player into the world alive, with full ammunition and a fresh weapon state.
        /// </summary>
        public void Spawn(SpawnPoint spawn, GameModeDefinition mode, LoadoutResolver resolver)
        {
            Movement = MovementState.AtSpawn(spawn);
            Vitals = VitalsState.Spawn(mode);
            RespawnRemaining = 0f;
            LastAttacker = PlayerId.None;
            AssistCandidate = PlayerId.None;
            TimeSinceLastAttacked = float.MaxValue;

            for (int slot = 0; slot < 3; slot++)
            {
                WeaponDefinition weapon = resolver.Resolve(Loadout[(WeaponSlot)slot]);
                ResolvedWeapons[slot] = weapon;
                Weapons[slot] = weapon != null ? WeaponState.Fresh(weapon) : default;
            }

            // Start on the best weapon the loadout actually resolved, so a player whose primary
            // failed to resolve is holding their pistol rather than nothing.
            HeldSlot = ResolvedWeapons[0] != null ? WeaponSlot.Primary
                     : ResolvedWeapons[1] != null ? WeaponSlot.Secondary
                     : WeaponSlot.Melee;
            if (ResolvedWeapons[(int)HeldSlot] != null)
                Weapons[(int)HeldSlot].BeginDraw(ResolvedWeapons[(int)HeldSlot]);
        }

        /// <summary>Marks the player dead. Does not decide the respawn time — that is the
        /// mode's call.</summary>
        public void Die()
        {
            Vitals.IsAlive = false;
            Vitals.Health = 0f;
            Score.Deaths++;
            Score.CurrentStreak = 0;
            Movement.Velocity = Vec3.Zero;
        }

        public void CreditKill(bool headshot)
        {
            Score.Kills++;
            if (headshot) Score.Headshots++;
            Score.CurrentStreak++;
            if (Score.CurrentStreak > Score.BestStreak) Score.BestStreak = Score.CurrentStreak;
        }
    }
}
