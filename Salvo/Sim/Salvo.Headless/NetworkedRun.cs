using System;
using System.Collections.Generic;
using Salvo.Sim;

namespace Salvo.Headless
{
    /// <summary>
    /// Plays a real networked match — authoritative server, predicting clients, a lossy link —
    /// entirely in one process, and reports whether it held together.
    /// </summary>
    /// <remarks>
    /// Netcode that has only ever run on localhost has not been tested. This runs the genuine
    /// <see cref="NetServer"/> and <see cref="NetClient"/> against a
    /// <see cref="SimulatedLink"/> with latency, jitter, loss and reordering, so the conditions
    /// that break naive implementations are the default rather than an afterthought.
    ///
    /// <para>Each client's commands come from a <see cref="BotBrain"/>. The brain stands in for
    /// a human's hands and nothing more: it produces a <see cref="PlayerInput"/>, which is the
    /// only thing a real client may send. It reads the server's match to decide where to aim,
    /// which a real client could not — but since its output is only ever a command, that
    /// shortcut cannot flatter the netcode. It just means the players move like players instead
    /// of standing still.</para>
    /// </remarks>
    public static class NetworkedRun
    {
        private sealed class ClientHarness
        {
            public PlayerId Id;
            public NetClient Client;
            public BotBrain Hands;
        }

        public static int Run(Options options)
        {
            GameContent content = StarterContent.Build();
            List<string> problems = content.Validate();
            if (problems.Count > 0)
            {
                foreach (string problem in problems) Console.Error.WriteLine($"content: {problem}");
                return 2;
            }

            GameModeDefinition modeDefinition = content.GameModes.Get(options.ModeId);
            MapDefinition map = content.Maps.Get(options.MapId);
            IGameMode mode = GameModes.Create(modeDefinition);

            var match = new MatchSimulation(content, map, mode, options.Seed);
            var server = new NetServer(match);
            BotDifficultyDefinition difficulty = content.BotDifficulties.Get(options.Difficulty);

            int count = Math.Min(options.BotCount, modeDefinition.MaxPlayers);
            var harnesses = new List<ClientHarness>();
            var links = new List<(SimulatedLink up, SimulatedLink down)>();

            for (int i = 0; i < count; i++)
            {
                Team team = modeDefinition.IsTeamBased ? (i % 2 == 0 ? Team.Alpha : Team.Bravo)
                                                       : Team.None;
                if (!Loadouts.TryBuildDefault(content, map.WorldId, i, out Loadout loadout))
                {
                    Console.Error.WriteLine($"world '{map.WorldId}' ships no usable weapons");
                    return 2;
                }
                PlayerRuntime player = match.AddPlayer($"Net{i:D2}", team, loadout);
                // Every client gets its own link with its own seed, so they do not all lose the
                // same packets on the same ticks — which would be a far kinder network than any
                // real one.
                SimulatedLink up = MakeLink(options.NetworkProfile, options.Seed + (uint)i * 31u);
                SimulatedLink down = MakeLink(options.NetworkProfile, options.Seed + (uint)i * 71u);
                links.Add((up, down));
                server.AddClient(player.Id, toClient: down, fromClient: up);

                harnesses.Add(new ClientHarness
                {
                    Id = player.Id,
                    Hands = new BotBrain(difficulty, options.Seed ^ (uint)(player.Id.Raw * 977u)),
                });
            }

            match.Start();

            // Clients are created after Start so they begin from the spawn the server chose,
            // exactly as a real client does once it has received its first snapshot.
            var world = new CollisionWorld(map);
            for (int i = 0; i < harnesses.Count; i++)
            {
                PlayerRuntime player = match.Find(harnesses[i].Id);
                harnesses[i].Client = new NetClient(player.Id, world, match.Tuning,
                                                    player.Movement, links[i].up, links[i].down);
            }

            Console.WriteLine($"Salvo networked — {modeDefinition.Id} on {map.Id}");
            Console.WriteLine($"  {count} clients, {options.NetworkProfile} link, "
                              + $"seed {options.Seed}, {FixedClock.TicksPerSecond} Hz sim / "
                              + $"{NetServer.SnapshotHz} Hz snapshots");
            Console.WriteLine();

            int maxTicks = (int)(options.MaxSeconds * FixedClock.TicksPerSecond);
            var stopwatch = System.Diagnostics.Stopwatch.StartNew();

            while (match.Phase != MatchPhase.MatchEnd && match.Tick < maxTicks)
            {
                for (int i = 0; i < harnesses.Count; i++)
                {
                    ClientHarness harness = harnesses[i];
                    PlayerRuntime player = match.Find(harness.Id);

                    PlayerInput input = harness.Hands.Think(match, player, FixedClock.TickInterval);
                    input.Tick = match.Tick;

                    // The multiplier is derived from the command being simulated, not from the
                    // player's current state, and the same function serves prediction, replay
                    // and the server. Passing the current multiplier for a replayed command was
                    // the single largest source of divergence in this harness: aiming halves
                    // movement speed, and bots aim and stop aiming constantly.
                    harness.Client.Step(input,
                                        player.SpeedMultiplierForInput(input),
                                        player.SpeedMultiplierForInput);

                    // Deliberately no error sampling here. Comparing the client's current
                    // position against the server's current position measures latency, not
                    // prediction: the client is always about one one-way trip ahead, and on a
                    // 90 ms link at running speed that is half a metre of entirely correct
                    // disagreement. ClientPrediction measures the comparison that matters —
                    // predicted versus authoritative for the same input tick.
                }
                server.Step();
            }
            stopwatch.Stop();

            return Report(match, server, harnesses, links, stopwatch.Elapsed, options);
        }

        private static SimulatedLink MakeLink(string profile, uint seed) => profile switch
        {
            "perfect" => SimulatedLink.Perfect(),
            "poor" => SimulatedLink.Poor(seed),
            // Single-impairment profiles. Not for shipping; for finding out which impairment is
            // responsible when the full profile misbehaves, instead of guessing.
            "latency" => new SimulatedLink(seed, latencySeconds: 0.06f),
            "jitter" => new SimulatedLink(seed, latencySeconds: 0.06f, jitterSeconds: 0.015f),
            "loss" => new SimulatedLink(seed, latencySeconds: 0.06f, lossChance: 0.01f),
            "reorder" => new SimulatedLink(seed, latencySeconds: 0.06f, reorderChance: 0.02f),
            _ => SimulatedLink.Mobile(seed),
        };

        private static int Report(MatchSimulation match, NetServer server,
                                  List<ClientHarness> harnesses,
                                  List<(SimulatedLink up, SimulatedLink down)> links,
                                  TimeSpan elapsed, Options options)
        {
            Console.WriteLine("--- clients ------------------------------------------------");
            Console.WriteLine("  error = client's prediction vs the server's result for the SAME input tick");
            Console.WriteLine($"{"client",-8} {"mean err",9} {"worst",8} {"recon",6} {"of",6} "
                              + $"{"replayed",9} {"tele",5} {"starv",6} {"undec",6} {"rtt",6}");

            double worstMean = 0, worstPeak = 0;
            int totalReconciliations = 0, totalUndecodable = 0, totalCompared = 0;

            foreach (ClientHarness harness in harnesses)
            {
                ClientPrediction prediction = harness.Client.Prediction;
                worstMean = Math.Max(worstMean, prediction.MeanError);
                worstPeak = Math.Max(worstPeak, prediction.WorstError);
                totalReconciliations += prediction.Reconciliations;
                totalCompared += prediction.ErrorSamples;
                totalUndecodable += harness.Client.UndecodablePackets;

                Console.WriteLine($"{match.Find(harness.Id)?.Name,-8} {prediction.MeanError,8:F4}m "
                                  + $"{prediction.WorstError,7:F3}m {prediction.Reconciliations,6} "
                                  + $"{prediction.ErrorSamples,6} "
                                  + $"{prediction.InputsReplayed,9} "
                                  + $"{harness.Client.Teleports,5} "
                                  + $"{server.StarvationsFor(harness.Id),6} "
                                  + $"{harness.Client.UndecodablePackets,6} "
                                  + $"{server.LatencyOf(harness.Id) * 1000f,5:F0}ms");
            }

            int sent = 0, dropped = 0;
            foreach ((SimulatedLink up, SimulatedLink down) in links)
            {
                sent += up.PacketsSent + down.PacketsSent;
                dropped += up.PacketsDropped + down.PacketsDropped;
            }

            double seconds = Math.Max(0.001, match.ElapsedSeconds);
            double bitsPerSecondPerClient = harnesses.Count == 0 ? 0
                : server.BytesSent * 8.0 / seconds / harnesses.Count;

            Console.WriteLine();
            Console.WriteLine("--- network ------------------------------------------------");
            Console.WriteLine($"profile          {options.NetworkProfile}");
            Console.WriteLine($"packets          {sent} sent, {dropped} dropped "
                              + $"({(sent == 0 ? 0 : (double)dropped / sent):P1})");
            Console.WriteLine($"snapshots        {server.SnapshotsSent} sent, "
                              + $"{server.BytesSent} bytes total");
            Console.WriteLine($"downstream       {bitsPerSecondPerClient / 1000.0:F1} kbit/s per client");
            Console.WriteLine($"undecodable      {totalUndecodable} (baseline no longer held)");
            Console.WriteLine($"reconciliations  {totalReconciliations} of {totalCompared} ticks compared "
                              + $"({(totalCompared == 0 ? 0 : (double)totalReconciliations / totalCompared):P1})");
            Console.WriteLine($"match            {match.Tick} ticks, {match.ElapsedSeconds:F0}s, "
                              + $"wall {elapsed.TotalSeconds:F2}s");
            Console.WriteLine();

            var failures = new List<string>();

            // The thresholds that matter. A mean per-tick disagreement above a few centimetres
            // means the player is being corrected constantly, which reads as the controls
            // fighting back.
            if (worstMean > 0.05)
                failures.Add($"a client's mean prediction error is {worstMean:F4} m — "
                             + "the local player would visibly rubber-band");
            if (worstPeak > 2.0)
                failures.Add($"a client's worst prediction error is {worstPeak:F2} m — "
                             + "that is a teleport, not a correction");
            // The correction rate is judged against the rate at which the server ran out of
            // commands, not against a flat number.
            //
            // A flat threshold is the wrong test, in both directions. On a link losing 11% of
            // commands the server has no choice but to guess on 11% of ticks, and every guess is
            // a correction — demanding a low rate there is demanding something the network makes
            // impossible. Meanwhile a 40% correction rate on a link losing 1% is a screaming
            // bug, and a flat 50% threshold would wave it through. Tying the two together is
            // what makes this catch the second case without failing the first: it is exactly the
            // check that would have caught reconciliation being seeded with the wrong velocity,
            // which turned 1% packet loss into a 40% correction rate.
            int totalStarvations = 0;
            foreach (ClientHarness harness in harnesses)
                totalStarvations += server.StarvationsFor(harness.Id);
            double starvationRate = match.Tick == 0 || harnesses.Count == 0
                ? 0 : (double)totalStarvations / (match.Tick * harnesses.Count);
            double correctionRate = totalCompared == 0
                ? 0 : (double)totalReconciliations / totalCompared;
            // Six corrections per starved tick allows for the correction arriving a snapshot
            // later than the starvation, plus the ordinary background rate; well above what a
            // healthy implementation produces and well below a broken one.
            double allowed = System.Math.Max(0.15, starvationRate * 6.0);

            Console.WriteLine($"input starvation {starvationRate:P1} of ticks "
                              + $"(server had no command and reused the previous one)");
            Console.WriteLine($"correction budget {correctionRate:P1} used of {allowed:P1} allowed");
            Console.WriteLine();

            if (correctionRate > allowed)
                failures.Add($"{correctionRate:P0} of compared ticks needed a correction, against "
                             + $"{starvationRate:P1} input starvation — that is divergence, not loss");

            foreach (ClientHarness harness in harnesses)
            {
                if (harness.Client.SnapshotsReceived == 0)
                    failures.Add($"{match.Find(harness.Id)?.Name} received no snapshots at all");
            }

            // 64 kbit/s downstream at 10v10 is the budget in PROJECT_PLAN.md. Scaled by player
            // count, since the run may have fewer.
            double budget = 64.0 * harnesses.Count / 10.0;
            if (bitsPerSecondPerClient / 1000.0 > budget)
                failures.Add($"downstream is {bitsPerSecondPerClient / 1000.0:F1} kbit/s per client, "
                             + $"over the {budget:F1} kbit/s budget for {harnesses.Count} players");

            foreach (string failure in failures) Console.WriteLine($"PROBLEM: {failure}");
            if (failures.Count == 0) Console.WriteLine("no problems found.");
            return failures.Count == 0 ? 0 : 1;
        }
    }
}
