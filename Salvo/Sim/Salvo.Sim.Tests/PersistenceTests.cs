using System.Collections.Generic;
using Xunit;
using Salvo.Sim;

namespace Salvo.Sim.Tests
{
    /// <summary>
    /// Saving and loading. Weighted toward the failure cases, because save data is the one thing
    /// in a game that cannot be regenerated: a lost match is a bad evening, a lost account is a
    /// player who stops playing.
    /// </summary>
    public class PersistenceTests : System.IDisposable
    {
        private readonly string _directory;

        public PersistenceTests()
        {
            _directory = System.IO.Path.Combine(System.IO.Path.GetTempPath(),
                                                "salvo-tests-" + System.Guid.NewGuid().ToString("N"));
        }

        public void Dispose()
        {
            try { if (System.IO.Directory.Exists(_directory))
                      System.IO.Directory.Delete(_directory, recursive: true); }
            catch (System.Exception) { /* a temp directory left behind is not a test failure */ }
        }

        private static PlayerProgress Populated(string account = "acct.alice")
        {
            var progress = new PlayerProgress { AccountId = account, TotalXp = 48_500 };
            progress.Career = new CareerStats
            {
                MatchesPlayed = 142, MatchesWon = 77, Kills = 1683, Deaths = 1201,
                Assists = 449, Headshots = 312, ObjectivesCompleted = 58,
                DamageDealt = 214_505, SecondsPlayed = 92_400, BestKillStreak = 14,
            };
            progress.RecordWeapon(StarterContent.Weapons.Kestrel, _ => new WeaponStats
            {
                Kills = 812, Headshots = 190, DamageDealt = 98_400,
                ShotsFired = 21_500, ShotsHit = 9_120,
            });
            progress.RecordWeapon(WartimeWorld.Weapons.Warden, _ => new WeaponStats
            {
                Kills = 205, Headshots = 88, DamageDealt = 31_200,
                ShotsFired = 1_940, ShotsHit = 640,
            });
            progress.GrantUnlocksFor(StarterContent.BuildUnlocks());
            return progress;
        }

        private static void AssertSame(PlayerProgress expected, PlayerProgress actual)
        {
            Assert.Equal(expected.AccountId, actual.AccountId);
            Assert.Equal(expected.TotalXp, actual.TotalXp);
            Assert.Equal(expected.Level, actual.Level);

            Assert.Equal(expected.Career.MatchesPlayed, actual.Career.MatchesPlayed);
            Assert.Equal(expected.Career.MatchesWon, actual.Career.MatchesWon);
            Assert.Equal(expected.Career.Kills, actual.Career.Kills);
            Assert.Equal(expected.Career.Deaths, actual.Career.Deaths);
            Assert.Equal(expected.Career.Assists, actual.Career.Assists);
            Assert.Equal(expected.Career.Headshots, actual.Career.Headshots);
            Assert.Equal(expected.Career.ObjectivesCompleted, actual.Career.ObjectivesCompleted);
            Assert.Equal(expected.Career.DamageDealt, actual.Career.DamageDealt);
            Assert.Equal(expected.Career.SecondsPlayed, actual.Career.SecondsPlayed);
            Assert.Equal(expected.Career.BestKillStreak, actual.Career.BestKillStreak);

            Assert.Equal(new SortedSet<string>(expected.Unlocked),
                         new SortedSet<string>(actual.Unlocked));
            Assert.Equal(new SortedSet<string>(expected.WeaponIds),
                         new SortedSet<string>(actual.WeaponIds));
            foreach (string id in expected.WeaponIds)
            {
                WeaponStats a = expected.StatsFor(id), b = actual.StatsFor(id);
                Assert.Equal(a.Kills, b.Kills);
                Assert.Equal(a.Headshots, b.Headshots);
                Assert.Equal(a.DamageDealt, b.DamageDealt);
                Assert.Equal(a.ShotsFired, b.ShotsFired);
                Assert.Equal(a.ShotsHit, b.ShotsHit);
            }
        }

        // ---- round trip -------------------------------------------------------------------

        [Fact]
        public void EveryFieldSurvivesASaveAndLoad()
        {
            PlayerProgress original = Populated();
            var loaded = new PlayerProgress();
            Assert.True(SaveFormat.Read(SaveFormat.Write(original), loaded).Ok);
            AssertSame(original, loaded);
        }

        [Fact]
        public void TheSocialGraphSurvivesToo()
        {
            var graph = new SocialGraph();
            graph.SendRequest("acct.alice", "acct.bob");
            graph.Accept("acct.alice", "acct.bob");
            graph.SendRequest("acct.alice", "acct.carol");
            graph.Block("acct.alice", "acct.dan");

            string text = SaveFormat.Write(Populated(), graph);

            var restored = new SocialGraph();
            Assert.True(SaveFormat.Read(text, new PlayerProgress(), restored).Ok);

            Assert.True(restored.AreFriends("acct.alice", "acct.bob"));
            Assert.Contains("acct.carol", restored.OutgoingRequestsOf("acct.alice"));
            Assert.Contains("acct.dan", restored.BlockedBy("acct.alice"));
            Assert.False(restored.MayInteract("acct.alice", "acct.dan"));
        }

        [Fact]
        public void ABlockBeatsAFriendshipIfASaveSomehowClaimsBoth()
        {
            // Applying them in the other order would leave a friendship that the block was
            // supposed to have severed, which is the one direction this must not fail in.
            string text = "salvo-save 2\naccount acct.alice\nfriend acct.bob\nblock acct.bob\n";
            var graph = new SocialGraph();
            Assert.True(SaveFormat.Read(text, new PlayerProgress(), graph).Ok);

            Assert.False(graph.AreFriends("acct.alice", "acct.bob"));
            Assert.False(graph.MayInteract("acct.alice", "acct.bob"));
        }

        [Fact]
        public void TheSameStateAlwaysProducesTheSameBytes()
        {
            // A diffable save is how "my progress is being lost" gets answered in minutes.
            PlayerProgress progress = Populated();
            Assert.Equal(SaveFormat.Write(progress), SaveFormat.Write(progress));
        }

        [Fact]
        public void AnIdContainingSpacesOrNewlinesRoundTrips()
        {
            var original = new PlayerProgress { AccountId = "acct. odd\\name", TotalXp = 500 };
            original.RecordWeapon("wpn. with space", _ => new WeaponStats { Kills = 3 });

            var loaded = new PlayerProgress();
            Assert.True(SaveFormat.Read(SaveFormat.Write(original), loaded).Ok);
            Assert.Equal("acct. odd\\name", loaded.AccountId);
            Assert.Equal(3, loaded.StatsFor("wpn. with space").Kills);
        }

        [Fact]
        public void AnEmptyAccountIsANewPlayerNotAnError()
        {
            Assert.Equal(SaveReadStatus.Empty,
                         SaveFormat.Read("", new PlayerProgress()).Status);
            Assert.Equal(SaveReadStatus.Empty,
                         SaveFormat.Read(null, new PlayerProgress()).Status);
        }

        // ---- versions ---------------------------------------------------------------------

        [Fact]
        public void ASaveFromANewerBuildIsRefusedNotPartiallyRead()
        {
            // The behaviour that protects a player who briefly opens an old client. Reading what
            // we recognise and ignoring the rest destroys whatever the newer build added, the
            // moment the older one saves back over it.
            string future = $"salvo-save {SaveFormat.CurrentVersion + 5}\n"
                            + "account acct.alice\nxp 999999\ncareer.kills 5000\n";

            var progress = new PlayerProgress { AccountId = "acct.alice", TotalXp = 100 };
            SaveReadResult result = SaveFormat.Read(future, progress);

            Assert.Equal(SaveReadStatus.TooNew, result.Status);
            // And the existing record is untouched, not half-overwritten.
            Assert.Equal(100, progress.TotalXp);
        }

        [Fact]
        public void RubbishIsReportedCorruptRatherThanLoadedAsEmpty()
        {
            foreach (string rubbish in new[]
                     {
                         "this is not a save",
                         "salvo-save\n",
                         "salvo-save notanumber\naccount acct.a\n",
                         "salvo-save 0\naccount acct.a\n",
                     })
            {
                SaveReadResult result = SaveFormat.Read(rubbish, new PlayerProgress());
                Assert.Equal(SaveReadStatus.Corrupt, result.Status);
                Assert.False(string.IsNullOrEmpty(result.Detail), "corruption was not explained");
            }
        }

        [Fact]
        public void ACorruptSaveLeavesTheLiveRecordUntouched()
        {
            var progress = new PlayerProgress { AccountId = "acct.alice", TotalXp = 12_345 };
            Assert.Equal(SaveReadStatus.Corrupt,
                         SaveFormat.Read("salvo-save 2\naccount acct.b\nweapon w 1 2\n",
                                         progress).Status);
            Assert.Equal(12_345, progress.TotalXp);
            Assert.Equal("acct.alice", progress.AccountId);
        }

        [Fact]
        public void AnUnknownKeyInAKnownVersionIsSkippedNotRejected()
        {
            // Otherwise every additive change becomes a breaking one.
            string text = "salvo-save 2\naccount acct.alice\nxp 700\n"
                          + "challenge.daily.sniper 3\ncareer.kills 42\n";
            var loaded = new PlayerProgress();
            Assert.True(SaveFormat.Read(text, loaded).Ok);
            Assert.Equal(700, loaded.TotalXp);
            Assert.Equal(42, loaded.Career.Kills);
        }

        [Fact]
        public void AVersionOneSaveIsMigratedRatherThanRejected()
        {
            // v1 counted shots in trigger pulls, so a shotgun could record more hits than shots
            // and decode to an accuracy above 100%.
            string v1 = "salvo-save 1\naccount acct.alice\nxp 5000\n"
                        + "weapon wpn.anvil 40 2 9000 300 1900\n";

            var loaded = new PlayerProgress();
            Assert.True(SaveFormat.Read(v1, loaded).Ok);

            WeaponStats stats = loaded.StatsFor("wpn.anvil");
            Assert.InRange(stats.Accuracy, 0f, 1f);
            Assert.True(stats.ShotsHit <= stats.ShotsFired,
                        $"{stats.ShotsHit} hits from {stats.ShotsFired} shots survived migration");
            // Kills and damage are history and are not rewritten.
            Assert.Equal(40, stats.Kills);
            Assert.Equal(9000, stats.DamageDealt);
        }

        [Fact]
        public void MigrationLeavesAlreadyValidStatsAlone()
        {
            string v1 = "salvo-save 1\naccount acct.alice\nweapon wpn.kestrel 10 3 500 900 400\n";
            var loaded = new PlayerProgress();
            Assert.True(SaveFormat.Read(v1, loaded).Ok);

            WeaponStats stats = loaded.StatsFor("wpn.kestrel");
            Assert.Equal(900, stats.ShotsFired);
            Assert.Equal(400, stats.ShotsHit);
        }

        [Fact]
        public void AnUnlockKeptInASaveSurvivesTheTableChangingUnderIt()
        {
            // Someone who earned an item must not lose it because its level was later raised.
            string text = "salvo-save 2\naccount acct.alice\nxp 0\nunlock att.compensator\n";
            var loaded = new PlayerProgress();
            Assert.True(SaveFormat.Read(text, loaded).Ok);

            Assert.Equal(1, loaded.Level);
            Assert.True(loaded.HasUnlocked(StarterContent.Attachments.Compensator),
                        "an earned unlock was lost because the account is only level 1");
        }

        // ---- the file store ------------------------------------------------------------------

        [Fact]
        public void AnAccountSurvivesARoundTripThroughDisk()
        {
            var store = new FileAccountStore(_directory);
            PlayerProgress original = Populated();
            Assert.True(store.Save(original));
            Assert.True(store.Exists(original.AccountId));

            var loaded = new PlayerProgress();
            Assert.True(store.Load(original.AccountId, loaded).Ok);
            AssertSame(original, loaded);
        }

        [Fact]
        public void LoadingAnAccountThatDoesNotExistIsNotAnError()
        {
            var store = new FileAccountStore(_directory);
            Assert.Equal(SaveReadStatus.Empty,
                         store.Load("acct.newcomer", new PlayerProgress()).Status);
        }

        [Fact]
        public void ACorruptSaveIsRecoveredFromTheBackup()
        {
            // The outcome all of this exists to avoid is showing a level-one account to somebody
            // who was level forty. Losing one match of progress is survivable; losing all of it
            // is not.
            var store = new FileAccountStore(_directory);
            PlayerProgress first = Populated();
            Assert.True(store.Save(first));

            // A second save moves the first aside as a backup.
            PlayerProgress second = Populated();
            second.TotalXp += 5_000;
            Assert.True(store.Save(second));

            // Now destroy the primary, as a kill mid-write would.
            string path = System.IO.Directory.GetFiles(_directory, "*.sav")[0];
            System.IO.File.WriteAllText(path, "\0\0\0 half a file");

            var loaded = new PlayerProgress();
            SaveReadResult result = store.Load(first.AccountId, loaded);

            Assert.True(result.Ok, result.Detail);
            Assert.Equal(1, store.BackupRecoveries);
            Assert.Equal(first.TotalXp, loaded.TotalXp);   // the older, intact save
        }

        [Fact]
        public void AnInterruptedSaveLeavesThePreviousOneIntact()
        {
            // Writing straight into the live file means a crash partway through loses the
            // account. Games are killed by the operating system routinely.
            var store = new FileAccountStore(_directory);
            PlayerProgress original = Populated();
            Assert.True(store.Save(original));

            // Simulate the crash: a temp file left behind, live file untouched.
            System.IO.File.WriteAllText(
                System.IO.Path.Combine(_directory, "acct.alice.sav.tmp"), "half written");

            var loaded = new PlayerProgress();
            Assert.True(store.Load(original.AccountId, loaded).Ok);
            AssertSame(original, loaded);
        }

        [Fact]
        public void ASaveIsNeverLeftHalfWrittenInTheLiveFile()
        {
            var store = new FileAccountStore(_directory);
            PlayerProgress progress = Populated();
            store.Save(progress);

            foreach (string path in System.IO.Directory.GetFiles(_directory, "*.sav"))
            {
                var check = new PlayerProgress();
                Assert.True(SaveFormat.Read(System.IO.File.ReadAllText(path), check).Ok,
                            $"{path} is not a complete save");
            }
        }

        [Fact]
        public void AnAccountIdCannotEscapeTheSaveDirectory()
        {
            // A directory-traversal bug in the most security-sensitive file the game owns.
            var store = new FileAccountStore(_directory);
            var progress = new PlayerProgress { AccountId = "../../etc/passwd", TotalXp = 1 };
            Assert.True(store.Save(progress));

            foreach (string path in System.IO.Directory.GetFiles(_directory))
                Assert.StartsWith(System.IO.Path.GetFullPath(_directory),
                                  System.IO.Path.GetFullPath(path));
            Assert.True(System.IO.Directory.GetFiles(_directory).Length > 0);
        }

        [Fact]
        public void DistinctIdsDoNotCollideAfterSanitising()
        {
            var store = new FileAccountStore(_directory);
            store.Save(new PlayerProgress { AccountId = "a/b", TotalXp = 111 });
            store.Save(new PlayerProgress { AccountId = "a\\b", TotalXp = 222 });

            var first = new PlayerProgress();
            var second = new PlayerProgress();
            Assert.True(store.Load("a/b", first).Ok);
            Assert.True(store.Load("a\\b", second).Ok);
            Assert.Equal(111, first.TotalXp);
            Assert.Equal(222, second.TotalXp);
        }

        [Fact]
        public void DeletingAnAccountRemovesTheBackupToo()
        {
            // A deletion that leaves a recoverable backup is not a deletion.
            var store = new FileAccountStore(_directory);
            PlayerProgress progress = Populated();
            store.Save(progress);
            store.Save(progress);   // creates a backup

            Assert.True(store.Delete(progress.AccountId));
            Assert.False(store.Exists(progress.AccountId));
            Assert.Empty(System.IO.Directory.GetFiles(_directory));
            Assert.Equal(SaveReadStatus.Empty,
                         store.Load(progress.AccountId, new PlayerProgress()).Status);
        }

        [Fact]
        public void SavingAnAccountWithNoIdFailsRatherThanWritingSomewhereOdd()
        {
            var store = new FileAccountStore(_directory);
            Assert.False(store.Save(new PlayerProgress { AccountId = "" }));
            Assert.False(store.Save(null));
        }

        // ---- a full career round trip ---------------------------------------------------------

        [Fact]
        public void ACareerBuiltFromRealMatchesSurvivesARestart()
        {
            // End to end: play, earn, save, throw the process away, load, keep playing.
            GameContent content = StarterContent.Build();
            var store = new InMemoryAccountStore();
            UnlockTable unlocks = StarterContent.BuildUnlocks();

            var progress = new PlayerProgress { AccountId = "acct.career" };
            for (int match = 0; match < 6; match++)
            {
                progress.Apply(new MatchRewards
                {
                    Won = match % 2 == 0, Kills = 9, Deaths = 5, Assists = 3, Headshots = 2,
                    SecondsPlayed = 540, BestStreak = 4,
                    KillXp = 950, ParticipationXp = 1080, WinBonusXp = match % 2 == 0 ? 500 : 0,
                });
                progress.GrantUnlocksFor(unlocks);
                Assert.True(store.Save(progress));
            }

            int levelBefore = progress.Level;
            Assert.True(levelBefore > 1, "six matches produced no level-up");

            var afterRestart = new PlayerProgress();
            Assert.True(store.Load("acct.career", afterRestart).Ok);

            Assert.Equal(levelBefore, afterRestart.Level);
            Assert.Equal(6, afterRestart.Career.MatchesPlayed);
            Assert.Equal(54, afterRestart.Career.Kills);
            AssertSame(progress, afterRestart);

            // And it keeps accumulating rather than starting over.
            afterRestart.Apply(new MatchRewards { Kills = 5, ParticipationXp = 500 });
            Assert.Equal(7, afterRestart.Career.MatchesPlayed);
        }
    }
}
