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

            // The networked run needs the same content and the same match, but a different
            // loop around them, so it lives in its own file rather than as a branch through
            // this one.
            if (options.Networked) return NetworkedRun.Run(options);
            if (options.Matchmaking) return MatchmakingRun.Run(options);

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

            IGameMode mode = GameModes.Create(modeDefinition);

            var match = new MatchSimulation(content, map, mode, options.Seed);
            var director = new BotDirector(content, options.Seed);

            AddBots(match, modeDefinition, options);
            match.Start();
            // Drained straight away: Start() emits the initial spawns and the next Step() will
            // clear them.
            var stats = new RunStatistics(options.MaxSeconds);
            stats.Observe(match, options.Verbose);

            // Career progress for every player, folded in as the match runs. Exercised here
            // rather than only in tests so a regression in reward accounting shows up in a run.
            var progress = new Dictionary<int, PlayerProgress>();
            UnlockTable unlocks = StarterContent.BuildUnlocks();
            List<string> unlockProblems = unlocks.Validate(content);
            if (unlockProblems.Count > 0)
            {
                foreach (string problem in unlockProblems)
                    Console.Error.WriteLine($"unlocks: {problem}");
                return 2;
            }
            foreach (PlayerRuntime player in match.Players)
                progress[player.Id.Raw] = new PlayerProgress { AccountId = player.Name };

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
                stats.ObserveObjective(match);
                foreach (PlayerRuntime player in match.Players)
                    RewardRules.RecordEvents(progress[player.Id.Raw], player.Id, match.Events, content);
            }
            stopwatch.Stop();

            Report(match, stats, stopwatch.Elapsed, maxTicks);
            ReportProgression(match, progress, unlocks);
            return stats.Verdict(match) ? 0 : 1;
        }

        private static void AddBots(MatchSimulation match, GameModeDefinition mode, Options options)
        {
            int count = Math.Min(options.BotCount, mode.MaxPlayers);
            for (int i = 0; i < count; i++)
            {
                Team team = mode.IsTeamBased ? (i % 2 == 0 ? Team.Alpha : Team.Bravo) : Team.None;
                // Drawn from the map's own world, not hardcoded. Handing out the modern carbine
                // on a 1940s map works perfectly — the simulation has no opinion about
                // anachronism — which is exactly why it has to be got right deliberately.
                if (!Loadouts.TryBuildDefault(match.Content, match.Map.WorldId, i, out Loadout loadout))
                {
                    Console.Error.WriteLine(
                        $"world '{match.Map.WorldId}' ships no usable weapons for map {match.Map.Id}");
                    continue;
                }
                match.AddPlayer($"Bot{i:D2}", team, loadout, isBot: true,
                                botDifficulty: options.Difficulty);
            }
        }

        /// <summary>
        /// What each player earned, and what it unlocked.
        /// </summary>
        /// <remarks>
        /// Printed because the shape of the reward curve is a design decision that is easy to
        /// get wrong quietly. Seeing participation and objective experience next to kill
        /// experience, match after match, is how anyone notices that the curve has drifted back
        /// towards rewarding whoever was already winning.
        /// </remarks>
        private static void ReportProgression(MatchSimulation match,
                                              Dictionary<int, PlayerProgress> progress,
                                              UnlockTable unlocks)
        {
            Console.WriteLine("--- progression --------------------------------------------");
            Console.WriteLine($"{"player",-10} {"kill",6} {"assist",7} {"objective",10} "
                              + $"{"played",7} {"win",5} {"total",7} {"level",6} {"unlocked",9}");

            foreach (PlayerRuntime player in match.Players)
            {
                MatchRewards rewards = RewardRules.Compute(match, player);
                PlayerProgress career = progress[player.Id.Raw];
                career.Apply(rewards);
                int granted = career.GrantUnlocksFor(unlocks).Count;

                Console.WriteLine($"{player.Name,-10} {rewards.KillXp,6} {rewards.AssistXp,7} "
                                  + $"{rewards.ObjectiveXp,10} {rewards.ParticipationXp,7} "
                                  + $"{rewards.WinBonusXp,5} {rewards.TotalXp,7} "
                                  + $"{career.Level,6} {granted,9}");
            }
            Console.WriteLine();
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
                    ? $"stopped after the requested {match.ElapsedSeconds:F0}s, before the "
                      + "match reached its own ending"
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
            // Worth watching: bots aim at the chest, so a high headshot share would mean the
            // aim error is not being applied, or the hitboxes are not where they should be.
            Console.WriteLine($"headshots        {stats.HeadshotHits} "
                              + $"({(stats.Hits == 0 ? 0 : (double)stats.HeadshotHits / stats.Hits):P1} of hits)");
            Console.WriteLine($"deaths           {stats.Deaths}");
            Console.WriteLine($"footsteps        {stats.Footsteps}");
            Console.WriteLine($"distance moved   {stats.DistanceMoved:F0} m total");

            if (stats.RoundOutcomes.Count > 0)
            {
                Console.WriteLine();
                Console.WriteLine("--- rounds -------------------------------------------------");
                foreach (KeyValuePair<string, int> entry in stats.RoundOutcomes)
                    Console.WriteLine($"{entry.Key,-28} {entry.Value}");
                foreach (KeyValuePair<string, int> entry in stats.ObjectiveEvents)
                    Console.WriteLine($"{entry.Key,-28} {entry.Value}");
                Console.WriteLine($"{"attacker on site (s)",-28} "
                                  + $"{stats.TicksWithAttackerOnSite / (float)FixedClock.TicksPerSecond:F1}");
                Console.WriteLine($"{"attacker arming (s)",-28} "
                                  + $"{stats.TicksArming / (float)FixedClock.TicksPerSecond:F1}");
            }
            Console.WriteLine();

            foreach (string line in stats.Problems(match)) Console.WriteLine($"PROBLEM: {line}");
        }
    }
}
