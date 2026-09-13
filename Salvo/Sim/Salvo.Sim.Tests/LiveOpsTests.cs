using System.Collections.Generic;
using Xunit;
using Salvo.Sim;

namespace Salvo.Sim.Tests
{
    /// <summary>
    /// Content that changes without a client rebuild, and the gate that stops two machines
    /// quietly running different numbers.
    /// </summary>
    public class LiveOpsTests
    {
        private static GameContent Content() => StarterContent.Build();

        // ---- the fingerprint ---------------------------------------------------------------

        [Fact]
        public void TheSameContentAlwaysHashesTheSame()
        {
            // Built twice from scratch. If this ever drifts, every client is rejected after a
            // refactor that changed nothing a player could see.
            ContentManifest a = ContentManifest.Build(StarterContent.Build());
            ContentManifest b = ContentManifest.Build(StarterContent.Build());
            Assert.Equal(a.SimulationHash, b.SimulationHash);
            Assert.Equal(a.PresentationHash, b.PresentationHash);
        }

        [Fact]
        public void CatalogueOrderDoesNotChangeTheHash()
        {
            // A hash that depends on enumeration order is a hash that changes when someone
            // reorders a list, and stops meaning anything.
            GameContent forward = Content();
            var weapons = new List<WeaponDefinition>(forward.Weapons.All);
            weapons.Reverse();

            var reordered = new InMemoryCatalog<WeaponDefinition>();
            foreach (WeaponDefinition weapon in weapons) reordered.Add(weapon.Id, weapon);

            var shuffled = new GameContent(reordered, forward.Attachments, forward.Characters,
                                           forward.Factions, forward.Maps, forward.Worlds,
                                           forward.GameModes, forward.BotDifficulties);

            Assert.Equal(ContentManifest.Build(forward).SimulationHash,
                         ContentManifest.Build(shuffled).SimulationHash);
        }

        [Fact]
        public void ABalanceChangeMovesTheSimulationHash()
        {
            GameContent original = Content();
            ulong before = ContentManifest.Build(original).SimulationHash;

            WeaponDefinition tweaked = original.Weapons.Get(StarterContent.Weapons.Kestrel).Clone();
            tweaked.BaseDamage += 1f;
            ulong after = ContentManifest.Build(Replace(original, tweaked)).SimulationHash;

            Assert.NotEqual(before, after);
        }

        [Fact]
        public void EveryGameplayFieldIsCovered()
        {
            // One assertion per field would be unreadable; this walks the ones most likely to be
            // forgotten when someone adds a field and does not think about the manifest.
            GameContent original = Content();
            ulong baseline = ContentManifest.Build(original).SimulationHash;

            void MustChange(string what, System.Action<WeaponDefinition> mutate)
            {
                WeaponDefinition copy = original.Weapons.Get(StarterContent.Weapons.Kestrel).Clone();
                mutate(copy);
                Assert.True(ContentManifest.Build(Replace(original, copy)).SimulationHash != baseline,
                            $"changing {what} did not move the simulation hash — a client and a "
                            + "server could differ on it and still be allowed to play together");
            }

            MustChange("HeadshotMultiplier", w => w.HeadshotMultiplier += 0.5f);
            MustChange("MagazineSize", w => w.MagazineSize += 1);
            MustChange("RoundsPerMinute", w => w.RoundsPerMinute += 10f);
            MustChange("AdsSpreadRadians", w => w.AdsSpreadRadians *= 2f);
            MustChange("ArmourPiercing", w => w.ArmourPiercing = 0.9f);
            MustChange("FalloffEndMetres", w => w.FalloffEndMetres += 5f);
            MustChange("ReloadSeconds", w => w.ReloadSeconds += 0.1f);
            MustChange("MoveSpeedMultiplier", w => w.MoveSpeedMultiplier *= 1.1f);
            MustChange("SpreadRecoveryDelaySeconds", w => w.SpreadRecoveryDelaySeconds += 0.05f);
            MustChange("PelletsPerShot", w => w.PelletsPerShot += 1);
            MustChange("the spray pattern", w => w.SprayPattern = new[] { new SprayPoint(9f, 9f) });
        }

        [Fact]
        public void ATranslationFixDoesNotMoveTheSimulationHash()
        {
            // The other half of the split. If a display key moved the simulation hash, shipping
            // a typo fix would force the entire fleet to update at the same moment.
            GameContent original = Content();
            ContentManifest before = ContentManifest.Build(original);

            WeaponDefinition renamed = original.Weapons.Get(StarterContent.Weapons.Kestrel).Clone();
            renamed.DisplayNameKey = "weapon.kestrel.name.v2";
            ContentManifest after = ContentManifest.Build(Replace(original, renamed));

            Assert.Equal(before.SimulationHash, after.SimulationHash);
            Assert.NotEqual(before.PresentationHash, after.PresentationHash);
        }

        [Fact]
        public void MovingAWallMovesTheSimulationHash()
        {
            // Map geometry is simulation. A wall that exists on one machine and not the other
            // makes shots pass through cover on exactly one of them.
            GameContent original = Content();
            ulong before = ContentManifest.Build(original).SimulationHash;

            MapDefinition map = original.Maps.Get(StarterContent.MapCrossfire);
            var moved = new MapDefinition
            {
                Id = map.Id, DisplayNameKey = map.DisplayNameKey, WorldId = map.WorldId,
                Bounds = map.Bounds, SupportedModes = map.SupportedModes,
            };
            moved.Brushes.AddRange(map.Brushes);
            moved.Spawns.AddRange(map.Spawns);
            moved.Objectives.AddRange(map.Objectives);
            moved.Brushes[3] = new MapBrush(
                new Aabb(moved.Brushes[3].Box.Min + new Vec3(0.5f, 0f, 0f),
                         moved.Brushes[3].Box.Max + new Vec3(0.5f, 0f, 0f)),
                moved.Brushes[3].Surface);

            var maps = new InMemoryCatalog<MapDefinition>();
            foreach (MapDefinition m in original.Maps.All)
                maps.Add(m.Id, m.Id == moved.Id ? moved : m);

            var patched = new GameContent(original.Weapons, original.Attachments,
                                          original.Characters, original.Factions, maps,
                                          original.Worlds, original.GameModes,
                                          original.BotDifficulties);
            Assert.NotEqual(before, ContentManifest.Build(patched).SimulationHash);
        }

        // ---- the gate ------------------------------------------------------------------------

        [Fact]
        public void MatchingContentIsAllowedToPlay()
        {
            ContentManifest manifest = ContentManifest.Build(Content(), "1.2.0");
            ContentCheck check = ContentCompatibility.Check(manifest, manifest);
            Assert.Equal(ContentVerdict.Identical, check.Verdict);
            Assert.True(check.CanPlay);
        }

        [Fact]
        public void DifferingSimulationContentIsRefused()
        {
            GameContent original = Content();
            WeaponDefinition buffed = original.Weapons.Get(StarterContent.Weapons.Kestrel).Clone();
            buffed.BaseDamage *= 1.5f;

            ContentCheck check = ContentCompatibility.Check(
                ContentManifest.Build(original, "1.2.0"),
                ContentManifest.Build(Replace(original, buffed), "1.2.0"));

            Assert.Equal(ContentVerdict.Incompatible, check.Verdict);
            Assert.False(check.CanPlay);
            Assert.Equal("content.error.simulation_mismatch", check.ReasonKey);
        }

        [Fact]
        public void DifferingPresentationIsAllowedButReported()
        {
            GameContent original = Content();
            WeaponDefinition renamed = original.Weapons.Get(StarterContent.Weapons.Kestrel).Clone();
            renamed.DisplayNameKey = "weapon.kestrel.name.fr";

            ContentCheck check = ContentCompatibility.Check(
                ContentManifest.Build(original, "1.2.0"),
                ContentManifest.Build(Replace(original, renamed), "1.2.1"));

            Assert.Equal(ContentVerdict.PresentationDiffers, check.Verdict);
            Assert.True(check.CanPlay);
        }

        [Fact]
        public void AMissingManifestIsRefusedRatherThanAssumedFine()
        {
            ContentManifest manifest = ContentManifest.Build(Content());
            Assert.False(ContentCompatibility.Check(manifest, null).CanPlay);
            Assert.False(ContentCompatibility.Check(null, manifest).CanPlay);
        }

        [Fact]
        public void TheDescriptionNamesWhatDiffers()
        {
            GameContent original = Content();
            var patch = new ContentPatch { Version = "1.3.0" };
            patch.Weapons.Add(NewWeapon("wpn.season_two"));

            List<string> differences = ContentCompatibility.Describe(
                ContentManifest.Build(patch.ApplyTo(original), "1.3.0"),
                ContentManifest.Build(original, "1.2.0"));

            Assert.Contains(differences, d => d.StartsWith("version:"));
            Assert.Contains(differences, d => d.StartsWith("weapons:"));
        }

        [Fact]
        public void EqualCountsButDifferentValuesIsSaidPlainly()
        {
            GameContent original = Content();
            WeaponDefinition buffed = original.Weapons.Get(StarterContent.Weapons.Kestrel).Clone();
            buffed.BaseDamage *= 2f;

            List<string> differences = ContentCompatibility.Describe(
                ContentManifest.Build(original, "1.0.0"),
                ContentManifest.Build(Replace(original, buffed), "1.0.0"));

            Assert.Contains(differences, d => d.Contains("balance change reached one side"));
        }

        // ---- patching --------------------------------------------------------------------------

        [Fact]
        public void APatchAddsContentWithoutTouchingTheBase()
        {
            GameContent original = Content();
            int weaponsBefore = original.Weapons.All.Count;

            var patch = new ContentPatch { Version = "1.3.0" };
            patch.Weapons.Add(NewWeapon("wpn.season_two"));

            GameContent patched = patch.ApplyTo(original);

            Assert.Equal(weaponsBefore + 1, patched.Weapons.All.Count);
            Assert.True(patched.Weapons.Contains("wpn.season_two"));
            // The base is untouched, so it can still be served to clients that have not taken
            // the patch, and rolled back to.
            Assert.Equal(weaponsBefore, original.Weapons.All.Count);
            Assert.False(original.Weapons.Contains("wpn.season_two"));
        }

        [Fact]
        public void APatchCanRebalanceAnExistingWeapon()
        {
            GameContent original = Content();
            float before = original.Weapons.Get(StarterContent.Weapons.Kestrel).BaseDamage;

            WeaponDefinition nerfed = original.Weapons.Get(StarterContent.Weapons.Kestrel).Clone();
            nerfed.BaseDamage = before - 2f;
            var patch = new ContentPatch { Version = "1.3.1" };
            patch.Weapons.Add(nerfed);

            GameContent patched = patch.ApplyTo(original);

            Assert.Equal(before - 2f, patched.Weapons.Get(StarterContent.Weapons.Kestrel).BaseDamage);
            Assert.Equal(before, original.Weapons.Get(StarterContent.Weapons.Kestrel).BaseDamage);
            Assert.Equal(original.Weapons.All.Count, patched.Weapons.All.Count);
        }

        [Fact]
        public void APatchIsValidatedAgainstTheCatalogueItLandsOn()
        {
            // The interesting failures are relational: an attachment naming a weapon that does
            // not exist validates perfectly well on its own.
            GameContent original = Content();
            var patch = new ContentPatch { Version = "1.4.0" };
            patch.Attachments.Add(new AttachmentDefinition
            {
                Id = "att.season_two_grip",
                DisplayNameKey = "attachment.season_two_grip.name",
                Slot = AttachmentSlot.Grip,
                CompatibleWeapons = new ContentId[] { "wpn.never_existed" },
                RecoilMultiplier = 0.9f,
                MoveSpeedMultiplier = 0.97f,
            });

            List<string> problems = patch.ValidateAgainst(original);
            Assert.NotEmpty(problems);
        }

        [Fact]
        public void APatchAddingAModeNothingCanRunIsRejected()
        {
            // A patch ships data, not code. A mode kind with no IGameMode behind it would appear
            // in the menu and throw when chosen.
            GameContent original = Content();
            var patch = new ContentPatch { Version = "1.5.0" };
            patch.GameModes.Add(new GameModeDefinition
            {
                Id = "mode.domination",
                DisplayNameKey = "mode.domination.name",
                Kind = GameModeKind.Domination,
                MinPlayers = 2, MaxPlayers = 10, TeamSize = 5,
                ScoreLimit = 200, TimeLimitSeconds = 600f,
            });

            Assert.Contains(patch.ValidateAgainst(original),
                            p => p.Contains("has no implementation in this build"));
        }

        [Fact]
        public void AnEmptyPatchIsRejected()
        {
            Assert.Contains(new ContentPatch().ValidateAgainst(Content()),
                            p => p.Contains("empty"));
        }

        [Fact]
        public void AValidPatchProducesAPlayableCatalogue()
        {
            // The end of the argument: patched content runs a match.
            GameContent original = Content();
            WeaponDefinition seasonal = NewWeapon("wpn.season_two");
            var patch = new ContentPatch { Version = "1.3.0" };
            patch.Weapons.Add(seasonal);

            Assert.Empty(patch.ValidateAgainst(original));
            GameContent patched = patch.ApplyTo(original);

            GameModeDefinition definition = patched.GameModes.Get(StarterContent.Modes.TeamDeathmatch);
            MapDefinition map = patched.Maps.Get(StarterContent.MapCrossfire);
            var match = new MatchSimulation(patched, map, GameModes.Create(definition), 5);
            var loadout = Loadout.Default(seasonal.Id, StarterContent.Weapons.Pike,
                                          StarterContent.Weapons.Cleaver);
            for (int i = 0; i < 4; i++)
                match.AddPlayer($"P{i}", i % 2 == 0 ? Team.Alpha : Team.Bravo, loadout,
                                isBot: true, botDifficulty: StarterContent.Difficulties.Normal);

            var director = new BotDirector(patched, 5);
            match.Start();
            int shots = 0;
            for (int i = 0; i < 60 * FixedClock.TicksPerSecond
                            && match.Phase != MatchPhase.MatchEnd; i++)
            {
                director.Think(match, FixedClock.TickInterval);
                match.Step();
                foreach (MatchEvent e in match.Events)
                    if (e.Kind == MatchEventKind.Fired) shots++;
            }
            Assert.True(shots > 0, "nobody fired the patched-in weapon");
        }

        [Fact]
        public void PatchingChangesTheHashSoStaleClientsAreCaught()
        {
            GameContent original = Content();
            var patch = new ContentPatch { Version = "1.3.0" };
            patch.Weapons.Add(NewWeapon("wpn.season_two"));

            ContentCheck check = ContentCompatibility.Check(
                ContentManifest.Build(patch.ApplyTo(original), "1.3.0"),
                ContentManifest.Build(original, "1.2.0"));

            Assert.Equal(ContentVerdict.Incompatible, check.Verdict);
        }

        // ---- the handshake -------------------------------------------------------------------

        [Fact]
        public void TheServerRefusesAClientRunningDifferentWeaponStatistics()
        {
            GameContent content = Content();
            GameModeDefinition definition = content.GameModes.Get(StarterContent.Modes.TeamDeathmatch);
            var match = new MatchSimulation(content, content.Maps.Get(StarterContent.MapCrossfire),
                                            GameModes.Create(definition), 1);
            var server = new NetServer(match, ContentManifest.Build(content, "1.0.0"));

            Loadouts.TryBuildDefault(content, StarterContent.WorldModern, 0, out Loadout loadout);
            PlayerRuntime honest = match.AddPlayer("Honest", Team.Alpha, loadout);
            PlayerRuntime stale = match.AddPlayer("Stale", Team.Bravo, loadout);

            Assert.True(server.AddClient(honest.Id, SimulatedLink.Perfect(), SimulatedLink.Perfect(),
                                         ContentManifest.Build(content, "1.0.0")).CanPlay);

            WeaponDefinition different = content.Weapons.Get(StarterContent.Weapons.Kestrel).Clone();
            different.BaseDamage += 5f;
            ContentCheck refused = server.AddClient(stale.Id, SimulatedLink.Perfect(),
                                                    SimulatedLink.Perfect(),
                                                    ContentManifest.Build(Replace(content, different), "1.0.0"));

            Assert.False(refused.CanPlay);
            Assert.Equal(1, server.RejectedClients);
        }

        [Fact]
        public void AClientThatPresentsNoManifestIsRefused()
        {
            // An old build that does not know to send one is exactly the client this exists for,
            // so absence must not read as agreement.
            ContentManifest manifest = ContentManifest.Build(Content(), "1.0.0");
            Assert.False(ContentCompatibility.Check(manifest, null).CanPlay);
        }

        [Fact]
        public void AClientWithOnlyADifferentTranslationIsStillAdmitted()
        {
            GameContent content = Content();
            GameModeDefinition definition = content.GameModes.Get(StarterContent.Modes.TeamDeathmatch);
            var match = new MatchSimulation(content, content.Maps.Get(StarterContent.MapCrossfire),
                                            GameModes.Create(definition), 1);
            var server = new NetServer(match, ContentManifest.Build(content, "1.0.0"));

            Loadouts.TryBuildDefault(content, StarterContent.WorldModern, 0, out Loadout loadout);
            PlayerRuntime player = match.AddPlayer("Translated", Team.Alpha, loadout);

            WeaponDefinition renamed = content.Weapons.Get(StarterContent.Weapons.Kestrel).Clone();
            renamed.DisplayNameKey = "weapon.kestrel.name.de";

            ContentCheck check = server.AddClient(player.Id, SimulatedLink.Perfect(),
                                                  SimulatedLink.Perfect(),
                                                  ContentManifest.Build(Replace(content, renamed), "1.0.1"));
            Assert.True(check.CanPlay);
            Assert.Equal(ContentVerdict.PresentationDiffers, check.Verdict);
            Assert.Equal(0, server.RejectedClients);
        }

        // ---- helpers -----------------------------------------------------------------------

        private static GameContent Replace(GameContent content, WeaponDefinition weapon)
        {
            var weapons = new InMemoryCatalog<WeaponDefinition>();
            foreach (WeaponDefinition w in content.Weapons.All)
                weapons.Add(w.Id, w.Id == weapon.Id ? weapon : w);
            return new GameContent(weapons, content.Attachments, content.Characters,
                                   content.Factions, content.Maps, content.Worlds,
                                   content.GameModes, content.BotDifficulties);
        }

        private static WeaponDefinition NewWeapon(ContentId id) => new WeaponDefinition
        {
            Id = id,
            DisplayNameKey = "weapon.season_two.name",
            Class = WeaponClass.AssaultRifle,
            FireMode = FireMode.Automatic,
            WorldId = StarterContent.WorldModern,
            BaseDamage = 25f,
            HeadshotMultiplier = 3f,
            FalloffStartMetres = 26f,
            FalloffEndMetres = 60f,
            FalloffFloor = 0.6f,
            ArmourPiercing = 0.3f,
            RoundsPerMinute = 600f,
            MagazineSize = 30,
            ReserveAmmo = 120,
            ReloadSeconds = 2.1f,
            EmptyReloadSeconds = 2.7f,
            MaxRangeMetres = 110f,
            HipSpreadRadians = 0.021f,
            AdsSpreadRadians = 0.002f,
            SpreadPerShot = 0.0045f,
            MaxSpreadRadians = 0.085f,
            SpreadRecoveryPerSecond = 0.16f,
            SpreadRecoveryDelaySeconds = 0.22f,
        };
    }
}
