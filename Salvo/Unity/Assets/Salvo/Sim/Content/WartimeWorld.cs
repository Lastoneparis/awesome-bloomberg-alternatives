using System;
using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>
    /// A 1940s era: bolt-action rifles, iron sights, stone and timber.
    /// </summary>
    /// <remarks>
    /// This world exists to answer one question: can an era be added without touching the
    /// engine? PROJECT_PLAN.md puts it plainly — if adding a second era requires changes in
    /// <c>Movement/</c>, <c>Combat/</c>, <c>Modes/</c>, <c>AI/</c> or <c>Net/</c>, the design has
    /// failed. So this file is content and nothing else, and it deliberately pushes on the parts
    /// of the data model that the modern era never exercised:
    ///
    /// <list type="bullet">
    /// <item>A bolt-action, which fires far slower than anything modern and needs the trigger
    /// released between shots — <see cref="FireMode.Bolt"/> and a very low rate of fire.</item>
    /// <item>A weapon that reloads round by round, which the modern era only used on a shotgun
    /// and which here is a rifle with a five-round magazine.</item>
    /// <item>Iron sights only: an optic slot with no optics in it, so an era can simply not
    /// offer a category of attachment rather than needing a flag to disable one.</item>
    /// <item>Damage high enough that two hits kill, which stresses the armour split from the
    /// opposite direction to the modern era's faster, weaker weapons.</item>
    /// </list>
    ///
    /// <para><b>Originality.</b> No real weapon, unit, nation, insignia or place name appears
    /// here. The factions are invented, the weapons are invented designations for generic
    /// archetypes, and the map is a stone quarry rather than a recreation of anywhere. The era
    /// is "the 1940s" in the way a western is "the 1880s": a visual and mechanical register,
    /// not a depiction of a real conflict. <see cref="WorldDefinition.EraYear"/> is used for
    /// sorting and UI only — no gameplay branches on it.</para>
    /// </remarks>
    public sealed class WartimeWorld : IWorldContent
    {
        public const string Id = "world.wartime";

        public static class Weapons
        {
            public const string Warden = "wpn.warden";       // bolt-action rifle
            public const string Thistle = "wpn.thistle";     // submachine gun
            public const string Ridgeback = "wpn.ridgeback"; // semi-automatic rifle
            public const string Kettle = "wpn.kettle";       // sidearm
            public const string Spade = "wpn.spade";         // melee
        }

        public static class Attachments
        {
            public const string Bipod = "att.bipod";
            public const string ExtendedStick = "att.extended_stick";
        }

        public const string MapQuarry = "map.quarry";

        public WorldDefinition World => new WorldDefinition
        {
            Id = Id,
            DisplayNameKey = "world.wartime.name",
            DescriptionKey = "world.wartime.description",
            EraYear = 1944,
            WeaponPool = new ContentId[]
            {
                Weapons.Warden, Weapons.Thistle, Weapons.Ridgeback, Weapons.Kettle, Weapons.Spade,
            },
            Factions = new ContentId[] { "faction.ironvale", "faction.sablewood" },
            Maps = new ContentId[] { MapQuarry },
            UiThemeKey = "theme.wartime",
            MusicKey = "music.wartime",
            AmbienceKey = "ambience.quarry",
        };

        IEnumerable<WeaponDefinition> IWorldContent.Weapons() => BuildWeapons();

        private static IEnumerable<WeaponDefinition> BuildWeapons()
        {
            // A bolt-action: one shot, then work the bolt. Very high damage, very low rate, and
            // the trigger must be released between shots. Five rounds, loaded one at a time.
            yield return new WeaponDefinition
            {
                Id = Weapons.Warden,
                DisplayNameKey = "weapon.warden.name",
                Class = WeaponClass.SniperRifle,
                FireMode = FireMode.Bolt,
                WorldId = Id,
                BaseDamage = 78f,
                HeadshotMultiplier = 2.0f,      // already near-lethal; 3x would be a one-shot body
                FalloffStartMetres = 60f,
                FalloffEndMetres = 120f,
                FalloffFloor = 0.85f,           // barely falls off; that is the point of a rifle
                ArmourPiercing = 0.6f,
                RoundsPerMinute = 48f,
                MagazineSize = 5,
                ReserveAmmo = 40,
                ReloadSeconds = 0.9f,
                EmptyReloadSeconds = 1.1f,
                ReloadsOneRoundAtATime = true,
                DrawSeconds = 0.75f,
                HolsterSeconds = 0.5f,
                MaxRangeMetres = 160f,
                HipSpreadRadians = 0.055f,      // hopeless from the hip, by design
                AdsSpreadRadians = 0.0006f,
                SpreadPerShot = 0.012f,
                MaxSpreadRadians = 0.11f,
                SpreadRecoveryPerSecond = 0.35f,
                SpreadRecoveryDelaySeconds = 0.9f,
                MovingSpreadPenalty = 0.03f,
                AirborneSpreadPenalty = 0.1f,
                CrouchSpreadMultiplier = 0.55f,
                RecoilVerticalRadians = 0.042f,
                RecoilHorizontalRadians = 0.006f,
                RecoilRecoveryPerSecond = 4f,
                AdsSeconds = 0.42f,
                AdsFovMultiplier = 0.5f,
                MoveSpeedMultiplier = 0.9f,
                AdsMoveSpeedMultiplier = 0.35f,
                Weight = 4.2f,
                ModelKey = "model.warden",
                FireSoundKey = "sfx.warden.fire",
                ReloadSoundKey = "sfx.warden.reload",
                // No optic slot at all. An era that has not invented a red dot does not need a
                // flag to disable one — it simply does not list the slot.
                SupportedAttachments = new[] { AttachmentSlot.Grip, AttachmentSlot.Stock },
            };

            yield return new WeaponDefinition
            {
                Id = Weapons.Thistle,
                DisplayNameKey = "weapon.thistle.name",
                Class = WeaponClass.SubmachineGun,
                FireMode = FireMode.Automatic,
                WorldId = Id,
                BaseDamage = 21f,
                HeadshotMultiplier = 2.4f,
                FalloffStartMetres = 10f,
                FalloffEndMetres = 28f,
                FalloffFloor = 0.4f,
                ArmourPiercing = 0.18f,
                RoundsPerMinute = 540f,         // slower than a modern SMG, and it kicks harder
                MagazineSize = 32,
                ReserveAmmo = 128,
                ReloadSeconds = 2.6f,
                EmptyReloadSeconds = 3.2f,
                DrawSeconds = 0.5f,
                HolsterSeconds = 0.36f,
                MaxRangeMetres = 70f,
                HipSpreadRadians = 0.034f,
                AdsSpreadRadians = 0.008f,      // iron sights are not precision instruments
                SpreadPerShot = 0.0075f,
                MaxSpreadRadians = 0.12f,
                SpreadRecoveryPerSecond = 0.22f,
                SpreadRecoveryDelaySeconds = 0.26f,
                MovingSpreadPenalty = 0.016f,
                AirborneSpreadPenalty = 0.08f,
                CrouchSpreadMultiplier = 0.72f,
                RecoilVerticalRadians = 0.014f,
                RecoilHorizontalRadians = 0.009f,
                RecoilRecoveryPerSecond = 6.5f,
                AdsSeconds = 0.26f,
                MoveSpeedMultiplier = 0.98f,
                AdsMoveSpeedMultiplier = 0.55f,
                Weight = 3.4f,
                ModelKey = "model.thistle",
                FireSoundKey = "sfx.thistle.fire",
                ReloadSoundKey = "sfx.thistle.reload",
                SupportedAttachments = new[] { AttachmentSlot.Magazine, AttachmentSlot.Stock },
            };

            yield return new WeaponDefinition
            {
                Id = Weapons.Ridgeback,
                DisplayNameKey = "weapon.ridgeback.name",
                Class = WeaponClass.Marksman,
                FireMode = FireMode.Semi,
                WorldId = Id,
                BaseDamage = 41f,
                HeadshotMultiplier = 2.6f,
                FalloffStartMetres = 35f,
                FalloffEndMetres = 80f,
                FalloffFloor = 0.7f,
                ArmourPiercing = 0.45f,
                RoundsPerMinute = 300f,
                MagazineSize = 8,
                ReserveAmmo = 64,
                ReloadSeconds = 2.2f,
                EmptyReloadSeconds = 2.4f,
                DrawSeconds = 0.6f,
                HolsterSeconds = 0.42f,
                MaxRangeMetres = 130f,
                HipSpreadRadians = 0.03f,
                AdsSpreadRadians = 0.0025f,
                SpreadPerShot = 0.009f,
                MaxSpreadRadians = 0.1f,
                SpreadRecoveryPerSecond = 0.3f,
                SpreadRecoveryDelaySeconds = 0.28f,
                MovingSpreadPenalty = 0.022f,
                AirborneSpreadPenalty = 0.09f,
                CrouchSpreadMultiplier = 0.65f,
                RecoilVerticalRadians = 0.024f,
                RecoilHorizontalRadians = 0.006f,
                RecoilRecoveryPerSecond = 5.5f,
                AdsSeconds = 0.32f,
                MoveSpeedMultiplier = 0.93f,
                AdsMoveSpeedMultiplier = 0.45f,
                Weight = 3.9f,
                ModelKey = "model.ridgeback",
                FireSoundKey = "sfx.ridgeback.fire",
                ReloadSoundKey = "sfx.ridgeback.reload",
                SupportedAttachments = new[] { AttachmentSlot.Stock, AttachmentSlot.Grip },
            };

            yield return new WeaponDefinition
            {
                Id = Weapons.Kettle,
                DisplayNameKey = "weapon.kettle.name",
                Class = WeaponClass.Pistol,
                FireMode = FireMode.Semi,
                WorldId = Id,
                BaseDamage = 33f,
                HeadshotMultiplier = 2.8f,
                FalloffStartMetres = 10f,
                FalloffEndMetres = 30f,
                FalloffFloor = 0.45f,
                ArmourPiercing = 0.3f,
                RoundsPerMinute = 330f,
                MagazineSize = 8,
                ReserveAmmo = 40,
                ReloadSeconds = 1.9f,
                EmptyReloadSeconds = 2.4f,
                DrawSeconds = 0.34f,
                HolsterSeconds = 0.24f,
                MaxRangeMetres = 60f,
                HipSpreadRadians = 0.024f,
                AdsSpreadRadians = 0.004f,
                SpreadPerShot = 0.011f,
                MaxSpreadRadians = 0.09f,
                SpreadRecoveryPerSecond = 0.3f,
                SpreadRecoveryDelaySeconds = 0.24f,
                MovingSpreadPenalty = 0.015f,
                AirborneSpreadPenalty = 0.06f,
                CrouchSpreadMultiplier = 0.78f,
                RecoilVerticalRadians = 0.019f,
                RecoilHorizontalRadians = 0.006f,
                RecoilRecoveryPerSecond = 7.5f,
                AdsSeconds = 0.2f,
                MoveSpeedMultiplier = 1.04f,
                AdsMoveSpeedMultiplier = 0.68f,
                Weight = 1.3f,
                ModelKey = "model.kettle",
                FireSoundKey = "sfx.kettle.fire",
                ReloadSoundKey = "sfx.kettle.reload",
                SupportedAttachments = Array.Empty<AttachmentSlot>(),
            };

            yield return new WeaponDefinition
            {
                Id = Weapons.Spade,
                DisplayNameKey = "weapon.spade.name",
                Class = WeaponClass.Melee,
                FireMode = FireMode.Semi,
                WorldId = Id,
                BaseDamage = 62f,
                HeadshotMultiplier = 1.5f,
                FalloffStartMetres = 1.7f,
                FalloffEndMetres = 2.1f,
                FalloffFloor = 0f,
                ArmourPiercing = 0.55f,
                RoundsPerMinute = 70f,
                MagazineSize = 1,
                ReserveAmmo = 0,
                ReloadSeconds = 0f,
                EmptyReloadSeconds = 0f,
                DrawSeconds = 0.3f,
                HolsterSeconds = 0.22f,
                MaxRangeMetres = 2.1f,
                HipSpreadRadians = 0.005f,
                AdsSpreadRadians = 0.005f,
                SpreadPerShot = 0f,
                MaxSpreadRadians = 0.02f,
                SpreadRecoveryPerSecond = 1f,
                SpreadRecoveryDelaySeconds = 0.05f,
                RecoilVerticalRadians = 0f,
                RecoilHorizontalRadians = 0f,
                RecoilRecoveryPerSecond = 10f,
                AdsSeconds = 0.12f,
                MoveSpeedMultiplier = 1.06f,
                AdsMoveSpeedMultiplier = 1f,
                Weight = 0.9f,
                ModelKey = "model.spade",
                FireSoundKey = "sfx.spade.swing",
                ReloadSoundKey = "sfx.spade.swing",
                SupportedAttachments = Array.Empty<AttachmentSlot>(),
            };
        }

        IEnumerable<AttachmentDefinition> IWorldContent.Attachments()
        {
            // Era-appropriate, and both cost something. AttachmentDefinition.Validate rejects an
            // attachment with no downside, which is the structural half of "nothing acquired is
            // a pure upgrade".
            yield return new AttachmentDefinition
            {
                Id = Attachments.Bipod,
                DisplayNameKey = "attachment.bipod.name",
                Slot = AttachmentSlot.Grip,
                CompatibleWeapons = new ContentId[] { Weapons.Warden, Weapons.Ridgeback },
                RecoilMultiplier = 0.7f,
                AdsSpreadMultiplier = 0.85f,
                MoveSpeedMultiplier = 0.93f,     // it is heavy and it catches on everything
                AdsSpeedMultiplier = 0.85f,
                ModelKey = "model.att.bipod",
            };

            yield return new AttachmentDefinition
            {
                Id = Attachments.ExtendedStick,
                DisplayNameKey = "attachment.extended_stick.name",
                Slot = AttachmentSlot.Magazine,
                CompatibleWeapons = new ContentId[] { Weapons.Thistle },
                MagazineSizeDelta = 18,
                ReloadSpeedMultiplier = 0.78f,
                MoveSpeedMultiplier = 0.97f,
                ModelKey = "model.att.extended_stick",
            };
        }

        IEnumerable<FactionDefinition> IWorldContent.Factions()
        {
            // Invented, and identical in every way the simulation can see. A faction that shoots
            // harder is pay-to-win wearing a flag, and CharacterDefinition has no stat field to
            // give one even if someone tried.
            ContentId[] pool =
            {
                Weapons.Warden, Weapons.Thistle, Weapons.Ridgeback, Weapons.Kettle, Weapons.Spade,
            };

            yield return new FactionDefinition
            {
                Id = "faction.ironvale",
                DisplayNameKey = "faction.ironvale.name",
                WorldId = Id,
                Characters = new ContentId[] { "char.ironvale_rifleman" },
                WeaponPool = pool,
                ColourRgb = 0x6E8B3D,
            };
            yield return new FactionDefinition
            {
                Id = "faction.sablewood",
                DisplayNameKey = "faction.sablewood.name",
                WorldId = Id,
                Characters = new ContentId[] { "char.sablewood_rifleman" },
                WeaponPool = pool,
                ColourRgb = 0x7A5C3E,
            };
        }

        IEnumerable<CharacterDefinition> IWorldContent.Characters()
        {
            yield return new CharacterDefinition
            {
                Id = "char.ironvale_rifleman",
                DisplayNameKey = "character.ironvale_rifleman.name",
                FactionId = "faction.ironvale",
                ModelKey = "model.char.ironvale",
                VoiceKey = "voice.ironvale",
            };
            yield return new CharacterDefinition
            {
                Id = "char.sablewood_rifleman",
                DisplayNameKey = "character.sablewood_rifleman.name",
                FactionId = "faction.sablewood",
                ModelKey = "model.char.sablewood",
                VoiceKey = "voice.sablewood",
            };
        }

        IEnumerable<MapDefinition> IWorldContent.Maps() { yield return BuildQuarry(); }

        /// <summary>
        /// A worked stone quarry: a sunken floor, terraced ledges, and a covered loading shed.
        /// </summary>
        /// <remarks>
        /// Deliberately a different shape from the modern map rather than a reskin. Junction is
        /// flat and symmetric with a raised middle; this is a bowl with height on the rim, so
        /// the long sightlines run downhill and the safe routes hug the terraces. If the engine
        /// only worked on flat symmetric arenas, this is where that would show.
        /// </remarks>
        public static MapDefinition BuildQuarry()
        {
            var map = new MapDefinition
            {
                Id = MapQuarry,
                DisplayNameKey = "map.quarry.name",
                WorldId = Id,
                Bounds = new Aabb(new Vec3(-44f, -12f, -44f), new Vec3(44f, 28f, 44f)),
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

            // The quarry floor, sunk four metres below the rim.
            Box(-34f, -6f, -34f, 34f, -4f, 34f, SurfaceKind.Dirt);

            // The rim: a raised walkway around the whole pit, reached by ramps at each corner.
            Box(-40f, -6f, -40f, 40f, 0f, -34f, SurfaceKind.Sand);
            Box(-40f, -6f, 34f, 40f, 0f, 40f, SurfaceKind.Sand);
            Box(-40f, -6f, -34f, -34f, 0f, 34f, SurfaceKind.Sand);
            Box(34f, -6f, -34f, 40f, 0f, 34f, SurfaceKind.Sand);

            // Terraces stepping down from the rim into the pit, on two opposite sides. Each step
            // is under the movement model's step height, so they are walked rather than jumped.
            for (int step = 0; step < 10; step++)
            {
                float y = -0.4f * step;
                float inner = 34f - (step + 1) * 2.2f;
                float outer = 34f - step * 2.2f;
                Box(-20f, -6f, inner, 20f, y, outer, SurfaceKind.Sand);
                Box(-20f, -6f, -outer, 20f, y, -inner, SurfaceKind.Sand);
            }

            // Perimeter wall, tall enough that the rim is not a sniper's balcony onto the world.
            Box(-42f, 0f, -42f, 42f, 10f, -40f);
            Box(-42f, 0f, 40f, 42f, 10f, 42f);
            Box(-42f, 0f, -40f, -40f, 10f, 40f);
            Box(40f, 0f, -40f, 42f, 10f, 40f);

            // A covered loading shed in the pit: the only hard cover down there, and the reason
            // to go down at all.
            Box(-9f, -4f, -7f, 9f, -3.6f, 7f, SurfaceKind.Wood);          // floor slab
            Box(-9f, -4f, -7f, -8f, -0.5f, 7f, SurfaceKind.Wood);         // west wall
            Box(8f, -4f, -7f, 9f, -0.5f, 7f, SurfaceKind.Wood);           // east wall
            Box(-9f, -1f, -7f, 9f, -0.5f, 7f, SurfaceKind.Wood);          // roof
            // Stacked blocks for cover in the open pit.
            foreach (int sx in new[] { -1, 1 })
            {
                foreach (int sz in new[] { -1, 1 })
                {
                    Box(sx * 20f - 2f, -4f, sz * 18f - 2f, sx * 20f + 2f, -2.6f, sz * 18f + 2f);
                    Box(sx * 26f - 3f, -4f, sz * 6f - 3f, sx * 26f + 3f, -1.8f, sz * 6f + 3f);
                }
            }

            // Spawns on opposite rims, facing in and down.
            for (int i = 0; i < 5; i++)
            {
                float x = (i - 2) * 7f;
                map.Spawns.Add(new SpawnPoint(new Vec3(x, 0f, -37f), 0f, Team.Alpha, priority: 1));
                map.Spawns.Add(new SpawnPoint(new Vec3(x, 0f, 37f), 180f, Team.Bravo, priority: 1));
            }
            map.Spawns.Add(new SpawnPoint(new Vec3(-37f, 0f, 0f), 90f));
            map.Spawns.Add(new SpawnPoint(new Vec3(37f, 0f, 0f), 270f));

            // Objective sites: one inside the shed, one out on the open floor. Deliberately
            // asymmetric in character rather than in distance — both are about as far from each
            // spawn, but taking the open one is a different problem from taking the covered one.
            map.Objectives.Add(new ObjectiveZone(0, "objective.quarry.shed",
                                                 new Aabb(new Vec3(-4f, -3.6f, -3f),
                                                          new Vec3(2f, -0.6f, 3f))));
            map.Objectives.Add(new ObjectiveZone(1, "objective.quarry.floor",
                                                 new Aabb(new Vec3(17f, -4f, -3f),
                                                          new Vec3(23f, -1f, 3f))));
            return map;
        }
    }
}
