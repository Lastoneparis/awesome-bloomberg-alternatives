using System.Collections.Generic;
using Xunit;
using Salvo.Sim;

namespace Salvo.Sim.Tests
{
    /// <summary>
    /// The round-based 5v5 format. Worth its own file because it is the first mode that
    /// exercises rounds, freeze time, elimination, a carried objective and a side swap — none of
    /// which team deathmatch or free-for-all touch, so none of which had ever run.
    /// </summary>
    public class OverloadTests
    {
        private static GameContent Content() => StarterContent.Build();

        private static MatchSimulation NewMatch(out OverloadMode mode, int players = 10,
                                                uint seed = 1)
        {
            GameContent content = Content();
            GameModeDefinition definition = content.GameModes.Get(StarterContent.Modes.Overload);
            MapDefinition map = content.Maps.Get(StarterContent.MapCrossfire);
            mode = new OverloadMode(definition);

            var match = new MatchSimulation(content, map, mode, seed);
            var loadout = Loadout.Default(StarterContent.Weapons.Kestrel,
                                          StarterContent.Weapons.Pike,
                                          StarterContent.Weapons.Cleaver);
            for (int i = 0; i < players; i++)
                match.AddPlayer($"P{i:D2}", i % 2 == 0 ? Team.Alpha : Team.Bravo, loadout);
            return match;
        }

        /// <summary>Steps the match, holding every player still except those given a command.</summary>
        private static void Run(MatchSimulation match, int ticks,
                                System.Action<MatchSimulation, int> perTick = null)
        {
            for (int i = 0; i < ticks && match.Phase != MatchPhase.MatchEnd; i++)
            {
                perTick?.Invoke(match, i);
                match.Step();
            }
        }

        // ---- content -------------------------------------------------------------------

        [Fact]
        public void TheModeDefinitionIsCoherent()
        {
            GameModeDefinition definition = Content().GameModes.Get(StarterContent.Modes.Overload);
            var problems = new List<string>();
            definition.Validate(problems);
            Assert.Empty(problems);

            Assert.True(definition.IsRoundBased);
            Assert.False(definition.AllowsRespawn);
            Assert.Equal(5, definition.TeamSize);
            Assert.Equal(10, definition.MaxPlayers);
        }

        [Fact]
        public void TheMapHasTwoStandableSitesAndBothAreReachableFloorSpace()
        {
            MapDefinition map = Content().Maps.Get(StarterContent.MapCrossfire);
            Assert.Equal(2, map.Objectives.Count);

            var world = new CollisionWorld(map);
            foreach (ObjectiveZone zone in map.Objectives)
            {
                // A site buried in geometry is a site nobody can ever contest, and it would look
                // exactly like the bots ignoring the objective.
                Vec3 feet = new Vec3(zone.Centre.X, zone.Volume.Min.Y, zone.Centre.Z);
                var box = new Aabb(
                    feet - new Vec3(CharacterDefinition.Radius, 0f, CharacterDefinition.Radius),
                    feet + new Vec3(CharacterDefinition.Radius,
                                    CharacterDefinition.StandingHeight,
                                    CharacterDefinition.Radius));
                Assert.False(world.Overlaps(box), $"{zone.NameKey} is inside level geometry");
                Assert.True(zone.Contains(feet),
                            $"{zone.NameKey} does not contain a player standing at its own centre");
            }
        }

        [Fact]
        public void GameModesCreateReturnsTheRoundBasedImplementation()
        {
            GameModeDefinition definition = Content().GameModes.Get(StarterContent.Modes.Overload);
            Assert.IsType<OverloadMode>(GameModes.Create(definition));
        }

        [Fact]
        public void AnUnimplementedModeKindFailsLoudlyRatherThanBecomingDeathmatch()
        {
            var definition = new GameModeDefinition
            {
                Id = "mode.unbuilt", DisplayNameKey = "x", Kind = GameModeKind.Domination,
            };
            Assert.Throws<System.NotSupportedException>(() => GameModes.Create(definition));
        }

        // ---- the round lifecycle ---------------------------------------------------------

        [Fact]
        public void AMatchStartsFrozenAndThenGoesLive()
        {
            MatchSimulation match = NewMatch(out OverloadMode mode);
            match.Start();
            Assert.Equal(MatchPhase.Freeze, match.Phase);
            Assert.Equal(1, match.RoundNumber);

            // Frozen players cannot move, however hard they push.
            Vec3 before = match.Players[0].Movement.Position;
            Run(match, 64, (m, _) =>
            {
                foreach (PlayerRuntime player in m.Players)
                    m.SubmitInput(player.Id, TestWorlds.Command(0f, 1f));
            });
            Assert.True(Vec3.Distance(before, match.Players[0].Movement.Position) < 0.2f,
                        "a player moved during freeze time");

            Run(match, 400);
            Assert.Equal(MatchPhase.Live, match.Phase);
        }

        [Fact]
        public void NobodyRespawnsInsideARound()
        {
            MatchSimulation match = NewMatch(out OverloadMode mode);
            match.Start();
            Run(match, 400);   // out of freeze

            PlayerRuntime victim = match.Players[0];
            victim.Die();
            Assert.False(victim.IsAlive);

            Run(match, FixedClock.TicksPerSecond * 10);
            Assert.False(victim.IsAlive, "a player came back during a round");
        }

        [Fact]
        public void EliminatingASideEndsTheRoundAndEveryoneComesBackForTheNext()
        {
            MatchSimulation match = NewMatch(out OverloadMode mode);
            match.Start();
            Run(match, 400);
            Assert.Equal(1, match.RoundNumber);

            foreach (PlayerRuntime player in match.Players)
                if (player.Team == Team.Bravo) player.Die();

            // Round end, then the between-rounds pause, then everyone is back.
            Run(match, FixedClock.TicksPerSecond * 12);

            Assert.True(match.RoundNumber >= 2, "the round never ended");
            Assert.Equal(1, mode.TeamScore(Team.Alpha));
            foreach (PlayerRuntime player in match.Players)
                Assert.True(player.IsAlive, $"{player.Name} did not come back for round 2");
        }

        [Fact]
        public void AnArmedChargeOutlivesTheTeamThatArmedIt()
        {
            // The rule that makes committing to an arm worth it: wiping the attackers after the
            // charge is armed does not win the round, because the fuse is still running.
            MatchSimulation match = NewMatch(out OverloadMode mode);
            match.Start();
            Run(match, 400);

            ArmTheCharge(match, mode);
            Assert.True(mode.IsArmed);

            int roundBefore = match.RoundNumber;
            foreach (PlayerRuntime player in match.Players)
                if (player.Team == mode.Attackers) player.Die();

            Run(match, FixedClock.TicksPerSecond * 2);
            Assert.Equal(roundBefore, match.RoundNumber);
            Assert.True(mode.IsArmed, "the charge vanished with its planter");
        }

        [Fact]
        public void AnArmedChargeDetonatesAndWinsTheRoundForTheAttackers()
        {
            MatchSimulation match = NewMatch(out OverloadMode mode);
            match.Start();
            Run(match, 400);

            Team attackers = mode.Attackers;
            ArmTheCharge(match, mode);

            // Let the fuse burn out with nobody disarming.
            Run(match, (int)((OverloadMode.FuseSeconds + 6f) * FixedClock.TicksPerSecond));

            Assert.Equal(1, mode.TeamScore(attackers));
            Assert.Equal(0, mode.TeamScore(attackers.Opponent()));
        }

        [Fact]
        public void DefendersCanDisarmAndWinTheRound()
        {
            MatchSimulation match = NewMatch(out OverloadMode mode);
            match.Start();
            Run(match, 400);

            Team attackers = mode.Attackers;
            ArmTheCharge(match, mode);
            int site = mode.ArmedSite;

            PlayerRuntime defender = FirstOf(match, attackers.Opponent());
            StandInZone(match, defender, site);

            Run(match, (int)((OverloadMode.DisarmSeconds + 1f) * FixedClock.TicksPerSecond),
                (m, _) => m.SubmitInput(defender.Id, UseCommand()));

            Assert.Equal(1, mode.TeamScore(attackers.Opponent()));
            Assert.Equal(0, mode.TeamScore(attackers));
        }

        [Fact]
        public void ArmingRequiresContinuousContactAndProgressIsLostOnRelease()
        {
            MatchSimulation match = NewMatch(out OverloadMode mode);
            match.Start();
            Run(match, 400);

            PlayerRuntime attacker = FirstOf(match, mode.Attackers);
            StandInZone(match, attacker, 0);

            // Hold for most of the arm time, then let go.
            Run(match, (int)(OverloadMode.ArmSeconds * 0.8f * FixedClock.TicksPerSecond),
                (m, _) => m.SubmitInput(attacker.Id, UseCommand()));
            Assert.False(mode.IsArmed);
            Assert.True(mode.ArmProgress > 0f);

            Run(match, 4, (m, _) => m.SubmitInput(attacker.Id, TestWorlds.Command(0f, 0f)));
            Assert.Equal(0f, mode.ArmProgress);

            // Holding again from zero must take the full time, not resume.
            Run(match, (int)(OverloadMode.ArmSeconds * 0.8f * FixedClock.TicksPerSecond),
                (m, _) => m.SubmitInput(attacker.Id, UseCommand()));
            Assert.False(mode.IsArmed, "arming resumed from where it was interrupted");
        }

        [Fact]
        public void DefendersCannotArmAndAttackersCannotDisarm()
        {
            MatchSimulation match = NewMatch(out OverloadMode mode);
            match.Start();
            Run(match, 400);

            PlayerRuntime defender = FirstOf(match, mode.Defenders);
            StandInZone(match, defender, 0);
            Run(match, (int)((OverloadMode.ArmSeconds + 2f) * FixedClock.TicksPerSecond),
                (m, _) => m.SubmitInput(defender.Id, UseCommand()));
            Assert.False(mode.IsArmed, "a defender armed the charge");

            ArmTheCharge(match, mode);
            PlayerRuntime attacker = FirstOf(match, mode.Attackers);
            StandInZone(match, attacker, mode.ArmedSite);
            Run(match, (int)((OverloadMode.DisarmSeconds + 1f) * FixedClock.TicksPerSecond),
                (m, _) => m.SubmitInput(attacker.Id, UseCommand()));
            Assert.True(mode.IsArmed, "an attacker disarmed their own charge");
        }

        [Fact]
        public void SidesSwapAtHalfTime()
        {
            GameModeDefinition definition = Content().GameModes.Get(StarterContent.Modes.Overload);
            var mode = new OverloadMode(definition, firstHalfAttackers: Team.Alpha);
            MapDefinition map = Content().Maps.Get(StarterContent.MapCrossfire);
            var match = new MatchSimulation(Content(), map, mode, 1);
            var loadout = Loadout.Default(StarterContent.Weapons.Kestrel,
                                          StarterContent.Weapons.Pike,
                                          StarterContent.Weapons.Cleaver);
            for (int i = 0; i < 4; i++)
                match.AddPlayer($"P{i}", i % 2 == 0 ? Team.Alpha : Team.Bravo, loadout);

            match.Start();
            Assert.Equal(Team.Alpha, mode.Attackers);

            mode.OnRoundStart(match, definition.RoundsToWin);
            Assert.Equal(Team.Alpha, mode.Attackers);

            mode.OnRoundStart(match, definition.RoundsToWin + 1);
            Assert.Equal(Team.Bravo, mode.Attackers);
        }

        [Fact]
        public void AMatchEndsWhenASideTakesEnoughRounds()
        {
            MatchSimulation match = NewMatch(out OverloadMode mode);
            match.Start();

            int roundsToWin = mode.Definition.RoundsToWin;
            int guard = 0;
            while (match.Phase != MatchPhase.MatchEnd && guard++ < 200)
            {
                Run(match, 400);   // through freeze into live
                // Wipe whichever side is defending, so the attackers take every round.
                foreach (PlayerRuntime player in match.Players)
                    if (player.Team == mode.Defenders && player.IsAlive) player.Die();
                Run(match, FixedClock.TicksPerSecond * 6);
            }

            Assert.Equal(MatchPhase.MatchEnd, match.Phase);
            Assert.True(match.Outcome.IsDecided);
            Assert.True(mode.TeamScore(Team.Alpha) >= roundsToWin
                        || mode.TeamScore(Team.Bravo) >= roundsToWin,
                        $"match ended at {mode.TeamScore(Team.Alpha)}-{mode.TeamScore(Team.Bravo)}, "
                        + $"neither side reached {roundsToWin}");
        }

        [Fact]
        public void ARoundTheAttackersIgnoreGoesToTheDefenders()
        {
            MatchSimulation match = NewMatch(out OverloadMode mode);
            match.Start();

            Team defenders = mode.Defenders;
            // Nobody does anything for longer than a round.
            Run(match, (int)((mode.Definition.RoundSeconds + 12f) * FixedClock.TicksPerSecond));

            Assert.True(mode.TeamScore(defenders) >= 1,
                        "the round clock expired without the defenders being awarded it");
        }

        // ---- helpers ---------------------------------------------------------------------

        private static PlayerInput UseCommand() =>
            TestWorlds.Command(0f, 0f, 0f, InputButtons.Use);

        private static PlayerRuntime FirstOf(MatchSimulation match, Team team)
        {
            foreach (PlayerRuntime player in match.Players)
                if (player.Team == team && player.IsAlive) return player;
            throw new System.InvalidOperationException($"no living player on {team}");
        }

        /// <summary>Teleports a player onto a site. Test-only: the simulation has no such move.</summary>
        private static void StandInZone(MatchSimulation match, PlayerRuntime player, int site)
        {
            ObjectiveZone zone = match.Map.Objectives[site];
            MovementState movement = player.Movement;
            movement.Position = new Vec3(zone.Centre.X, zone.Volume.Min.Y, zone.Centre.Z);
            movement.Velocity = Vec3.Zero;
            movement.IsGrounded = true;
            player.Movement = movement;
        }

        private static void ArmTheCharge(MatchSimulation match, OverloadMode mode)
        {
            PlayerRuntime attacker = FirstOf(match, mode.Attackers);
            StandInZone(match, attacker, 0);
            Run(match, (int)((OverloadMode.ArmSeconds + 1f) * FixedClock.TicksPerSecond),
                (m, _) =>
                {
                    StandInZone(m, attacker, 0);   // hold them there against gravity settling
                    m.SubmitInput(attacker.Id, UseCommand());
                });
        }
    }
}
