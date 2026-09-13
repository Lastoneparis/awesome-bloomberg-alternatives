using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>
    /// A complete, playable catalogue built in code.
    /// </summary>
    /// <remarks>
    /// <b>Everything here is original.</b> No weapon, faction, character, map or mode is
    /// modelled on, named after, or laid out like any existing game's. The weapons are generic
    /// archetypes — a carbine, a submachine gun, a shotgun, a pistol — with invented
    /// designations, and the map is a symmetric arena built from primitives. The brief is
    /// explicit that this must be original IP, and content is where that is either honoured or
    /// broken.
    ///
    /// <para>This exists so the simulation can be played and tested before Unity is in the
    /// picture. It is not the shipping content pipeline: in the real game these come from
    /// ScriptableObjects in the editor and JSON on the server, both of which deserialise into
    /// exactly these types. Building the first catalogue in code proves the data model can
    /// express a real loadout before any asset has been authored against it.</para>
    ///
    /// <para>Every display string is a localisation key, never a literal (brief §22). The keys
    /// here have no translations yet; that is a Phase 12 task, and the keys are the contract it
    /// will be written against.</para>
    /// </remarks>
    public static class StarterContent
    {
        public const string WorldModern = "world.modern";

        public static class Weapons
        {
            public const string Kestrel = "wpn.kestrel";     // assault rifle
            public const string Hornet = "wpn.hornet";       // submachine gun
            public const string Anvil = "wpn.anvil";         // shotgun
            public const string Pike = "wpn.pike";           // sidearm
            public const string Cleaver = "wpn.cleaver";     // melee
        }

        public static class Attachments
        {
            public const string ShortScope = "att.short_scope";
            public const string Compensator = "att.compensator";
            public const string ExtendedMag = "att.extended_mag";
        }

        public static class Modes
        {
            public const string TeamDeathmatch = "mode.tdm";
            public const string FreeForAll = "mode.ffa";
            public const string Overload = "mode.overload";
        }

        public static class Difficulties
        {
            public const string Easy = "bot.easy";
            public const string Normal = "bot.normal";
            public const string Hard = "bot.hard";
            public const string Expert = "bot.expert";
        }

        public const string MapCrossfire = "map.junction";

        /// <summary>
        /// The modern era, behind the same interface every era uses.
        /// </summary>
        /// <remarks>
        /// A thin adapter over the builders already in this file rather than a move of them. The
        /// content itself did not need to change when a second era arrived, which is the claim
        /// <see cref="IWorldContent"/> exists to make — so rewriting it to prove the point would
        /// have undermined the point.
        /// </remarks>
        public sealed class ModernWorld : IWorldContent
        {
            public WorldDefinition World => new WorldDefinition
            {
                Id = WorldModern,
                DisplayNameKey = "world.modern.name",
                DescriptionKey = "world.modern.description",
                EraYear = 2020,
                WeaponPool = new ContentId[]
                {
                    Weapons.Kestrel, Weapons.Hornet, Weapons.Anvil, Weapons.Pike, Weapons.Cleaver,
                },
                Factions = new ContentId[] { "faction.meridian", "faction.ashwood" },
                Maps = new ContentId[] { MapCrossfire },
                UiThemeKey = "theme.modern",
                MusicKey = "music.modern",
                AmbienceKey = "ambience.urban",
            };

            IEnumerable<WeaponDefinition> IWorldContent.Weapons() => BuildWeapons();
            IEnumerable<AttachmentDefinition> IWorldContent.Attachments() => BuildAttachments();

            IEnumerable<FactionDefinition> IWorldContent.Factions()
            {
                var factions = new InMemoryCatalog<FactionDefinition>();
                var characters = new InMemoryCatalog<CharacterDefinition>();
                BuildFactions(factions, characters);
                return factions.All;
            }

            IEnumerable<CharacterDefinition> IWorldContent.Characters()
            {
                var factions = new InMemoryCatalog<FactionDefinition>();
                var characters = new InMemoryCatalog<CharacterDefinition>();
                BuildFactions(factions, characters);
                return characters.All;
            }

            IEnumerable<MapDefinition> IWorldContent.Maps() { yield return BuildJunction(); }
        }

        /// <summary>
        /// What each level grants. Weapons are absent on purpose — see <see cref="UnlockTable"/>.
        /// </summary>
        /// <remarks>
        /// Deliberately thin, and it should stay thin until there is real cosmetic content to
        /// hang on it. A long table of placeholder ids would validate cleanly and mean nothing;
        /// the value here is the shape and the rule, not the quantity.
        /// </remarks>
        public static UnlockTable BuildUnlocks()
        {
            var table = new UnlockTable();

            // Attachments are sidegrades — each already costs the player something, enforced by
            // AttachmentDefinition.Validate — so gating them behind a level changes which
            // trade-offs are available rather than how strong the player is.
            table.Add(new UnlockEntry(3, Attachments.Compensator,
                                      "attachment.compensator.name", UnlockKind.Attachment));
            table.Add(new UnlockEntry(6, Attachments.ShortScope,
                                      "attachment.short_scope.name", UnlockKind.Attachment));
            table.Add(new UnlockEntry(10, Attachments.ExtendedMag,
                                      "attachment.extended_mag.name", UnlockKind.Attachment));
            table.Add(new UnlockEntry(14, WartimeWorld.Attachments.Bipod,
                                      "attachment.bipod.name", UnlockKind.Attachment));
            table.Add(new UnlockEntry(18, WartimeWorld.Attachments.ExtendedStick,
                                      "attachment.extended_stick.name", UnlockKind.Attachment));

            // Titles and cosmetics never reach the simulation at all.
            table.Add(new UnlockEntry(2, "title.recruit", "title.recruit.name", UnlockKind.Title));
            table.Add(new UnlockEntry(8, "title.operator", "title.operator.name", UnlockKind.Title));
            table.Add(new UnlockEntry(20, "title.veteran", "title.veteran.name", UnlockKind.Title));
            table.Add(new UnlockEntry(5, "cosmetic.weapon_tint_slate",
                                      "cosmetic.weapon_tint_slate.name", UnlockKind.Cosmetic));
            table.Add(new UnlockEntry(12, "cosmetic.weapon_tint_ember",
                                      "cosmetic.weapon_tint_ember.name", UnlockKind.Cosmetic));

            return table;
        }

        /// <summary>Every era the game ships with. Adding one is adding a line here and a file.</summary>
        public static IEnumerable<IWorldContent> AllWorlds()
        {
            yield return new ModernWorld();
            yield return new WartimeWorld();
        }

        /// <summary>Builds the whole catalogue, ready to hand to a <see cref="MatchSimulation"/>.</summary>
        public static GameContent Build() =>
            ContentAssembler.Assemble(AllWorlds(), BuildModes(), BuildDifficulties());

        /// <summary>
        /// The modern era on its own.
        /// </summary>
        /// <remarks>
        /// Used by tests that want to assert something about one era without a second era's
        /// content changing the answer — and by anything that needs to prove a single world
        /// stands up alone, since a world that only validates alongside another is not modular.
        /// </remarks>
        public static GameContent BuildModernOnly() =>
            ContentAssembler.Assemble(new IWorldContent[] { new ModernWorld() },
                                      BuildModes(), BuildDifficulties());


        // ---- weapons -------------------------------------------------------------------

        private static IEnumerable<WeaponDefinition> BuildWeapons()
        {
            // A carbine: the baseline everything else is balanced against.
            yield return new WeaponDefinition
            {
                Id = Weapons.Kestrel,
                DisplayNameKey = "weapon.kestrel.name",
                Class = WeaponClass.AssaultRifle,
                FireMode = FireMode.Automatic,
                WorldId = WorldModern,
                BaseDamage = 24f,
                HeadshotMultiplier = 3.2f,
                FalloffStartMetres = 28f,
                FalloffEndMetres = 62f,
                FalloffFloor = 0.62f,
                ArmourPiercing = 0.35f,
                RoundsPerMinute = 620f,
                MagazineSize = 30,
                ReserveAmmo = 120,
                ReloadSeconds = 2.1f,
                EmptyReloadSeconds = 2.7f,
                DrawSeconds = 0.5f,
                HolsterSeconds = 0.35f,
                MaxRangeMetres = 120f,
                HipSpreadRadians = 0.021f,
                AdsSpreadRadians = 0.0018f,
                SpreadPerShot = 0.0045f,
                MaxSpreadRadians = 0.085f,
                SpreadRecoveryPerSecond = 0.16f,
                SpreadRecoveryDelaySeconds = 0.22f,
                MovingSpreadPenalty = 0.018f,
                AirborneSpreadPenalty = 0.07f,
                CrouchSpreadMultiplier = 0.7f,
                RecoilVerticalRadians = 0.0105f,
                RecoilHorizontalRadians = 0.004f,
                RecoilRecoveryPerSecond = 7f,
                // An authored pattern: up hard for the first few, then drifting left and right.
                // Learnable, which is the whole point of a pattern rather than random climb.
                SprayPattern = new[]
                {
                    new SprayPoint(0.2f, 0f), new SprayPoint(0.9f, 0.1f),
                    new SprayPoint(1.0f, -0.2f), new SprayPoint(1.0f, -0.5f),
                    new SprayPoint(0.9f, -0.8f), new SprayPoint(0.7f, -0.6f),
                    new SprayPoint(0.6f, 0.1f), new SprayPoint(0.5f, 0.7f),
                    new SprayPoint(0.45f, 1.0f), new SprayPoint(0.4f, 0.8f),
                    new SprayPoint(0.4f, 0.2f), new SprayPoint(0.35f, -0.5f),
                },
                AdsSeconds = 0.24f,
                AdsFovMultiplier = 0.75f,
                MoveSpeedMultiplier = 0.95f,
                AdsMoveSpeedMultiplier = 0.5f,
                Weight = 3.2f,
                ModelKey = "model.kestrel",
                FireSoundKey = "sfx.kestrel.fire",
                ReloadSoundKey = "sfx.kestrel.reload",
                SupportedAttachments = new[]
                {
                    AttachmentSlot.Optic, AttachmentSlot.Barrel, AttachmentSlot.Magazine,
                    AttachmentSlot.Grip,
                },
            };

            // Faster, weaker, much better up close: the counterplay to the carbine.
            yield return new WeaponDefinition
            {
                Id = Weapons.Hornet,
                DisplayNameKey = "weapon.hornet.name",
                Class = WeaponClass.SubmachineGun,
                FireMode = FireMode.Automatic,
                WorldId = WorldModern,
                BaseDamage = 17f,
                HeadshotMultiplier = 2.6f,
                FalloffStartMetres = 12f,
                FalloffEndMetres = 34f,
                FalloffFloor = 0.45f,
                ArmourPiercing = 0.2f,
                RoundsPerMinute = 860f,
                MagazineSize = 32,
                ReserveAmmo = 160,
                ReloadSeconds = 1.8f,
                EmptyReloadSeconds = 2.3f,
                DrawSeconds = 0.38f,
                HolsterSeconds = 0.28f,
                MaxRangeMetres = 90f,
                HipSpreadRadians = 0.026f,
                AdsSpreadRadians = 0.0035f,
                SpreadPerShot = 0.005f,
                MaxSpreadRadians = 0.1f,
                SpreadRecoveryPerSecond = 0.2f,
                SpreadRecoveryDelaySeconds = 0.18f,
                MovingSpreadPenalty = 0.01f,     // built to be fired on the move
                AirborneSpreadPenalty = 0.06f,
                CrouchSpreadMultiplier = 0.75f,
                RecoilVerticalRadians = 0.008f,
                RecoilHorizontalRadians = 0.006f,
                RecoilRecoveryPerSecond = 8.5f,
                AdsSeconds = 0.18f,
                MoveSpeedMultiplier = 1.03f,
                AdsMoveSpeedMultiplier = 0.62f,
                Weight = 2.4f,
                ModelKey = "model.hornet",
                FireSoundKey = "sfx.hornet.fire",
                ReloadSoundKey = "sfx.hornet.reload",
                SupportedAttachments = new[]
                {
                    AttachmentSlot.Optic, AttachmentSlot.Barrel, AttachmentSlot.Magazine,
                },
            };

            yield return new WeaponDefinition
            {
                Id = Weapons.Anvil,
                DisplayNameKey = "weapon.anvil.name",
                Class = WeaponClass.Shotgun,
                FireMode = FireMode.Pump,
                WorldId = WorldModern,
                BaseDamage = 13f,                // per pellet
                HeadshotMultiplier = 1.8f,       // low: eight pellets times three would be absurd
                FalloffStartMetres = 6f,
                FalloffEndMetres = 22f,
                FalloffFloor = 0.2f,
                ArmourPiercing = 0.1f,
                RoundsPerMinute = 72f,
                PelletsPerShot = 8,
                MagazineSize = 6,
                ReserveAmmo = 36,
                ReloadSeconds = 0.55f,
                EmptyReloadSeconds = 0.75f,
                ReloadsOneRoundAtATime = true,
                DrawSeconds = 0.6f,
                HolsterSeconds = 0.45f,
                MaxRangeMetres = 40f,
                HipSpreadRadians = 0.052f,
                AdsSpreadRadians = 0.036f,       // aiming tightens the pattern, never removes it
                SpreadPerShot = 0.004f,
                MaxSpreadRadians = 0.09f,
                SpreadRecoveryPerSecond = 0.3f,
                SpreadRecoveryDelaySeconds = 0.35f,
                MovingSpreadPenalty = 0.012f,
                AirborneSpreadPenalty = 0.05f,
                CrouchSpreadMultiplier = 0.85f,
                RecoilVerticalRadians = 0.03f,
                RecoilHorizontalRadians = 0.008f,
                RecoilRecoveryPerSecond = 6f,
                AdsSeconds = 0.3f,
                MoveSpeedMultiplier = 0.93f,
                AdsMoveSpeedMultiplier = 0.45f,
                Weight = 3.8f,
                ModelKey = "model.anvil",
                FireSoundKey = "sfx.anvil.fire",
                ReloadSoundKey = "sfx.anvil.reload",
                SupportedAttachments = new[] { AttachmentSlot.Optic, AttachmentSlot.Barrel },
            };

            yield return new WeaponDefinition
            {
                Id = Weapons.Pike,
                DisplayNameKey = "weapon.pike.name",
                Class = WeaponClass.Pistol,
                FireMode = FireMode.Semi,
                WorldId = WorldModern,
                BaseDamage = 28f,
                HeadshotMultiplier = 3.4f,
                FalloffStartMetres = 14f,
                FalloffEndMetres = 40f,
                FalloffFloor = 0.5f,
                ArmourPiercing = 0.25f,
                RoundsPerMinute = 420f,
                MagazineSize = 15,
                ReserveAmmo = 60,
                ReloadSeconds = 1.5f,
                EmptyReloadSeconds = 2.0f,
                DrawSeconds = 0.3f,
                HolsterSeconds = 0.22f,
                MaxRangeMetres = 80f,
                HipSpreadRadians = 0.018f,
                AdsSpreadRadians = 0.0025f,
                SpreadPerShot = 0.007f,
                MaxSpreadRadians = 0.075f,
                SpreadRecoveryPerSecond = 0.26f,
                SpreadRecoveryDelaySeconds = 0.2f,
                MovingSpreadPenalty = 0.013f,
                AirborneSpreadPenalty = 0.05f,
                CrouchSpreadMultiplier = 0.75f,
                RecoilVerticalRadians = 0.014f,
                RecoilHorizontalRadians = 0.005f,
                RecoilRecoveryPerSecond = 9f,
                AdsSeconds = 0.16f,
                MoveSpeedMultiplier = 1.05f,
                AdsMoveSpeedMultiplier = 0.7f,
                Weight = 1.1f,
                ModelKey = "model.pike",
                FireSoundKey = "sfx.pike.fire",
                ReloadSoundKey = "sfx.pike.reload",
                SupportedAttachments = new[] { AttachmentSlot.Optic, AttachmentSlot.Laser },
            };

            yield return new WeaponDefinition
            {
                Id = Weapons.Cleaver,
                DisplayNameKey = "weapon.cleaver.name",
                Class = WeaponClass.Melee,
                FireMode = FireMode.Semi,
                WorldId = WorldModern,
                BaseDamage = 55f,
                HeadshotMultiplier = 1.4f,
                FalloffStartMetres = 1.6f,
                FalloffEndMetres = 2.0f,
                FalloffFloor = 0f,       // nothing at all beyond arm's reach
                ArmourPiercing = 0.6f,
                RoundsPerMinute = 80f,
                MagazineSize = 1,
                ReserveAmmo = 0,
                ReloadSeconds = 0f,
                EmptyReloadSeconds = 0f,
                DrawSeconds = 0.25f,
                HolsterSeconds = 0.2f,
                MaxRangeMetres = 2.0f,
                HipSpreadRadians = 0.004f,
                AdsSpreadRadians = 0.004f,
                SpreadPerShot = 0f,
                MaxSpreadRadians = 0.02f,
                SpreadRecoveryPerSecond = 1f,
                SpreadRecoveryDelaySeconds = 0.05f,
                RecoilVerticalRadians = 0f,
                RecoilHorizontalRadians = 0f,
                RecoilRecoveryPerSecond = 10f,
                AdsSeconds = 0.1f,
                MoveSpeedMultiplier = 1.08f,
                AdsMoveSpeedMultiplier = 1f,
                Weight = 0.4f,
                ModelKey = "model.cleaver",
                FireSoundKey = "sfx.cleaver.swing",
                ReloadSoundKey = "sfx.cleaver.swing",
                SupportedAttachments = System.Array.Empty<AttachmentSlot>(),
            };
        }

        // ---- attachments ---------------------------------------------------------------

        private static IEnumerable<AttachmentDefinition> BuildAttachments()
        {
            // Every one of these has a downside. AttachmentDefinition.Validate rejects an
            // attachment that is strictly better than nothing, because an attachment with no
            // cost is not a choice — it is a buff to the base weapon that every player will
            // take, and it is how a cosmetic system quietly becomes pay-to-win.
            yield return new AttachmentDefinition
            {
                Id = Attachments.ShortScope,
                DisplayNameKey = "attachment.short_scope.name",
                Slot = AttachmentSlot.Optic,
                AdsSpreadMultiplier = 0.85f,
                AdsSpeedMultiplier = 0.88f,     // slower to bring up
                AdsFovMultiplier = 0.85f,       // and narrower once it is
                ModelKey = "model.att.short_scope",
            };

            yield return new AttachmentDefinition
            {
                Id = Attachments.Compensator,
                DisplayNameKey = "attachment.compensator.name",
                Slot = AttachmentSlot.Barrel,
                RecoilMultiplier = 0.82f,
                HipSpreadMultiplier = 1.1f,     // worse from the hip
                MoveSpeedMultiplier = 0.97f,
                ModelKey = "model.att.compensator",
            };

            yield return new AttachmentDefinition
            {
                Id = Attachments.ExtendedMag,
                DisplayNameKey = "attachment.extended_mag.name",
                Slot = AttachmentSlot.Magazine,
                MagazineSizeDelta = 10,
                ReloadSpeedMultiplier = 0.85f,  // slower to reload
                MoveSpeedMultiplier = 0.98f,
                ModelKey = "model.att.extended_mag",
            };
        }

        // ---- factions and characters ---------------------------------------------------

        private static void BuildFactions(InMemoryCatalog<FactionDefinition> factions,
                                          InMemoryCatalog<CharacterDefinition> characters)
        {
            // Two factions, identical in every way that touches the simulation. They differ in
            // name, colour and model only. A faction with better stats is pay-to-win wearing a
            // flag, and CharacterDefinition does not even have a stat field to give one.
            characters.Add("char.meridian_operator", new CharacterDefinition
            {
                Id = "char.meridian_operator",
                DisplayNameKey = "character.meridian_operator.name",
                FactionId = "faction.meridian",
                ModelKey = "model.char.meridian",
                VoiceKey = "voice.meridian",
            });
            characters.Add("char.ashwood_operator", new CharacterDefinition
            {
                Id = "char.ashwood_operator",
                DisplayNameKey = "character.ashwood_operator.name",
                FactionId = "faction.ashwood",
                ModelKey = "model.char.ashwood",
                VoiceKey = "voice.ashwood",
            });

            ContentId[] pool =
            {
                Weapons.Kestrel, Weapons.Hornet, Weapons.Anvil, Weapons.Pike, Weapons.Cleaver,
            };

            factions.Add("faction.meridian", new FactionDefinition
            {
                Id = "faction.meridian",
                DisplayNameKey = "faction.meridian.name",
                WorldId = WorldModern,
                Characters = new ContentId[] { "char.meridian_operator" },
                WeaponPool = pool,
                ColourRgb = 0x3F8FD8,
            });
            factions.Add("faction.ashwood", new FactionDefinition
            {
                Id = "faction.ashwood",
                DisplayNameKey = "faction.ashwood.name",
                WorldId = WorldModern,
                Characters = new ContentId[] { "char.ashwood_operator" },
                WeaponPool = pool,
                ColourRgb = 0xD8763F,
            });
        }

        // ---- modes ---------------------------------------------------------------------

        private static IEnumerable<GameModeDefinition> BuildModes()
        {
            yield return new GameModeDefinition
            {
                Id = Modes.TeamDeathmatch,
                DisplayNameKey = "mode.tdm.name",
                DescriptionKey = "mode.tdm.description",
                Kind = GameModeKind.TeamDeathmatch,
                MinPlayers = 2,
                MaxPlayers = 10,
                TeamSize = 5,
                IsTeamBased = true,
                ScoreLimit = 50,
                TimeLimitSeconds = 600f,
                WarmupSeconds = 5f,
                AllowsRespawn = true,
                RespawnDelaySeconds = 3f,
                SpawnProtectionSeconds = 1.5f,
                FriendlyFire = false,
                HealthRegenerates = true,
                RegenDelaySeconds = 5f,
                RegenPerSecond = 25f,
                StartingHealth = 100f,
                StartingArmour = 50f,
                FillWithBots = true,
            };

            yield return new GameModeDefinition
            {
                Id = Modes.FreeForAll,
                DisplayNameKey = "mode.ffa.name",
                DescriptionKey = "mode.ffa.description",
                Kind = GameModeKind.FreeForAll,
                MinPlayers = 2,
                MaxPlayers = 8,
                TeamSize = 1,
                IsTeamBased = false,
                ScoreLimit = 25,
                TimeLimitSeconds = 480f,
                WarmupSeconds = 5f,
                AllowsRespawn = true,
                RespawnDelaySeconds = 2.5f,
                SpawnProtectionSeconds = 2f,
                FriendlyFire = true,     // there are no friends
                HealthRegenerates = true,
                RegenDelaySeconds = 4.5f,
                RegenPerSecond = 30f,
                StartingHealth = 100f,
                StartingArmour = 0f,
                FillWithBots = true,
            };

            // The 5v5 format: rounds, no respawning inside one, an objective to attack and
            // defend. Numbers chosen so a round is decided by play rather than by the clock —
            // 115 s is long enough to take a site and short enough to punish stalling.
            yield return new GameModeDefinition
            {
                Id = Modes.Overload,
                DisplayNameKey = "mode.overload.name",
                DescriptionKey = "mode.overload.description",
                Kind = GameModeKind.RoundObjective,
                MinPlayers = 2,
                MaxPlayers = 10,
                TeamSize = 5,
                IsTeamBased = true,
                ScoreLimit = 0,
                TimeLimitSeconds = 0f,      // the rounds are the limit
                RoundsToWin = 7,            // first to 7, so at most 13 rounds
                RoundSeconds = 115f,
                WarmupSeconds = 5f,
                FreezeSeconds = 5f,
                AllowsRespawn = false,
                RespawnDelaySeconds = 0f,
                SpawnProtectionSeconds = 0f,   // nobody spawns mid-round, so nothing to protect
                FriendlyFire = true,           // the format's usual trade: coordination has a cost
                HealthRegenerates = false,     // damage carries through a round; that is the tension
                RegenDelaySeconds = 0f,
                RegenPerSecond = 0f,
                StartingHealth = 100f,
                StartingArmour = 50f,
                FillWithBots = true,
            };
        }

        // ---- bot difficulties ----------------------------------------------------------

        private static IEnumerable<BotDifficultyDefinition> BuildDifficulties()
        {
            // Read down any single column and it only ever gets better at playing, never
            // stronger. There is no damage multiplier here and no health bonus, because a bot
            // that hits harder is not a harder bot — it is a cheating one, and players can tell.
            yield return new BotDifficultyDefinition
            {
                Id = Difficulties.Easy,
                DisplayNameKey = "bot.easy.name",
                ReactionSeconds = 0.75f,
                AimErrorRadians = 0.075f,
                TurnSpeedRadiansPerSecond = 2.2f,
                TriggerDisciplineChance = 0.05f,
                ViewConeDegrees = 80f,
                SightRangeMetres = 32f,
                HearingRangeMetres = 12f,
                RetreatTendency = 0.15f,
                CoverPreference = 0.2f,
                ObjectiveFocus = 0.25f,
            };
            yield return new BotDifficultyDefinition
            {
                Id = Difficulties.Normal,
                DisplayNameKey = "bot.normal.name",
                ReactionSeconds = 0.45f,
                AimErrorRadians = 0.038f,
                TurnSpeedRadiansPerSecond = 4.0f,
                TriggerDisciplineChance = 0.2f,
                ViewConeDegrees = 105f,
                SightRangeMetres = 50f,
                HearingRangeMetres = 20f,
                RetreatTendency = 0.35f,
                CoverPreference = 0.45f,
                ObjectiveFocus = 0.5f,
            };
            yield return new BotDifficultyDefinition
            {
                Id = Difficulties.Hard,
                DisplayNameKey = "bot.hard.name",
                ReactionSeconds = 0.28f,
                AimErrorRadians = 0.019f,
                TurnSpeedRadiansPerSecond = 6.0f,
                TriggerDisciplineChance = 0.4f,
                ViewConeDegrees = 120f,
                SightRangeMetres = 65f,
                HearingRangeMetres = 26f,
                RetreatTendency = 0.5f,
                CoverPreference = 0.65f,
                ObjectiveFocus = 0.7f,
            };
            yield return new BotDifficultyDefinition
            {
                Id = Difficulties.Expert,
                DisplayNameKey = "bot.expert.name",
                // Still a fifth of a second of reaction and still a measurable aim error. An
                // Expert bot should feel like a strong player, which means it must remain
                // beatable by out-thinking it — a zero here would make it unbeatable by
                // definition, and BotDifficultyDefinition.Validate rejects that.
                ReactionSeconds = 0.18f,
                AimErrorRadians = 0.011f,
                TurnSpeedRadiansPerSecond = 8.5f,
                TriggerDisciplineChance = 0.6f,
                ViewConeDegrees = 140f,
                SightRangeMetres = 80f,
                HearingRangeMetres = 32f,
                RetreatTendency = 0.6f,
                CoverPreference = 0.8f,
                ObjectiveFocus = 0.85f,
            };
        }

        // ---- map -----------------------------------------------------------------------

        /// <summary>
        /// A symmetric arena: two spawn areas joined by three routes — a long open middle, a
        /// covered flank and a short connector.
        /// </summary>
        /// <remarks>
        /// Original layout, built from primitives. Symmetry is the point: an asymmetric map
        /// cannot be balanced without playtesting, and there is none of that yet, so neither
        /// side gets an advantage that would be mistaken for a bug in the simulation.
        /// </remarks>
        public static MapDefinition BuildJunction()
        {
            var map = new MapDefinition
            {
                Id = MapCrossfire,
                DisplayNameKey = "map.junction.name",
                WorldId = WorldModern,
                Bounds = new Aabb(new Vec3(-40f, -6f, -40f), new Vec3(40f, 26f, 40f)),
                SupportedModes = new[]
                {
                    GameModeKind.TeamDeathmatch, GameModeKind.FreeForAll, GameModeKind.RoundObjective,
                },
                RecommendedMinPlayers = 2,
                RecommendedMaxPlayers = 10,
            };

            void Box(float x0, float y0, float z0, float x1, float y1, float z1,
                     SurfaceKind surface = SurfaceKind.Concrete)
            {
                map.Brushes.Add(new MapBrush(new Aabb(new Vec3(x0, y0, z0), new Vec3(x1, y1, z1)),
                                             surface));
            }

            // Floor and a perimeter wall high enough that nothing can jump it.
            Box(-36f, -2f, -36f, 36f, 0f, 36f, SurfaceKind.Concrete);
            Box(-36f, 0f, 36f, 36f, 8f, 38f);
            Box(-36f, 0f, -38f, 36f, 8f, -36f);
            Box(-38f, 0f, -36f, -36f, 8f, 36f);
            Box(36f, 0f, -36f, 38f, 8f, 36f);

            // Centre structure: a raised platform reachable by ramps from both sides, so the
            // middle is contestable rather than simply a killing field.
            Box(-6f, 0f, -6f, 6f, 2.4f, 6f, SurfaceKind.Metal);
            for (int step = 0; step < 6; step++)
            {
                float y = step * 0.4f;
                Box(-6f, y, -6f - (step + 1) * 0.8f, 6f, y + 0.4f, -6f - step * 0.8f, SurfaceKind.Metal);
                Box(-6f, y, 6f + step * 0.8f, 6f, y + 0.4f, 6f + (step + 1) * 0.8f, SurfaceKind.Metal);
            }

            // Flank cover, mirrored across both axes.
            foreach (int sx in new[] { -1, 1 })
            {
                foreach (int sz in new[] { -1, 1 })
                {
                    Box(sx * 14f - 2f, 0f, sz * 14f - 2f, sx * 14f + 2f, 1.2f, sz * 14f + 2f,
                        SurfaceKind.Wood);
                    Box(sx * 24f - 1f, 0f, sz * 8f - 6f, sx * 24f + 1f, 3f, sz * 8f + 6f);
                }
            }

            // Waist-high cover along the long sightlines.
            for (int i = -2; i <= 2; i++)
            {
                Box(i * 8f - 1.5f, 0f, -28f, i * 8f + 1.5f, 1.1f, -26f, SurfaceKind.Wood);
                Box(i * 8f - 1.5f, 0f, 26f, i * 8f + 1.5f, 1.1f, 28f, SurfaceKind.Wood);
            }

            // Spawns: five a side, behind their own cover line, facing the middle.
            for (int i = 0; i < 5; i++)
            {
                float x = (i - 2) * 6f;
                map.Spawns.Add(new SpawnPoint(new Vec3(x, 0f, -32f), 0f, Team.Alpha, priority: 1));
                map.Spawns.Add(new SpawnPoint(new Vec3(x, 0f, 32f), 180f, Team.Bravo, priority: 1));
            }
            // Neutral spawns for free-for-all, out on the flanks.
            map.Spawns.Add(new SpawnPoint(new Vec3(-30f, 0f, 0f), 90f));
            map.Spawns.Add(new SpawnPoint(new Vec3(30f, 0f, 0f), 270f));
            map.Spawns.Add(new SpawnPoint(new Vec3(0f, 2.4f, 0f), 0f));

            // Two relay sites on the flanks, slightly into Bravo's half so that Alpha attacks
            // first. Placed in clear floor away from every brush above: a site a player cannot
            // stand in is a site nobody can ever contest.
            //
            // The offset from centre is small on purpose. An earlier placement put them at
            // z = 18, which is 14 m from the defenders' spawn and 50 m from the attackers'. The
            // mode still worked — the tests passed and average bots armed seven times a match —
            // but at higher bot skill the defenders simply arrived first and held, and the
            // attackers took one round in eight. Round-objective formats are meant to favour
            // the defenders; a 36 m head start is not favouring them, it is deciding it.
            map.Objectives.Add(new ObjectiveZone(0, "objective.junction.relay_a",
                                                 new Aabb(new Vec3(-17f, 0f, 5f),
                                                          new Vec3(-11f, 3f, 11f))));
            map.Objectives.Add(new ObjectiveZone(1, "objective.junction.relay_b",
                                                 new Aabb(new Vec3(11f, 0f, 5f),
                                                          new Vec3(17f, 3f, 11f))));
            return map;
        }
    }
}
