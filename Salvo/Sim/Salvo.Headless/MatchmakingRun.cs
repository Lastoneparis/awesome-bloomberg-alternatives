using System;
using System.Collections.Generic;
using Salvo.Sim;

namespace Salvo.Headless
{
    /// <summary>
    /// Runs a queue of parties through the matchmaker and plays what comes out.
    /// </summary>
    /// <remarks>
    /// The end-to-end path nothing else covers: parties queue, a match is formed, and that
    /// proposal becomes a running match. Tests check each rule in isolation; this checks that
    /// the output of one stage is usable as the input of the next, which is where systems
    /// built separately usually come apart.
    ///
    /// <para>It also exercises the rules under volume rather than in the two- or three-party
    /// arrangements a unit test uses. A queue of sixty with blocks scattered through it will
    /// find an ordering bug that four hand-written tickets never would.</para>
    /// </remarks>
    public static class MatchmakingRun
    {
        public static int Run(Options options)
        {
            GameContent content = StarterContent.Build();
            List<string> problems = content.Validate();
            if (problems.Count > 0)
            {
                foreach (string problem in problems) Console.Error.WriteLine($"content: {problem}");
                return 2;
            }

            var graph = new SocialGraph();
            var matchmaker = new Matchmaker(content, graph);
            var random = new DeterministicRandom(options.Seed);

            // A population with parties of varying size, a spread of skill, and some blocks.
            const int population = 60;
            var accounts = new List<string>();
            for (int i = 0; i < population; i++) accounts.Add($"acct.p{i:D3}");

            int blocksCreated = 0;
            for (int i = 0; i < population / 6; i++)
            {
                string a = accounts[random.NextInt(accounts.Count)];
                string b = accounts[random.NextInt(accounts.Count)];
                if (a == b) continue;
                if (graph.Block(a, b) == SocialResult.Ok) blocksCreated++;
            }

            int queued = 0, partiesQueued = 0;
            for (int i = 0; i < population;)
            {
                int size = 1 + random.NextInt(Party.AbsoluteMaxSize);
                if (i + size > population) size = population - i;

                var ticket = new MatchmakingTicket
                {
                    ModeId = options.ModeId,
                    SkillRating = random.NextInt(SkillRatings.Default - 400,
                                                 SkillRatings.Default + 900),
                };
                for (int m = 0; m < size; m++) ticket.Accounts.Add(accounts[i + m]);
                matchmaker.Enqueue(ticket);
                partiesQueued++;
                queued += size;
                i += size;
            }

            Console.WriteLine($"Salvo matchmaking — {options.ModeId}");
            Console.WriteLine($"  {queued} players in {partiesQueued} parties, "
                              + $"{blocksCreated} blocks, seed {options.Seed}");
            Console.WriteLine();
            Console.WriteLine("--- matches formed -----------------------------------------");
            Console.WriteLine($"{"#",3} {"alpha",6} {"bravo",6} {"bots",5} {"skill gap",10} "
                              + $"{"avoided",8} {"map",-16} {"result",-28}");

            var formed = new List<MatchProposal>();
            int avoidanceTotal = 0;
            int pass = 0;

            while (pass++ < 40)
            {
                MatchmakingResult result = matchmaker.TryForm(options.ModeId, options.Seed + (uint)pass);
                avoidanceTotal += result.ExcludedByAvoidance;

                if (!result.Success)
                {
                    // Ageing the queue widens the skill window, which is the only rule allowed
                    // to bend. If it still cannot form after that, it genuinely cannot.
                    matchmaker.Tick(30f);
                    if (matchmaker.QueuedPlayers == 0) break;
                    MatchmakingResult retry = matchmaker.TryForm(options.ModeId,
                                                                 options.Seed + (uint)pass);
                    avoidanceTotal += retry.ExcludedByAvoidance;
                    if (!retry.Success)
                    {
                        Console.WriteLine($"{pass,3} {"-",6} {"-",6} {"-",5} {"-",10} "
                                          + $"{result.ExcludedByAvoidance,8} {"-",-16} "
                                          + $"{retry.ReasonKey,-28}");
                        break;
                    }
                    result = retry;
                }

                MatchProposal proposal = result.Proposal;
                formed.Add(proposal);
                Console.WriteLine($"{pass,3} {proposal.AlphaPlayers,6} {proposal.BravoPlayers,6} "
                                  + $"{proposal.BotsToAdd,5} {proposal.SkillGap,10} "
                                  + $"{result.ExcludedByAvoidance,8} {proposal.Map.Id,-16} "
                                  + $"{result.ReasonKey,-28}");
            }

            Console.WriteLine();
            return Verify(content, graph, formed, matchmaker, queued, avoidanceTotal, options);
        }

        private static int Verify(GameContent content, SocialGraph graph,
                                  List<MatchProposal> formed, Matchmaker matchmaker,
                                  int queued, int avoidanceTotal, Options options)
        {
            var failures = new List<string>();
            var everMatched = new HashSet<string>();
            int totalSeats = 0;

            foreach (MatchProposal proposal in formed)
            {
                var accounts = new List<string>(proposal.AllAccounts());
                totalSeats += accounts.Count;

                // The rule that never bends, checked against every pair in every match formed.
                for (int i = 0; i < accounts.Count; i++)
                {
                    everMatched.Add(accounts[i]);
                    for (int j = i + 1; j < accounts.Count; j++)
                        if (!graph.MayInteract(accounts[i], accounts[j]))
                            failures.Add($"{accounts[i]} and {accounts[j]} were matched together "
                                         + "despite a block");
                }

                if (proposal.Mode.IsTeamBased)
                {
                    // Human-only balance is deliberately not asserted. Parties cannot be split,
                    // so a lobby containing one five-stack and nothing else has no even human
                    // split available — demanding one would mean either splitting the party or
                    // refusing the match, and both are worse than five humans against five bots.
                    // What must hold is that the sides are even once bots are counted.
                    int alphaSeats = proposal.AlphaPlayers + proposal.BotsForAlpha;
                    int bravoSeats = proposal.BravoPlayers + proposal.BotsForBravo;
                    if (alphaSeats != bravoSeats)
                        failures.Add($"after bots, sides are {alphaSeats} against {bravoSeats}");
                    if (proposal.AlphaPlayers > proposal.Mode.TeamSize
                        || proposal.BravoPlayers > proposal.Mode.TeamSize)
                        failures.Add("a team exceeded the mode's team size");
                }

                // Every party landed whole on one side.
                foreach (List<MatchmakingTicket> side in
                         new[] { proposal.Alpha, proposal.Bravo })
                    foreach (MatchmakingTicket ticket in side)
                        if (ticket.Accounts.Count == 0)
                            failures.Add("an empty ticket reached a proposal");
            }

            // Nobody is in two matches at once.
            if (everMatched.Count != totalSeats)
                failures.Add($"{totalSeats} seats filled by only {everMatched.Count} accounts — "
                             + "somebody was placed in more than one match");

            Console.WriteLine("--- summary ------------------------------------------------");
            Console.WriteLine($"matches formed   {formed.Count}");
            Console.WriteLine($"players placed   {everMatched.Count} of {queued}");
            Console.WriteLine($"still queued     {matchmaker.QueuedPlayers}");
            Console.WriteLine($"avoidance skips  {avoidanceTotal}");

            // Reported rather than failed: a lopsided human split is a match-quality signal, and
            // with unsplittable parties it is not always avoidable.
            int lopsided = 0;
            foreach (MatchProposal proposal in formed)
                if (proposal.Mode.IsTeamBased
                    && System.Math.Abs(proposal.AlphaPlayers - proposal.BravoPlayers) > 1)
                    lopsided++;
            Console.WriteLine($"lopsided humans  {lopsided} of {formed.Count} "
                              + "(bots even the sides; parties cannot be split)");
            Console.WriteLine();

            if (formed.Count == 0)
                failures.Add("a queue of 60 produced no matches at all");

            // Nobody may leave the queue without being placed. This is the check that caught the
            // matchmaker dropping tickets it had selected but could not fit on a side.
            int unaccounted = queued - everMatched.Count - matchmaker.QueuedPlayers;
            if (unaccounted != 0)
                failures.Add($"{unaccounted} players left the queue without being placed in a "
                             + "match — matchmaking is losing people");

            foreach (string failure in failures) Console.WriteLine($"PROBLEM: {failure}");
            if (failures.Count == 0) Console.WriteLine("no problems found.");
            return failures.Count == 0 ? 0 : 1;
        }
    }
}
