using System.Collections.Generic;
using Xunit;
using Salvo.Sim;

namespace Salvo.Sim.Tests
{
    public class ProgressionTests
    {
        // ---- the curve -------------------------------------------------------------------

        [Fact]
        public void TheCurveAndItsInverseAgreeAtEveryLevel()
        {
            // The boundary is where this matters: a player on exactly the experience for level
            // 20 must be level 20, and one experience point short must be level 19. A float
            // round-trip that is off by one there is off by one at the exact moment the player
            // is watching the bar fill.
            for (int level = 1; level <= XpCurve.MaxLevel; level++)
            {
                long exact = XpCurve.TotalXpForLevel(level);
                Assert.Equal(level, XpCurve.LevelForTotalXp(exact));
                if (level > 1)
                    Assert.Equal(level - 1, XpCurve.LevelForTotalXp(exact - 1));
                if (level < XpCurve.MaxLevel)
                    Assert.Equal(level, XpCurve.LevelForTotalXp(exact + 1));
            }
        }

        [Fact]
        public void EveryLevelCostsMoreThanTheOneBefore()
        {
            long previous = 0;
            for (int level = 1; level < XpCurve.MaxLevel; level++)
            {
                long cost = XpCurve.XpForNextLevel(level);
                Assert.True(cost > previous,
                            $"level {level}->{level + 1} costs {cost}, no more than the previous {previous}");
                previous = cost;
            }
        }

        [Fact]
        public void ProgressIsMonotonicAndStaysInRange()
        {
            float previous = -1f;
            long start = XpCurve.TotalXpForLevel(7);
            long end = XpCurve.TotalXpForLevel(8);
            for (long xp = start; xp <= end; xp += (end - start) / 50)
            {
                float progress = XpCurve.ProgressThroughLevel(xp);
                Assert.InRange(progress, 0f, 1f);
                if (xp < end) Assert.True(progress >= previous, "progress went backwards");
                previous = progress;
            }
        }

        [Fact]
        public void TheCapHoldsAndDoesNotOverflow()
        {
            Assert.Equal(XpCurve.MaxLevel, XpCurve.LevelForTotalXp(long.MaxValue / 4));
            Assert.Equal(0, XpCurve.XpForNextLevel(XpCurve.MaxLevel));
            Assert.Equal(1f, XpCurve.ProgressThroughLevel(long.MaxValue / 4));
            Assert.Equal(1, XpCurve.LevelForTotalXp(0));
            Assert.Equal(1, XpCurve.LevelForTotalXp(-500));
        }

        // ---- the fairness rule -----------------------------------------------------------

        [Fact]
        public void NoWeaponIsEverLockedBehindALevel()
        {
            // The rule this whole file exists to defend. Gating a weapon behind a level is a
            // competitive advantage granted for time served — the same thing the brief forbids
            // selling, at a slower price and invisible to anyone auditing a store.
            GameContent content = StarterContent.Build();
            UnlockTable table = StarterContent.BuildUnlocks();

            foreach (UnlockEntry entry in table.Entries)
                Assert.False(content.Weapons.Contains(entry.Id),
                             $"{entry.Id} is a weapon and is gated behind level {entry.Level}");
        }

        [Fact]
        public void EveryWeaponInEveryWorldIsUsableByABrandNewAccount()
        {
            // Stated from the player's side rather than the table's, because it is the property
            // that actually matters and it would survive someone replacing UnlockTable entirely.
            GameContent content = StarterContent.Build();
            var fresh = new PlayerProgress();
            fresh.GrantUnlocksFor(StarterContent.BuildUnlocks());

            Assert.Equal(1, fresh.Level);
            foreach (WeaponDefinition weapon in content.Weapons.All)
            {
                var loadout = Loadout.Default(weapon.Id, weapon.Id, weapon.Id);
                var resolver = new LoadoutResolver(content);
                Assert.NotNull(resolver.Resolve(loadout.Primary));
            }
        }

        [Fact]
        public void TheUnlockTableValidatesAgainstTheCatalogue()
        {
            List<string> problems = StarterContent.BuildUnlocks().Validate(StarterContent.Build());
            Assert.True(problems.Count == 0,
                        "unlock table has problems:\n  " + string.Join("\n  ", problems));
        }

        [Fact]
        public void ValidationRejectsAWeaponUnlock()
        {
            // Proves the check can fail, which is the only way to know it means anything.
            GameContent content = StarterContent.Build();
            var table = new UnlockTable();
            table.Add(new UnlockEntry(5, StarterContent.Weapons.Kestrel,
                                      "weapon.kestrel.name", UnlockKind.Cosmetic));

            List<string> problems = table.Validate(content);
            Assert.Contains(problems, p => p.Contains("is a weapon"));
        }

        [Fact]
        public void ValidationRejectsAnAttachmentWithNoDownside()
        {
            var weapons = new InMemoryCatalog<WeaponDefinition>();
            var attachments = new InMemoryCatalog<AttachmentDefinition>();
            attachments.Add("att.free_lunch", new AttachmentDefinition
            {
                Id = "att.free_lunch",
                DisplayNameKey = "attachment.free_lunch.name",
                Slot = AttachmentSlot.Barrel,
                RecoilMultiplier = 0.5f,       // better, and costs nothing
            });
            var content = new GameContent(
                weapons, attachments,
                new InMemoryCatalog<CharacterDefinition>(), new InMemoryCatalog<FactionDefinition>(),
                new InMemoryCatalog<MapDefinition>(), new InMemoryCatalog<WorldDefinition>(),
                new InMemoryCatalog<GameModeDefinition>(),
                new InMemoryCatalog<BotDifficultyDefinition>());

            var table = new UnlockTable();
            table.Add(new UnlockEntry(5, "att.free_lunch", "attachment.free_lunch.name",
                                      UnlockKind.Attachment));

            Assert.Contains(table.Validate(content), p => p.Contains("strictly better"));
        }

        [Fact]
        public void ValidationRejectsDuplicateAndOutOfRangeEntries()
        {
            GameContent content = StarterContent.Build();
            var table = new UnlockTable();
            table.Add(new UnlockEntry(2, "title.a", "title.a.name", UnlockKind.Title));
            table.Add(new UnlockEntry(9, "title.a", "title.a.name", UnlockKind.Title));
            table.Add(new UnlockEntry(0, "title.b", "title.b.name", UnlockKind.Title));
            table.Add(new UnlockEntry(4, "title.c", "", UnlockKind.Title));

            List<string> problems = table.Validate(content);
            Assert.Contains(problems, p => p.Contains("more than one level"));
            Assert.Contains(problems, p => p.Contains("outside"));
            Assert.Contains(problems, p => p.Contains("DisplayNameKey"));
        }

        // ---- granting --------------------------------------------------------------------

        [Fact]
        public void UnlocksAreGrantedByLevelAndGrantingTwiceChangesNothing()
        {
            UnlockTable table = StarterContent.BuildUnlocks();
            var progress = new PlayerProgress { TotalXp = XpCurve.TotalXpForLevel(7) };

            IReadOnlyList<UnlockEntry> first = progress.GrantUnlocksFor(table);
            Assert.NotEmpty(first);
            foreach (UnlockEntry entry in first) Assert.True(entry.Level <= 7);

            // Idempotent: a second call grants nothing new.
            Assert.Empty(progress.GrantUnlocksFor(table));

            Assert.True(progress.HasUnlocked(StarterContent.Attachments.Compensator));
            Assert.False(progress.HasUnlocked(StarterContent.Attachments.ExtendedMag));
        }

        [Fact]
        public void GrantingIsDerivedFromLevelNotFromHistory()
        {
            // A player restored from a backup, or granted experience out of band, must end up
            // with exactly the unlocks their level implies — not a set that depends on the order
            // things happened in.
            UnlockTable table = StarterContent.BuildUnlocks();

            var stepwise = new PlayerProgress();
            for (int level = 1; level <= 15; level++)
            {
                stepwise.TotalXp = XpCurve.TotalXpForLevel(level);
                stepwise.GrantUnlocksFor(table);
            }

            var atOnce = new PlayerProgress { TotalXp = XpCurve.TotalXpForLevel(15) };
            atOnce.GrantUnlocksFor(table);

            Assert.Equal(new SortedSet<string>(stepwise.Unlocked),
                         new SortedSet<string>(atOnce.Unlocked));
        }

        // ---- rewards ---------------------------------------------------------------------

        private static MatchSimulation PlayedMatch(out PlayerRuntime player, uint seed = 3)
        {
            GameContent content = StarterContent.Build();
            GameModeDefinition definition = content.GameModes.Get(StarterContent.Modes.TeamDeathmatch);
            MapDefinition map = content.Maps.Get(StarterContent.MapCrossfire);
            var match = new MatchSimulation(content, map, GameModes.Create(definition), seed);

            Loadouts.TryBuildDefault(content, map.WorldId, 0, out Loadout loadout);
            for (int i = 0; i < 6; i++)
                match.AddPlayer($"P{i}", i % 2 == 0 ? Team.Alpha : Team.Bravo, loadout,
                                isBot: true, botDifficulty: StarterContent.Difficulties.Normal);

            var director = new BotDirector(content, seed);
            match.Start();
            for (int i = 0; i < 120 * FixedClock.TicksPerSecond
                            && match.Phase != MatchPhase.MatchEnd; i++)
            {
                director.Think(match, FixedClock.TickInterval);
                match.Step();
            }
            player = match.Players[0];
            return match;
        }

        [Fact]
        public void RewardsAreEarnedForPlayingAtAll()
        {
            MatchSimulation match = PlayedMatch(out PlayerRuntime player);
            MatchRewards rewards = RewardRules.Compute(match, player);

            Assert.True(rewards.ParticipationXp > 0, "a full match earned no participation award");
            Assert.True(rewards.TotalXp > 0);
            Assert.Equal(player.Score.Kills, rewards.Kills);
            Assert.Equal(player.Score.Deaths, rewards.Deaths);
        }

        [Fact]
        public void ShowingUpAndLeavingEarnsNothing()
        {
            GameContent content = StarterContent.Build();
            GameModeDefinition definition = content.GameModes.Get(StarterContent.Modes.TeamDeathmatch);
            var match = new MatchSimulation(content, content.Maps.Get(StarterContent.MapCrossfire),
                                            GameModes.Create(definition), 1);
            Loadouts.TryBuildDefault(content, StarterContent.WorldModern, 0, out Loadout loadout);
            PlayerRuntime player = match.AddPlayer("Quitter", Team.Alpha, loadout);
            match.AddPlayer("Other", Team.Bravo, loadout);
            match.Start();
            for (int i = 0; i < 5 * FixedClock.TicksPerSecond; i++) match.Step();

            Assert.Equal(0, RewardRules.Compute(match, player).TotalXp);
        }

        [Fact]
        public void ParticipationOutweighsKillsForAnAverageMatch()
        {
            // The deliberate shape of the curve. A kill-weighted curve rewards the player who is
            // already winning and quietly teaches everyone that playing the objective costs them
            // something.
            var typical = new MatchRewards
            {
                Kills = 8, Assists = 4, Headshots = 1, SecondsPlayed = 480,
            };
            long killXp = typical.Kills * RewardRules.XpPerKill
                          + typical.Headshots * RewardRules.XpPerHeadshot;
            long participationXp = typical.SecondsPlayed * RewardRules.XpPerMinutePlayed / 60;

            Assert.True(participationXp > killXp,
                        $"participation {participationXp} does not outweigh kills {killXp} "
                        + "for an ordinary match");
        }

        [Fact]
        public void LosingCostsTheBonusButNeverTakesExperienceAway()
        {
            MatchSimulation match = PlayedMatch(out PlayerRuntime player);

            MatchRewards rewards = RewardRules.Compute(match, player);
            Assert.True(rewards.TotalXp >= 0);
            Assert.True(rewards.WinBonusXp == 0 || rewards.WinBonusXp == RewardRules.WinBonus);
            // Every component is non-negative: there is no path to a penalty.
            Assert.True(rewards.KillXp >= 0 && rewards.AssistXp >= 0
                        && rewards.ObjectiveXp >= 0 && rewards.ParticipationXp >= 0);
        }

        [Fact]
        public void ObjectiveWorkIsRewardedInTheObjectiveMode()
        {
            GameContent content = StarterContent.Build();
            GameModeDefinition definition = content.GameModes.Get(StarterContent.Modes.Overload);
            MapDefinition map = content.Maps.Get(StarterContent.MapCrossfire);
            var match = new MatchSimulation(content, map, GameModes.Create(definition), 11);
            Loadouts.TryBuildDefault(content, map.WorldId, 0, out Loadout loadout);
            for (int i = 0; i < 10; i++)
                match.AddPlayer($"P{i}", i % 2 == 0 ? Team.Alpha : Team.Bravo, loadout,
                                isBot: true, botDifficulty: StarterContent.Difficulties.Normal);

            var director = new BotDirector(content, 11);
            match.Start();
            for (int i = 0; i < 900 * FixedClock.TicksPerSecond
                            && match.Phase != MatchPhase.MatchEnd; i++)
            {
                director.Think(match, FixedClock.TickInterval);
                match.Step();
            }

            long objectiveXp = 0;
            foreach (PlayerRuntime player in match.Players)
                objectiveXp += RewardRules.Compute(match, player).ObjectiveXp;

            Assert.True(objectiveXp > 0,
                        "a whole objective match awarded no objective experience");
        }

        [Fact]
        public void AShotgunsAccuracyCannotExceedOneHundredPercent()
        {
            // A shotgun emits one Fired event and up to PelletsPerShot Damaged events, so
            // counting Damaged against Fired makes an eight-pellet weapon look 800% accurate.
            // Nothing errors; the number on the stats screen is simply wrong.
            GameContent content = StarterContent.Build();
            GameModeDefinition definition = content.GameModes.Get(StarterContent.Modes.TeamDeathmatch);
            MapDefinition map = content.Maps.Get(StarterContent.MapCrossfire);
            var match = new MatchSimulation(content, map, GameModes.Create(definition), 21);

            // Everyone on the shotgun, at close quarters, so pellets land in bunches.
            var loadout = Loadout.Default(StarterContent.Weapons.Anvil,
                                          StarterContent.Weapons.Pike,
                                          StarterContent.Weapons.Cleaver);
            for (int i = 0; i < 8; i++)
                match.AddPlayer($"P{i}", i % 2 == 0 ? Team.Alpha : Team.Bravo, loadout,
                                isBot: true, botDifficulty: StarterContent.Difficulties.Hard);

            var director = new BotDirector(content, 21);
            var progress = new PlayerProgress();
            match.Start();
            PlayerId watched = match.Players[0].Id;
            for (int i = 0; i < 180 * FixedClock.TicksPerSecond
                            && match.Phase != MatchPhase.MatchEnd; i++)
            {
                director.Think(match, FixedClock.TickInterval);
                match.Step();
                RewardRules.RecordEvents(progress, watched, match.Events, content);
            }

            WeaponStats stats = progress.StatsFor(StarterContent.Weapons.Anvil);
            Assert.True(stats.ShotsFired > 0, "the watched player never fired the shotgun");
            Assert.True(stats.ShotsHit > 0, "the watched player never landed a pellet");
            // The raw counts, not the accuracy figure. Accuracy clamps to 1 for safety, which
            // would make this test pass on exactly the bug it exists to catch.
            Assert.True(stats.ShotsHit <= stats.ShotsFired,
                        $"{stats.ShotsHit} pellets landed from {stats.ShotsFired} fired — "
                        + "hits are being counted against trigger pulls rather than projectiles");
        }

        [Fact]
        public void CareerAccumulatesAcrossMatches()
        {
            var progress = new PlayerProgress();
            var rewards = new MatchRewards
            {
                Won = true, Kills = 10, Deaths = 4, Assists = 3, Headshots = 2,
                SecondsPlayed = 600, BestStreak = 5,
                KillXp = 1000, ParticipationXp = 1200, WinBonusXp = 500,
            };

            progress.Apply(rewards);
            progress.Apply(rewards);

            Assert.Equal(2, progress.Career.MatchesPlayed);
            Assert.Equal(2, progress.Career.MatchesWon);
            Assert.Equal(20, progress.Career.Kills);
            Assert.Equal(5, progress.Career.BestKillStreak);
            Assert.Equal(1f, progress.Career.WinRate);
            Assert.Equal(rewards.TotalXp * 2, progress.TotalXp);
            Assert.True(progress.Level > 1, "5400 experience did not produce a level-up");
        }

        [Fact]
        public void WeaponStatsComeFromTheEventStream()
        {
            MatchSimulation match = PlayedMatch(out PlayerRuntime player);
            var progress = new PlayerProgress();

            // Replay a fresh match, folding events in as they happen.
            GameContent content = StarterContent.Build();
            GameModeDefinition definition = content.GameModes.Get(StarterContent.Modes.TeamDeathmatch);
            MapDefinition map = content.Maps.Get(StarterContent.MapCrossfire);
            var replay = new MatchSimulation(content, map, GameModes.Create(definition), 3);
            Loadouts.TryBuildDefault(content, map.WorldId, 0, out Loadout loadout);
            for (int i = 0; i < 6; i++)
                replay.AddPlayer($"P{i}", i % 2 == 0 ? Team.Alpha : Team.Bravo, loadout,
                                 isBot: true, botDifficulty: StarterContent.Difficulties.Normal);
            var director = new BotDirector(content, 3);
            replay.Start();
            PlayerId watched = replay.Players[0].Id;
            for (int i = 0; i < 120 * FixedClock.TicksPerSecond
                            && replay.Phase != MatchPhase.MatchEnd; i++)
            {
                director.Think(replay, FixedClock.TickInterval);
                replay.Step();
                RewardRules.RecordEvents(progress, watched, replay.Events, content);
            }

            WeaponStats stats = progress.StatsFor(loadout.Primary.WeaponId);
            Assert.True(stats.ShotsFired > 0, "no shots were attributed to the watched player");
            Assert.True(stats.ShotsHit <= stats.ShotsFired,
                        "more projectiles landed than were fired");
        }
    }
}
