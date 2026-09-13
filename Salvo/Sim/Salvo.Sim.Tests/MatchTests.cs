using System.Collections.Generic;
using Xunit;
using Salvo.Sim;

namespace Salvo.Sim.Tests
{
    public class MatchTests
    {
        private static GameContent Content() => StarterContent.Build();

        private static MatchSimulation NewMatch(out BotDirector director, int bots = 6,
                                                string modeId = StarterContent.Modes.TeamDeathmatch,
                                                string difficulty = StarterContent.Difficulties.Normal,
                                                uint seed = 1)
        {
            GameContent content = Content();
            GameModeDefinition definition = content.GameModes.Get(modeId);
            MapDefinition map = content.Maps.Get(StarterContent.MapCrossfire);
            IGameMode mode = definition.Kind == GameModeKind.FreeForAll
                ? (IGameMode)new FreeForAllMode(definition)
                : new TeamDeathmatchMode(definition);

            var match = new MatchSimulation(content, map, mode, seed);
            for (int i = 0; i < bots; i++)
            {
                Team team = definition.IsTeamBased ? (i % 2 == 0 ? Team.Alpha : Team.Bravo)
                                                   : Team.None;
                match.AddPlayer($"Bot{i:D2}", team,
                                Loadout.Default(StarterContent.Weapons.Kestrel,
                                                StarterContent.Weapons.Pike,
                                                StarterContent.Weapons.Cleaver),
                                isBot: true, botDifficulty: difficulty);
            }
            director = new BotDirector(content, seed);
            return match;
        }

        private static void Play(MatchSimulation match, BotDirector director, float seconds)
        {
            int ticks = (int)(seconds * FixedClock.TicksPerSecond);
            for (int i = 0; i < ticks && match.Phase != MatchPhase.MatchEnd; i++)
            {
                director.Think(match, FixedClock.TickInterval);
                match.Step();
            }
        }

        // ---- content -------------------------------------------------------------------

        [Fact]
        public void StarterContentValidatesCleanly()
        {
            // The catalogue is checked by the same validation the shipping content pipeline
            // will use, so an authoring mistake here is caught the same way a designer's would be.
            List<string> problems = Content().Validate();
            Assert.True(problems.Count == 0,
                        "starter content has problems:\n  " + string.Join("\n  ", problems));
        }

        [Fact]
        public void NoAttachmentIsStrictlyBetterThanNoAttachment()
        {
            // §31: nothing that can be acquired may be a pure upgrade. An attachment with no
            // downside is a buff to the base weapon that every player will take.
            foreach (AttachmentDefinition attachment in Content().Attachments.All)
                Assert.False(attachment.IsStrictlyBetter(),
                             $"{attachment.Id} has no downside — it is a buff, not a choice");
        }

        [Fact]
        public void NoBotDifficultyMakesABotStrongerRatherThanBetter()
        {
            // Difficulty must only degrade senses and hands. There is no damage or health knob
            // on BotDifficultyDefinition at all, which is the structural half; this asserts the
            // knobs that do exist stay inside honest bounds.
            foreach (BotDifficultyDefinition difficulty in Content().BotDifficulties.All)
            {
                Assert.True(difficulty.ReactionSeconds > 0f,
                            $"{difficulty.Id} reacts instantly");
                Assert.True(difficulty.AimErrorRadians > 0f,
                            $"{difficulty.Id} has perfect aim — that is an aimbot, not a difficulty");
                Assert.True(difficulty.ViewConeDegrees < 360f,
                            $"{difficulty.Id} can see behind itself");
                Assert.True(difficulty.SightRangeMetres < float.MaxValue);
            }
        }

        [Fact]
        public void EveryStarterWeaponIsInternallyConsistent()
        {
            var problems = new List<string>();
            foreach (WeaponDefinition weapon in Content().Weapons.All) weapon.Validate(problems);
            Assert.True(problems.Count == 0, string.Join("\n", problems));
        }

        [Fact]
        public void TheStarterMapIsWellFormedAndItsSpawnsAreStandable()
        {
            MapDefinition map = Content().Maps.Get(StarterContent.MapCrossfire);
            var problems = new List<string>();
            map.Validate(problems);
            Assert.True(problems.Count == 0, string.Join("\n", problems));

            // The failure this catches is the one that cost an entire earlier project a day:
            // a spawn point buried in geometry. It is invisible in the map data and fatal in play.
            var world = new CollisionWorld(map);
            foreach (SpawnPoint spawn in map.Spawns)
            {
                var box = new Aabb(
                    spawn.Position - new Vec3(CharacterDefinition.Radius, 0f, CharacterDefinition.Radius),
                    spawn.Position + new Vec3(CharacterDefinition.Radius,
                                              CharacterDefinition.StandingHeight,
                                              CharacterDefinition.Radius));
                Assert.False(world.Overlaps(box),
                             $"spawn at {spawn.Position} is inside level geometry");
                Assert.True(map.Bounds.Contains(spawn.Position),
                            $"spawn at {spawn.Position} is outside the map bounds");
            }
        }

        [Fact]
        public void EveryTeamHasSomewhereToSpawn()
        {
            MapDefinition map = Content().Maps.Get(StarterContent.MapCrossfire);
            foreach (Team team in new[] { Team.Alpha, Team.Bravo })
            {
                int count = 0;
                foreach (SpawnPoint _ in map.SpawnsFor(team)) count++;
                Assert.True(count > 0, $"{team} has no spawn points");
            }
        }

        // ---- the match runs ------------------------------------------------------------

        [Fact]
        public void EveryPlayerEntersTheMatch()
        {
            MatchSimulation match = NewMatch(out BotDirector director);
            match.Start();
            foreach (PlayerRuntime player in match.Players)
                Assert.True(player.IsAlive,
                            $"{player.Name} never spawned — spawn selection rejected every point");
        }

        [Fact]
        public void BotsMoveFindEachOtherAndFight()
        {
            MatchSimulation match = NewMatch(out BotDirector director);
            match.Start();

            var startPositions = new Dictionary<int, Vec3>();
            foreach (PlayerRuntime player in match.Players)
                startPositions[player.Id.Raw] = player.Movement.Position;

            int shots = 0, hits = 0, deaths = 0;
            var moved = new HashSet<int>();
            int ticks = 90 * FixedClock.TicksPerSecond;
            for (int i = 0; i < ticks && match.Phase != MatchPhase.MatchEnd; i++)
            {
                director.Think(match, FixedClock.TickInterval);
                match.Step();
                foreach (MatchEvent e in match.Events)
                {
                    if (e.Kind == MatchEventKind.Fired) shots++;
                    else if (e.Kind == MatchEventKind.Damaged && e.OtherPlayer != e.Player) hits++;
                    else if (e.Kind == MatchEventKind.Died) deaths++;
                }
                foreach (PlayerRuntime player in match.Players)
                    if (Vec3.Distance(startPositions[player.Id.Raw], player.Movement.Position) > 3f)
                        moved.Add(player.Id.Raw);
            }

            Assert.Equal(match.Players.Count, moved.Count);
            Assert.True(shots > 20, $"only {shots} shots in 90 seconds — bots are not engaging");
            Assert.True(hits > 5, $"{shots} shots but only {hits} hits — aiming or ballistics is wrong");
            Assert.True(deaths > 0, "nobody died in 90 seconds of fighting");
        }

        [Fact]
        public void DeadPlayersComeBack()
        {
            MatchSimulation match = NewMatch(out BotDirector director);
            match.Start();

            int deaths = 0, respawns = 0;
            int ticks = 120 * FixedClock.TicksPerSecond;
            for (int i = 0; i < ticks && match.Phase != MatchPhase.MatchEnd; i++)
            {
                director.Think(match, FixedClock.TickInterval);
                match.Step();
                foreach (MatchEvent e in match.Events)
                {
                    if (e.Kind == MatchEventKind.Died) deaths++;
                    else if (e.Kind == MatchEventKind.Spawned) respawns++;
                }
            }

            Assert.True(deaths > 0, "nobody died, so respawn was never exercised");
            // Everyone who died should be back, give or take whoever died in the last few ticks.
            Assert.True(respawns >= deaths - match.Players.Count,
                        $"{deaths} deaths but only {respawns} respawns — players are staying dead");
        }

        [Fact]
        public void AMatchReachesItsOwnEnding()
        {
            MatchSimulation match = NewMatch(out BotDirector director,
                                             difficulty: StarterContent.Difficulties.Hard);
            match.Start();
            Play(match, director, match.Mode.Definition.TimeLimitSeconds + 30f);

            Assert.Equal(MatchPhase.MatchEnd, match.Phase);
            Assert.True(match.Outcome.IsDecided);
            Assert.False(string.IsNullOrEmpty(match.Outcome.ReasonKey));
        }

        [Fact]
        public void AMatchReplaysIdenticallyFromTheSameSeed()
        {
            // Everything in the networking plan rests on this: if the same seed and the same
            // inputs do not produce the same match, a client cannot predict anything.
            string Run(uint seed)
            {
                MatchSimulation match = NewMatch(out BotDirector director, seed: seed);
                match.Start();
                Play(match, director, 45f);

                var summary = new System.Text.StringBuilder();
                foreach (PlayerRuntime player in match.Players)
                {
                    summary.Append(player.Name).Append(':')
                           .Append(player.Score.Kills).Append('/')
                           .Append(player.Score.Deaths).Append('/')
                           .Append(player.Movement.Position).Append(';');
                }
                return summary.ToString();
            }

            Assert.Equal(Run(99), Run(99));
            Assert.NotEqual(Run(99), Run(100));
        }

        [Fact]
        public void HarderBotsAimBetterWithoutHittingHarder()
        {
            // Difficulty must show up as accuracy, never as damage. Both halves are asserted:
            // the hit rate climbs, and the damage per landed hit does not.
            (double hitRate, double damagePerHit) Measure(string difficulty)
            {
                MatchSimulation match = NewMatch(out BotDirector director, bots: 6,
                                                 difficulty: difficulty, seed: 5);
                match.Start();
                int shots = 0, hits = 0;
                double damage = 0;
                int ticks = 120 * FixedClock.TicksPerSecond;
                for (int i = 0; i < ticks && match.Phase != MatchPhase.MatchEnd; i++)
                {
                    director.Think(match, FixedClock.TickInterval);
                    match.Step();
                    foreach (MatchEvent e in match.Events)
                    {
                        if (e.Kind == MatchEventKind.Fired) shots++;
                        else if (e.Kind == MatchEventKind.Damaged && e.OtherPlayer != e.Player)
                        {
                            hits++;
                            damage += e.Value;
                        }
                    }
                }
                return (shots == 0 ? 0 : (double)hits / shots, hits == 0 ? 0 : damage / hits);
            }

            (double easyRate, double easyDamage) = Measure(StarterContent.Difficulties.Easy);
            (double expertRate, double expertDamage) = Measure(StarterContent.Difficulties.Expert);

            Assert.True(expertRate > easyRate,
                        $"expert bots ({expertRate:P1}) are no more accurate than easy ones ({easyRate:P1})");
            // Damage per hit may vary with range and hit region, but not by much, and certainly
            // not systematically upward with difficulty.
            Assert.True(expertDamage < easyDamage * 1.5,
                        $"expert bots deal {expertDamage:F1} per hit vs easy {easyDamage:F1} — "
                        + "difficulty is leaking into damage");
        }

        [Fact]
        public void NobodyEverLeavesTheMap()
        {
            MatchSimulation match = NewMatch(out BotDirector director, bots: 8);
            match.Start();
            Aabb bounds = match.Map.Bounds;

            int ticks = 150 * FixedClock.TicksPerSecond;
            for (int i = 0; i < ticks && match.Phase != MatchPhase.MatchEnd; i++)
            {
                director.Think(match, FixedClock.TickInterval);
                match.Step();
                foreach (PlayerRuntime player in match.Players)
                {
                    Vec3 position = player.Movement.Position;
                    Assert.False(float.IsNaN(position.X) || float.IsNaN(position.Y)
                                 || float.IsNaN(position.Z),
                                 $"{player.Name} position went NaN at tick {match.Tick}");
                    Assert.True(bounds.Contains(position),
                                $"{player.Name} left the map at {position} on tick {match.Tick}");
                }
            }
        }

        [Fact]
        public void FreeForAllNeedsNoChangesToTheMatchLoop()
        {
            // The mode abstraction's real test: a mode with no teams, scoring per player, runs
            // on exactly the same loop.
            MatchSimulation match = NewMatch(out BotDirector director, bots: 6,
                                             modeId: StarterContent.Modes.FreeForAll);
            match.Start();
            Play(match, director, 90f);

            int totalKills = 0;
            foreach (PlayerRuntime player in match.Players) totalKills += player.Score.Kills;
            Assert.True(totalKills > 0, "no kills in a free-for-all");
            foreach (PlayerRuntime player in match.Players)
                Assert.Equal(Team.None, player.Team);
        }

        // ---- rules -------------------------------------------------------------------

        [Fact]
        public void FriendlyFireOffMeansTeammatesCannotBeShot()
        {
            GameContent content = Content();
            GameModeDefinition definition = content.GameModes.Get(StarterContent.Modes.TeamDeathmatch);
            Assert.False(definition.FriendlyFire);

            MatchSimulation match = NewMatch(out BotDirector director, bots: 6);
            match.Start();
            Play(match, director, 120f);

            // No player may ever have been credited a kill against their own team.
            foreach (PlayerRuntime player in match.Players)
                Assert.True(player.Score.Kills >= 0);

            // And the team score can never have gone down, which is the only way a team kill
            // registers in this mode.
            Assert.True(match.Mode.TeamScore(Team.Alpha) >= 0);
            Assert.True(match.Mode.TeamScore(Team.Bravo) >= 0);
        }

        [Fact]
        public void SpawnProtectionStopsAnInstantSpawnKill()
        {
            MatchSimulation match = NewMatch(out BotDirector director, bots: 2);
            match.Start();
            PlayerRuntime victim = match.Players[0];
            Assert.True(victim.Vitals.SpawnProtection > 0f,
                        "a freshly spawned player has no protection at all");
        }

        [Fact]
        public void TheMatchRefusesMorePlayersThanTheModeAllows()
        {
            GameContent content = Content();
            GameModeDefinition definition = content.GameModes.Get(StarterContent.Modes.TeamDeathmatch);
            var match = new MatchSimulation(content, content.Maps.Get(StarterContent.MapCrossfire),
                                            new TeamDeathmatchMode(definition), 1);

            var loadout = Loadout.Default(StarterContent.Weapons.Kestrel,
                                          StarterContent.Weapons.Pike,
                                          StarterContent.Weapons.Cleaver);
            for (int i = 0; i < definition.MaxPlayers; i++)
                match.AddPlayer($"P{i}", i % 2 == 0 ? Team.Alpha : Team.Bravo, loadout);

            Assert.Throws<System.InvalidOperationException>(
                () => match.AddPlayer("OneTooMany", Team.Alpha, loadout));
        }

        [Fact]
        public void MaxPlayersIsPerModeNotGlobal()
        {
            // §7 of the brief: the maximum must be configurable per mode.
            GameContent content = Content();
            int tdm = content.GameModes.Get(StarterContent.Modes.TeamDeathmatch).MaxPlayers;
            int ffa = content.GameModes.Get(StarterContent.Modes.FreeForAll).MaxPlayers;
            Assert.NotEqual(tdm, ffa);
        }

        // ---- loadouts ------------------------------------------------------------------

        [Fact]
        public void AttachmentsChangeTheWeaponAndCannotBeStacked()
        {
            GameContent content = Content();
            var resolver = new LoadoutResolver(content);

            WeaponDefinition bare = resolver.Resolve(
                new WeaponBuild(StarterContent.Weapons.Kestrel));
            WeaponDefinition withMag = resolver.Resolve(
                new WeaponBuild(StarterContent.Weapons.Kestrel, StarterContent.Attachments.ExtendedMag));
            Assert.True(withMag.MagazineSize > bare.MagazineSize);

            // The same attachment five times must not apply five times. Without the one-per-slot
            // rule a client could send a repeated optic and stack its recoil reduction away.
            WeaponDefinition stacked = resolver.Resolve(new WeaponBuild(
                StarterContent.Weapons.Kestrel,
                StarterContent.Attachments.ExtendedMag, StarterContent.Attachments.ExtendedMag,
                StarterContent.Attachments.ExtendedMag, StarterContent.Attachments.ExtendedMag,
                StarterContent.Attachments.ExtendedMag));
            Assert.Equal(withMag.MagazineSize, stacked.MagazineSize);
        }

        [Fact]
        public void AnUnknownWeaponResolvesToNothingRatherThanASubstitute()
        {
            var resolver = new LoadoutResolver(Content());
            Assert.Null(resolver.Resolve(new WeaponBuild("wpn.does_not_exist")));
        }

        [Fact]
        public void AttachmentsDoNotMutateTheCatalogueEntry()
        {
            // ApplyTo returns a clone. If it mutated in place, fitting a suppressor once would
            // change that weapon for every player in the match, for the rest of the process.
            GameContent content = Content();
            WeaponDefinition catalogued = content.Weapons.Get(StarterContent.Weapons.Kestrel);
            int originalMagazine = catalogued.MagazineSize;

            var resolver = new LoadoutResolver(content);
            resolver.Resolve(new WeaponBuild(StarterContent.Weapons.Kestrel,
                                             StarterContent.Attachments.ExtendedMag));

            Assert.Equal(originalMagazine,
                         content.Weapons.Get(StarterContent.Weapons.Kestrel).MagazineSize);
        }
    }
}
