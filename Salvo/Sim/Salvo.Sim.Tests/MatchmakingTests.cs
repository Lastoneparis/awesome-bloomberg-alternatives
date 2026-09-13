using System.Collections.Generic;
using Xunit;
using Salvo.Sim;

namespace Salvo.Sim.Tests
{
    /// <summary>
    /// Turning a queue of parties into a match. The rules conflict with one another, so most of
    /// these tests are about which one wins.
    /// </summary>
    public class MatchmakingTests
    {
        private static GameContent Content() => StarterContent.Build();
        private static readonly ContentId Tdm = StarterContent.Modes.TeamDeathmatch;
        private static readonly ContentId Ffa = StarterContent.Modes.FreeForAll;
        private static readonly ContentId Overload = StarterContent.Modes.Overload;

        private static MatchmakingTicket Solo(string account, ContentId mode, int skill = 1000)
            => MatchmakingTicket.ForSolo(account, mode, skill);

        private static MatchmakingTicket Stack(ContentId mode, int skill, params string[] accounts)
        {
            var ticket = new MatchmakingTicket { ModeId = mode, SkillRating = skill };
            ticket.Accounts.AddRange(accounts);
            return ticket;
        }

        private static void FillSolos(Matchmaker matchmaker, int count, ContentId mode,
                                      int skill = 1000, string prefix = "p")
        {
            for (int i = 0; i < count; i++)
                matchmaker.Enqueue(Solo($"acct.{prefix}{i}", mode, skill));
        }

        // ---- forming a match ------------------------------------------------------------

        [Fact]
        public void EnoughSolosFormAMatch()
        {
            var matchmaker = new Matchmaker(Content());
            FillSolos(matchmaker, 10, Tdm);

            MatchmakingResult result = matchmaker.TryForm(Tdm);

            Assert.True(result.Success, result.ReasonKey);
            Assert.Equal(10, result.Proposal.HumanPlayers);
            Assert.Equal(5, result.Proposal.AlphaPlayers);
            Assert.Equal(5, result.Proposal.BravoPlayers);
            Assert.NotNull(result.Proposal.Map);
        }

        [Fact]
        public void FormingAMatchTakesThosePlayersOutOfTheQueue()
        {
            var matchmaker = new Matchmaker(Content());
            FillSolos(matchmaker, 14, Tdm);

            Assert.True(matchmaker.TryForm(Tdm).Success);
            Assert.Equal(4, matchmaker.QueuedPlayers);
        }

        [Fact]
        public void AnEmptyQueueSaysSoRatherThanFormingAnEmptyMatch()
        {
            var matchmaker = new Matchmaker(Content());
            MatchmakingResult result = matchmaker.TryForm(Tdm);
            Assert.False(result.Success);
            Assert.Equal(MatchmakingOutcome.NotEnoughPlayers, result.Outcome);
        }

        [Fact]
        public void AnUnknownModeFailsRatherThanThrowing()
        {
            var matchmaker = new Matchmaker(Content());
            MatchmakingResult result = matchmaker.TryForm("mode.does_not_exist");
            Assert.False(result.Success);
        }

        [Fact]
        public void TicketsForOtherModesAreLeftAlone()
        {
            var matchmaker = new Matchmaker(Content());
            FillSolos(matchmaker, 10, Tdm, prefix: "tdm");
            FillSolos(matchmaker, 4, Overload, prefix: "ovl");

            MatchmakingResult result = matchmaker.TryForm(Tdm);
            Assert.True(result.Success);

            foreach (string account in result.Proposal.AllAccounts())
                Assert.StartsWith("acct.tdm", account);
            Assert.Equal(4, matchmaker.QueuedPlayers);
        }

        // ---- parties stay together ---------------------------------------------------------

        [Fact]
        public void APartyIsNeverSplitAcrossTeams()
        {
            // People queue together to play together; a matchmaker that separates them has
            // failed at the one thing they asked for.
            var matchmaker = new Matchmaker(Content());
            MatchmakingTicket trio = Stack(Tdm, 1000, "acct.a", "acct.b", "acct.c");
            matchmaker.Enqueue(trio);
            FillSolos(matchmaker, 7, Tdm);

            MatchmakingResult result = matchmaker.TryForm(Tdm);
            Assert.True(result.Success, result.ReasonKey);

            var alpha = new HashSet<string>(result.Proposal.AccountsOn(Team.Alpha));
            var bravo = new HashSet<string>(result.Proposal.AccountsOn(Team.Bravo));

            bool allInAlpha = alpha.Contains("acct.a") && alpha.Contains("acct.b")
                              && alpha.Contains("acct.c");
            bool allInBravo = bravo.Contains("acct.a") && bravo.Contains("acct.b")
                              && bravo.Contains("acct.c");
            Assert.True(allInAlpha || allInBravo, "the trio was split across teams");
        }

        [Fact]
        public void APartyLargerThanATeamIsNeverPlaced()
        {
            // Six people cannot fit on a team of five, and splitting them is rule two.
            var matchmaker = new Matchmaker(Content());
            matchmaker.Enqueue(Stack(Tdm, 1000, "a", "b", "c", "d", "e", "f"));
            FillSolos(matchmaker, 10, Tdm);

            MatchmakingResult result = matchmaker.TryForm(Tdm);
            Assert.True(result.Success);
            Assert.DoesNotContain("a", result.Proposal.AllAccounts());
        }

        [Fact]
        public void TwoFiveStacksBecomeOneMatch()
        {
            var matchmaker = new Matchmaker(Content());
            matchmaker.Enqueue(Stack(Tdm, 1000, "a1", "a2", "a3", "a4", "a5"));
            matchmaker.Enqueue(Stack(Tdm, 1000, "b1", "b2", "b3", "b4", "b5"));

            MatchmakingResult result = matchmaker.TryForm(Tdm);
            Assert.True(result.Success, result.ReasonKey);
            Assert.Equal(5, result.Proposal.AlphaPlayers);
            Assert.Equal(5, result.Proposal.BravoPlayers);
        }

        // ---- blocking, which never bends -----------------------------------------------------

        [Fact]
        public void BlockedPlayersAreNeverPutInTheSameMatch()
        {
            // Not merely never on the same team. In the same match, A still sees B's name, is
            // shot by B, and can be followed by B.
            var graph = new SocialGraph();
            graph.Block("acct.victim", "acct.harasser");

            var matchmaker = new Matchmaker(Content(), graph);
            matchmaker.Enqueue(Solo("acct.victim", Tdm));
            matchmaker.Enqueue(Solo("acct.harasser", Tdm));
            FillSolos(matchmaker, 9, Tdm);

            MatchmakingResult result = matchmaker.TryForm(Tdm);
            Assert.True(result.Success, result.ReasonKey);

            var accounts = new HashSet<string>(result.Proposal.AllAccounts());
            Assert.False(accounts.Contains("acct.victim") && accounts.Contains("acct.harasser"),
                         "a blocked pair were put in the same match");
        }

        [Fact]
        public void ABlockIsRespectedWhicheverSideDidTheBlocking()
        {
            foreach (bool victimBlocks in new[] { true, false })
            {
                var graph = new SocialGraph();
                if (victimBlocks) graph.Block("acct.one", "acct.two");
                else graph.Block("acct.two", "acct.one");

                var matchmaker = new Matchmaker(Content(), graph);
                matchmaker.Enqueue(Solo("acct.one", Tdm));
                matchmaker.Enqueue(Solo("acct.two", Tdm));
                FillSolos(matchmaker, 9, Tdm);

                var accounts = new HashSet<string>(
                    matchmaker.TryForm(Tdm).Proposal.AllAccounts());
                Assert.False(accounts.Contains("acct.one") && accounts.Contains("acct.two"),
                             $"blocked pair matched together (victimBlocks={victimBlocks})");
            }
        }

        [Fact]
        public void ABlockInsideAPartyBlocksTheWholeParty()
        {
            var graph = new SocialGraph();
            graph.Block("acct.victim", "acct.inparty2");

            var matchmaker = new Matchmaker(Content(), graph);
            matchmaker.Enqueue(Solo("acct.victim", Tdm));
            matchmaker.Enqueue(Stack(Tdm, 1000, "acct.inparty1", "acct.inparty2", "acct.inparty3"));
            FillSolos(matchmaker, 9, Tdm);

            var accounts = new HashSet<string>(matchmaker.TryForm(Tdm).Proposal.AllAccounts());
            Assert.False(accounts.Contains("acct.victim") && accounts.Contains("acct.inparty1"),
                         "a party was matched with someone one of its members had blocked");
        }

        [Fact]
        public void TheBlockRuleIsNeverRelaxedToFillALobby()
        {
            // The tempting engineering move when a queue will not fill. It trades a visible
            // problem — an empty queue, which players understand and metrics record — for an
            // invisible one, where somebody is matched with a person they took deliberate action
            // to avoid and nothing anywhere notes it.
            var graph = new SocialGraph();
            graph.Block("acct.a", "acct.b");

            GameContent content = Content();
            var matchmaker = new Matchmaker(content, graph);
            matchmaker.Enqueue(Solo("acct.a", Overload));
            matchmaker.Enqueue(Solo("acct.b", Overload));

            MatchmakingResult result = matchmaker.TryForm(Overload);
            if (result.Success)
            {
                var accounts = new HashSet<string>(result.Proposal.AllAccounts());
                Assert.False(accounts.Contains("acct.a") && accounts.Contains("acct.b"),
                             "the block rule was relaxed to fill a lobby");
            }
            else
            {
                Assert.True(result.Outcome == MatchmakingOutcome.BlockedByAvoidance
                            || result.Outcome == MatchmakingOutcome.NotEnoughPlayers);
            }
        }

        [Fact]
        public void AvoidanceIsReportedEvenWhenAMatchFormsAnyway()
        {
            // The case that matters most and is easiest to miss: the queue fills fine, so
            // nothing looks wrong, but one player is quietly never matched with anybody. A
            // number that climbs is the only way whoever operates the service finds out.
            var graph = new SocialGraph();
            for (int i = 1; i < 10; i++) graph.Block("acct.p0", $"acct.p{i}");

            var matchmaker = new Matchmaker(Content(), graph);
            FillSolos(matchmaker, 10, Tdm);

            MatchmakingResult result = matchmaker.TryForm(Tdm);
            Assert.True(result.ExcludedByAvoidance > 0,
                        "nine parties were skipped for avoidance and none was reported");

            var accounts = new HashSet<string>(result.Proposal?.AllAccounts()
                                               ?? System.Array.Empty<string>());
            for (int i = 1; i < 10; i++)
                Assert.False(accounts.Contains("acct.p0") && accounts.Contains($"acct.p{i}"),
                             "a blocked pair were matched together");
        }

        [Fact]
        public void AvoidanceIsNotReportedWhenNobodyBlockedAnybody()
        {
            var matchmaker = new Matchmaker(Content(), new SocialGraph());
            FillSolos(matchmaker, 10, Tdm);
            Assert.Equal(0, matchmaker.TryForm(Tdm).ExcludedByAvoidance);
        }

        [Fact]
        public void APartyContainingItsOwnBlockedPairIsNeverMatched()
        {
            // Such a party should not exist — Party.EnforceBlocks sees to that — but the
            // matchmaker receives tickets, not parties, and cannot verify where they came from.
            // Checking only against already-chosen accounts let this through every other rule.
            var graph = new SocialGraph();
            graph.Block("acct.x", "acct.y");

            var matchmaker = new Matchmaker(Content(), graph);
            matchmaker.Enqueue(Stack(Tdm, 1000, "acct.x", "acct.y"));
            FillSolos(matchmaker, 10, Tdm);

            MatchmakingResult result = matchmaker.TryForm(Tdm);
            Assert.True(result.Success, result.ReasonKey);

            var accounts = new HashSet<string>(result.Proposal.AllAccounts());
            Assert.False(accounts.Contains("acct.x") && accounts.Contains("acct.y"),
                         "a party whose own members had blocked each other was matched");
        }

        [Fact]
        public void NobodyLeavesTheQueueWithoutBeingPlaced()
        {
            // The matchmaker used to select a ticket, fail to fit it on either side once the
            // teams filled, and remove it from the queue anyway — so those players were in no
            // match and no queue. From outside it looks like matchmaking losing people.
            var matchmaker = new Matchmaker(Content());
            matchmaker.Enqueue(Stack(Tdm, 1000, "a1", "a2", "a3", "a4", "a5"));
            matchmaker.Enqueue(Stack(Tdm, 1000, "b1", "b2", "b3", "b4", "b5"));
            matchmaker.Enqueue(Stack(Tdm, 1000, "c1", "c2", "c3"));

            int before = matchmaker.QueuedPlayers;
            MatchmakingResult result = matchmaker.TryForm(Tdm);
            Assert.True(result.Success, result.ReasonKey);

            int placed = 0;
            foreach (string _ in result.Proposal.AllAccounts()) placed++;
            Assert.Equal(before, placed + matchmaker.QueuedPlayers);
        }

        [Fact]
        public void AnUnplaceableTicketCanStillBeMatchedLater()
        {
            var matchmaker = new Matchmaker(Content());
            matchmaker.Enqueue(Stack(Tdm, 1000, "a1", "a2", "a3", "a4", "a5"));
            matchmaker.Enqueue(Stack(Tdm, 1000, "b1", "b2", "b3", "b4", "b5"));
            matchmaker.Enqueue(Stack(Tdm, 1000, "c1", "c2", "c3"));

            Assert.True(matchmaker.TryForm(Tdm).Success);
            // The trio is still waiting, and a second pass places it.
            MatchmakingResult second = matchmaker.TryForm(Tdm);
            Assert.True(second.Success, second.ReasonKey);
            Assert.Contains("c1", second.Proposal.AllAccounts());
        }

        // ---- balance --------------------------------------------------------------------------

        [Fact]
        public void TeamsAreEvenInSize()
        {
            var matchmaker = new Matchmaker(Content());
            matchmaker.Enqueue(Stack(Tdm, 1000, "a1", "a2", "a3"));
            matchmaker.Enqueue(Stack(Tdm, 1000, "b1", "b2"));
            FillSolos(matchmaker, 5, Tdm);

            MatchProposal proposal = matchmaker.TryForm(Tdm).Proposal;
            Assert.True(System.Math.Abs(proposal.AlphaPlayers - proposal.BravoPlayers) <= 1,
                        $"teams are {proposal.AlphaPlayers} v {proposal.BravoPlayers}");
        }

        [Fact]
        public void StrongAndWeakPlayersAreSpreadAcrossBothSides()
        {
            // The failure this catches is a matchmaker that fills Alpha then Bravo in queue
            // order, which produces an even split of players and a hopeless split of skill.
            var matchmaker = new Matchmaker(Content());
            for (int i = 0; i < 5; i++) matchmaker.Enqueue(Solo($"acct.strong{i}", Tdm, 1400));
            for (int i = 0; i < 5; i++) matchmaker.Enqueue(Solo($"acct.weak{i}", Tdm, 1000));

            MatchProposal proposal = matchmaker.TryForm(Tdm).Proposal;

            // Perfectly stacked sides would be 7000 against 5000.
            Assert.True(proposal.SkillGap < 2000,
                        $"skill gap of {proposal.SkillGap} — the strong players were stacked "
                        + $"({proposal.AlphaSkill} v {proposal.BravoSkill})");
        }

        [Fact]
        public void APartysSkillCountsOncePerMember()
        {
            // Otherwise a five-stack and a solo of the same rating balance as equals.
            var matchmaker = new Matchmaker(Content());
            matchmaker.Enqueue(Stack(Tdm, 1200, "a1", "a2", "a3", "a4", "a5"));
            matchmaker.Enqueue(Stack(Tdm, 1200, "b1", "b2", "b3", "b4", "b5"));

            MatchProposal proposal = matchmaker.TryForm(Tdm).Proposal;
            Assert.Equal(1200 * 5, proposal.AlphaSkill);
            Assert.Equal(1200 * 5, proposal.BravoSkill);
        }

        [Fact]
        public void PlayersFarApartInSkillDoNotMatchImmediately()
        {
            // The experts queue first, so one of them is the anchor. The anchor itself is never
            // excluded — it is the ticket the queue owes a match to — so the novice has to be
            // the one arriving late for this to test anything.
            var matchmaker = new Matchmaker(Content());
            for (int i = 0; i < 9; i++)
                matchmaker.Enqueue(Solo($"acct.expert{i}", Tdm, 4000));
            matchmaker.Enqueue(Solo("acct.novice", Tdm, 1000));

            MatchmakingResult result = matchmaker.TryForm(Tdm);
            Assert.True(result.Success, result.ReasonKey);
            Assert.DoesNotContain("acct.novice", result.Proposal.AllAccounts());
        }

        [Fact]
        public void WaitingWidensTheSkillWindow()
        {
            // The only rule that bends. A match eventually beats a perfect match.
            Assert.True(SkillRatings.ToleranceAfter(0f) < SkillRatings.ToleranceAfter(60f));
            Assert.Equal(SkillRatings.MaxTolerance, SkillRatings.ToleranceAfter(100000f));

            var matchmaker = new Matchmaker(Content());
            matchmaker.Enqueue(Solo("acct.novice", Tdm, 1000));
            for (int i = 0; i < 9; i++) matchmaker.Enqueue(Solo($"acct.expert{i}", Tdm, 2600));

            matchmaker.Tick(180f);
            MatchmakingResult result = matchmaker.TryForm(Tdm);

            Assert.True(result.Success, result.ReasonKey);
            Assert.Contains("acct.novice", result.Proposal.AllAccounts());
        }

        // ---- fairness over time ----------------------------------------------------------------

        [Fact]
        public void TheLongestWaitingPartyIsMatchedFirst()
        {
            // Without this, a party that happens to be convenient to balance is matched over and
            // over while an awkward one waits forever and nobody can see why.
            var matchmaker = new Matchmaker(Content());
            MatchmakingTicket patient = Solo("acct.patient", Tdm);
            patient.WaitSeconds = 300f;
            matchmaker.Enqueue(patient);
            FillSolos(matchmaker, 20, Tdm);

            MatchmakingResult result = matchmaker.TryForm(Tdm);
            Assert.Contains("acct.patient", result.Proposal.AllAccounts());
        }

        [Fact]
        public void TickingAgesEveryTicket()
        {
            var matchmaker = new Matchmaker(Content());
            MatchmakingTicket ticket = Solo("acct.a", Tdm);
            matchmaker.Enqueue(ticket);
            matchmaker.Tick(12.5f);
            Assert.Equal(12.5f, ticket.WaitSeconds, 3);
        }

        // ---- maps and modes -----------------------------------------------------------------------

        [Fact]
        public void TheChosenMapSupportsTheChosenMode()
        {
            var matchmaker = new Matchmaker(Content());
            FillSolos(matchmaker, 10, Overload);

            MatchProposal proposal = matchmaker.TryForm(Overload).Proposal;
            Assert.Contains(GameModeKind.RoundObjective, proposal.Map.SupportedModes);
        }

        [Fact]
        public void AWorldPreferenceIsHonouredWhenItCanBe()
        {
            var matchmaker = new Matchmaker(Content());
            for (int i = 0; i < 10; i++)
            {
                MatchmakingTicket ticket = Solo($"acct.p{i}", Tdm);
                ticket.PreferredWorlds = new ContentId[] { WartimeWorld.Id };
                matchmaker.Enqueue(ticket);
            }

            MatchProposal proposal = matchmaker.TryForm(Tdm).Proposal;
            Assert.Equal(WartimeWorld.Id, proposal.Map.WorldId);
        }

        [Fact]
        public void AnImpossibleWorldPreferenceStillGetsAMatch()
        {
            // A preference narrows the pool; it must never empty it, or a player who asked for
            // an era that has no map for this mode waits forever with no explanation.
            var matchmaker = new Matchmaker(Content());
            for (int i = 0; i < 10; i++)
            {
                MatchmakingTicket ticket = Solo($"acct.p{i}", Tdm);
                ticket.PreferredWorlds = new ContentId[] { "world.does_not_exist" };
                matchmaker.Enqueue(ticket);
            }

            MatchmakingResult result = matchmaker.TryForm(Tdm);
            Assert.True(result.Success, result.ReasonKey);
            Assert.NotNull(result.Proposal.Map);
        }

        [Fact]
        public void AFreeForAllNeedsNoTeams()
        {
            var matchmaker = new Matchmaker(Content());
            FillSolos(matchmaker, 8, Ffa);

            MatchmakingResult result = matchmaker.TryForm(Ffa);
            Assert.True(result.Success, result.ReasonKey);
            Assert.Equal(8, result.Proposal.HumanPlayers);
        }

        [Fact]
        public void ShortQueuesAreFilledToAFullLobbyNotJustTheMinimum()
        {
            // Reaching the minimum is what lets a match legally start; it is not what anyone
            // wants to play. Three humans on a map laid out for ten is worse than three humans
            // and seven bots.
            var matchmaker = new Matchmaker(Content());
            FillSolos(matchmaker, 3, Tdm);

            MatchmakingResult result = matchmaker.TryForm(Tdm);
            Assert.True(result.Success, result.ReasonKey);

            MatchProposal proposal = result.Proposal;
            Assert.Equal(proposal.Mode.TeamSize, proposal.AlphaPlayers + proposal.BotsForAlpha);
            Assert.Equal(proposal.Mode.TeamSize, proposal.BravoPlayers + proposal.BotsForBravo);
        }

        [Fact]
        public void BotsEvenOutALopsidedLobbyRatherThanStaffingAnAdvantage()
        {
            var matchmaker = new Matchmaker(Content());
            matchmaker.Enqueue(Stack(Tdm, 1000, "a1", "a2", "a3", "a4"));
            matchmaker.Enqueue(Solo("acct.lonely", Tdm));

            MatchProposal proposal = matchmaker.TryForm(Tdm).Proposal;
            Assert.Equal(proposal.AlphaPlayers + proposal.BotsForAlpha,
                         proposal.BravoPlayers + proposal.BotsForBravo);
        }

        [Fact]
        public void AFullQueueNeedsNoBots()
        {
            var matchmaker = new Matchmaker(Content());
            FillSolos(matchmaker, 10, Tdm);
            Assert.Equal(0, matchmaker.TryForm(Tdm).Proposal.BotsToAdd);
        }

        [Fact]
        public void AProposalNeverExceedsTheModesLimits()
        {
            var matchmaker = new Matchmaker(Content());
            FillSolos(matchmaker, 40, Tdm);

            MatchProposal proposal = matchmaker.TryForm(Tdm).Proposal;
            Assert.True(proposal.HumanPlayers <= proposal.Mode.MaxPlayers);
            Assert.True(proposal.AlphaPlayers <= proposal.Mode.TeamSize);
            Assert.True(proposal.BravoPlayers <= proposal.Mode.TeamSize);
        }

        // ---- the proposal actually runs ---------------------------------------------------------

        [Fact]
        public void AProposalCanBeTurnedIntoARunningMatch()
        {
            // The end of the argument: matchmaking output is match input.
            GameContent content = Content();
            var matchmaker = new Matchmaker(content);
            FillSolos(matchmaker, 10, Tdm);

            MatchProposal proposal = matchmaker.TryForm(Tdm).Proposal;
            var match = new MatchSimulation(content, proposal.Map,
                                            GameModes.Create(proposal.Mode), 9);

            Loadouts.TryBuildDefault(content, proposal.Map.WorldId, 0, out Loadout loadout);
            int variant = 0;
            foreach (Team team in new[] { Team.Alpha, Team.Bravo })
                foreach (string account in proposal.AccountsOn(team))
                {
                    Loadouts.TryBuildDefault(content, proposal.Map.WorldId, variant++, out loadout);
                    match.AddPlayer(account, team, loadout, isBot: true,
                                    botDifficulty: StarterContent.Difficulties.Normal);
                }

            var director = new BotDirector(content, 9);
            match.Start();
            foreach (PlayerRuntime player in match.Players)
                Assert.True(player.IsAlive, $"{player.Name} never spawned");

            int shots = 0;
            for (int i = 0; i < 60 * FixedClock.TicksPerSecond
                            && match.Phase != MatchPhase.MatchEnd; i++)
            {
                director.Think(match, FixedClock.TickInterval);
                match.Step();
                foreach (MatchEvent e in match.Events)
                    if (e.Kind == MatchEventKind.Fired) shots++;
            }
            Assert.True(shots > 0, "the matchmade lobby never fired a shot");
        }
    }
}
