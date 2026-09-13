using System;
using System.Collections.Generic;
using Salvo.Sim;

namespace Salvo.Headless
{
    /// <summary>
    /// Plays a full match of bots against bots and prints the scoreboard.
    /// </summary>
    /// <remarks>
    /// This is the answer to "is it playable?" in an environment with no Unity and no screen.
    /// It runs the real <see cref="MatchSimulation"/> with the real content, the real movement
    /// model and the real bots — the same code a dedicated server would run — and reports what
    /// happened. If bots move, find each other, shoot, die, respawn and reach a score limit,
    /// the game works; what Unity adds on top is how it looks.
    ///
    /// <para>It is also the honest limit of what can be claimed from here. It exercises the
    /// simulation, not the renderer, the input system, the netcode transport or the UI, none of
    /// which exist yet. See ARCHITECTURE.md §6.</para>
    /// </remarks>
    public static class Program
    {
        public static int Main(string[] args)
        {
            var options = Options.Parse(args);
            if (options.ShowHelp)
            {
                Console.WriteLine(Options.Usage);
                return 0;
            }

            GameContent content = StarterContent.Build();

            List<string> problems = content.Validate();
            if (problems.Count > 0)
            {
                // Content that does not validate is not worth simulating: every failure below
                // would be blamed on the simulation instead.
                Console.Error.WriteLine($"Content failed validation ({problems.Count} problems):");
                foreach (string problem in problems) Console.Error.WriteLine($"  - {problem}");
                return 2;
            }

            if (!content.GameModes.TryGet(options.ModeId, out GameModeDefinition modeDefinition))
            {
                Console.Error.WriteLine($"No such game mode: {options.ModeId}");
                return 2;
            }
            if (!content.Maps.TryGet(options.MapId, out MapDefinition map))
            {
                Console.Error.WriteLine($"No such map: {options.MapId}");
                return 2;
            }

            IGameMode mode = modeDefinition.Kind == GameModeKind.FreeForAll
                ? (IGameMode)new FreeForAllMode(modeDefinition)
                : new TeamDeathmatchMode(modeDefinition);

            var match = new MatchSimulation(content, map, mode, options.Seed);
            var director = new BotDirector(content, options.Seed);

            AddBots(match, modeDefinition, options);
            match.Start();
            // Drained straight away: Start() emits the initial spawns and the next Step() will
            // clear them.
            var stats = new RunStatistics();
            stats.Observe(match, options.Verbose);

            Console.WriteLine($"Salvo headless — {modeDefinition.Id} on {map.Id}");
            Console.WriteLine($"  seed {options.Seed}, {match.Players.Count} bots, "
                              + $"{options.Difficulty}, tick rate {FixedClock.TicksPerSecond} Hz");
            Console.WriteLine();

            int maxTicks = (int)(options.MaxSeconds * FixedClock.TicksPerSecond);
            var stopwatch = System.Diagnostics.Stopwatch.StartNew();

            while (match.Phase != MatchPhase.MatchEnd && match.Tick < maxTicks)
            {
                director.Think(match, FixedClock.TickInterval);
                match.Step();
                stats.Observe(match, options.Verbose);
            }
            stopwatch.Stop();

            Report(match, stats, stopwatch.Elapsed, maxTicks);
            return stats.Verdict(match) ? 0 : 1;
        }

        private static void AddBots(MatchSimulation match, GameModeDefinition mode, Options options)
        {
            int count = Math.Min(options.BotCount, mode.MaxPlayers);
            // Weapon choice alternates so a run exercises more than one weapon's state machine.
            ContentId[] primaries =
            {
                StarterContent.Weapons.Kestrel,
                StarterContent.Weapons.Hornet,
                StarterContent.Weapons.Anvil,
            };

            for (int i = 0; i < count; i++)
            {
                Team team = mode.IsTeamBased ? (i % 2 == 0 ? Team.Alpha : Team.Bravo) : Team.None;
                var loadout = Loadout.Default(primaries[i % primaries.Length],
                                              StarterContent.Weapons.Pike,
                                              StarterContent.Weapons.Cleaver);
                match.AddPlayer($"Bot{i:D2}", team, loadout, isBot: true,
                                botDifficulty: options.Difficulty);
            }
        }

        private static void Report(MatchSimulation match, RunStatistics stats, TimeSpan elapsed,
                                   int maxTicks)
        {
            Console.WriteLine("--- scoreboard ---------------------------------------------");
            Console.WriteLine($"{"player",-10} {"team",-6} {"K",3} {"D",3} {"A",3} {"HS",3} "
                              + $"{"dmg",8} {"best",4}");

            var ordered = new List<PlayerRuntime>(match.Players);
            ordered.Sort((a, b) => b.Score.TotalScore.CompareTo(a.Score.TotalScore));
            foreach (PlayerRuntime player in ordered)
            {
                Console.WriteLine($"{player.Name,-10} {player.Team,-6} {player.Score.Kills,3} "
                                  + $"{player.Score.Deaths,3} {player.Score.Assists,3} "
                                  + $"{player.Score.Headshots,3} {player.Score.DamageDealt,8:F0} "
                                  + $"{player.Score.BestStreak,4}");
            }

            Console.WriteLine();
            if (match.Mode.Definition.IsTeamBased)
            {
                Console.WriteLine($"team score: Alpha {match.Mode.TeamScore(Team.Alpha)} "
                                  + $"- {match.Mode.TeamScore(Team.Bravo)} Bravo");
            }

            string ending = match.Outcome.IsDecided
                ? match.Outcome.WinningPlayer.IsValid
                    ? $"{match.Find(match.Outcome.WinningPlayer)?.Name} wins ({match.Outcome.ReasonKey})"
                    : match.Outcome.WinningTeam == Team.None
                        ? $"draw ({match.Outcome.ReasonKey})"
                        : $"{match.Outcome.WinningTeam} wins ({match.Outcome.ReasonKey})"
                : match.Tick >= maxTicks
                    ? "stopped at the tick limit — the match did not reach its own ending"
                    : "undecided";

            Console.WriteLine($"result: {ending}");
            Console.WriteLine();
            Console.WriteLine("--- simulation ---------------------------------------------");
            Console.WriteLine($"ticks            {match.Tick} ({match.ElapsedSeconds:F1} s of match time)");
            Console.WriteLine($"wall clock       {elapsed.TotalSeconds:F2} s "
                              + $"({match.Tick / Math.Max(0.001, elapsed.TotalSeconds):F0} ticks/s, "
                              + $"{match.Tick / Math.Max(0.001, elapsed.TotalSeconds) / FixedClock.TicksPerSecond:F0}x real time)");
            Console.WriteLine($"spawns           {stats.Spawns}");
            Console.WriteLine($"shots fired      {stats.ShotsFired}");
            Console.WriteLine($"hits landed      {stats.Hits} ({stats.HitRate:P1} of shots)");
            Console.WriteLine($"deaths           {stats.Deaths}");
            Console.WriteLine($"footsteps        {stats.Footsteps}");
            Console.WriteLine($"distance moved   {stats.DistanceMoved:F0} m total");
            Console.WriteLine();

            foreach (string line in stats.Problems(match)) Console.WriteLine($"PROBLEM: {line}");
        }
    }
}
