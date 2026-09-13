using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>A match the matchmaker has assembled but not yet started.</summary>
    public sealed class MatchProposal
    {
        public GameModeDefinition Mode;
        public MapDefinition Map;
        public readonly List<MatchmakingTicket> Alpha = new List<MatchmakingTicket>();
        public readonly List<MatchmakingTicket> Bravo = new List<MatchmakingTicket>();
        /// <summary>
        /// Bot seats needed, split per side so the caller does not have to work it out.
        /// </summary>
        /// <remarks>
        /// Filled to a <em>full</em> lobby rather than to the mode's minimum. Reaching the
        /// minimum is what lets a match legally start; it is not what anyone wants to play. Three
        /// humans on a map laid out for ten is a worse experience than three humans and seven
        /// bots, and "fill with bots" is a promise about the lobby being full.
        /// </remarks>
        public int BotsForAlpha;
        public int BotsForBravo;
        public int BotsToAdd => BotsForAlpha + BotsForBravo;

        public int AlphaPlayers => CountOf(Alpha);
        public int BravoPlayers => CountOf(Bravo);
        public int HumanPlayers => AlphaPlayers + BravoPlayers;

        public int AlphaSkill => SkillOf(Alpha);
        public int BravoSkill => SkillOf(Bravo);
        /// <summary>Difference in summed skill between the sides. Lower is a fairer match.</summary>
        public int SkillGap => System.Math.Abs(AlphaSkill - BravoSkill);

        private static int CountOf(List<MatchmakingTicket> side)
        {
            int total = 0;
            for (int i = 0; i < side.Count; i++) total += side[i].Size;
            return total;
        }

        private static int SkillOf(List<MatchmakingTicket> side)
        {
            int total = 0;
            // Weighted by party size: a five-stack's rating should count five times, or a solo
            // and a five-stack of the same skill would balance as equals.
            for (int i = 0; i < side.Count; i++) total += side[i].SkillRating * side[i].Size;
            return total;
        }

        public IEnumerable<string> AccountsOn(Team team)
        {
            List<MatchmakingTicket> side = team == Team.Alpha ? Alpha : Bravo;
            for (int i = 0; i < side.Count; i++)
                for (int j = 0; j < side[i].Accounts.Count; j++)
                    yield return side[i].Accounts[j];
        }

        public IEnumerable<string> AllAccounts()
        {
            foreach (string account in AccountsOn(Team.Alpha)) yield return account;
            foreach (string account in AccountsOn(Team.Bravo)) yield return account;
        }
    }

    /// <summary>Why the matchmaker could not form a match this pass.</summary>
    public enum MatchmakingOutcome : byte
    {
        Formed,
        /// <summary>Not enough players queued for this mode yet.</summary>
        NotEnoughPlayers,
        /// <summary>Enough players, but every combination puts blocked players together.</summary>
        BlockedByAvoidance,
        /// <summary>No map in the catalogue supports this mode.</summary>
        NoSuitableMap,
        /// <summary>Players are queued, but too far apart in skill for their current wait.</summary>
        SkillTooFarApart,
    }

    public struct MatchmakingResult
    {
        public MatchmakingOutcome Outcome;
        public MatchProposal Proposal;
        public string ReasonKey;

        /// <summary>
        /// Parties left out of this match because of a block, whether or not one formed anyway.
        /// </summary>
        /// <remarks>
        /// Reported on success too, and that is the point. Avoidance that only surfaces when it
        /// prevents a match is invisible in exactly the case that matters most: a queue that
        /// fills fine but in which one player is quietly never matched with anybody. A number
        /// that climbs is the only way anyone operating the service finds out.
        /// </remarks>
        public int ExcludedByAvoidance;

        public bool Success => Outcome == MatchmakingOutcome.Formed;
    }

    /// <summary>
    /// Turns a queue of parties into a balanced match.
    /// </summary>
    /// <remarks>
    /// Four rules, in strict priority order. The order is the design, because they conflict:
    /// a perfectly balanced match is easy if you are allowed to split parties and ignore blocks.
    ///
    /// <list type="number">
    /// <item><b>Blocked players never share a match.</b> Not merely never share a team — if A
    /// blocked B, putting them in the same match still means A sees B's name, is shot by B, and
    /// can be followed by B. This is the one rule that is never relaxed to fill a lobby; see
    /// below.</item>
    /// <item><b>A party is never split.</b> People queue together to play together, and a
    /// matchmaker that separates them has failed at the thing they asked for.</item>
    /// <item><b>Teams are even in size</b>, within one player.</item>
    /// <item><b>Teams are close in skill</b>, and only this rule bends as the queue waits.</item>
    /// </list>
    ///
    /// <para><b>On not relaxing the block rule.</b> The tempting engineering move, when a small
    /// player base cannot fill a lobby, is to quietly allow blocked players together rather than
    /// leave everyone waiting. That trades a visible problem — an empty queue, which players
    /// understand and which shows up in metrics — for an invisible one, where somebody is put in
    /// a match with a person they took deliberate action to avoid, and nothing anywhere records
    /// that it happened. So this returns <see cref="MatchmakingOutcome.BlockedByAvoidance"/> and
    /// says so, and whoever operates the service decides what to do about it with the
    /// information in front of them.</para>
    /// </remarks>
    public sealed class Matchmaker
    {
        private readonly GameContent _content;
        private readonly SocialGraph _graph;
        private readonly List<MatchmakingTicket> _queue = new List<MatchmakingTicket>();

        public Matchmaker(GameContent content, SocialGraph graph = null)
        {
            _content = content ?? throw new System.ArgumentNullException(nameof(content));
            _graph = graph;
        }

        public IReadOnlyList<MatchmakingTicket> Queue => _queue;
        public int QueuedPlayers
        {
            get
            {
                int total = 0;
                for (int i = 0; i < _queue.Count; i++) total += _queue[i].Size;
                return total;
            }
        }

        public void Enqueue(MatchmakingTicket ticket)
        {
            if (ticket == null || ticket.Size == 0) return;
            _queue.Add(ticket);
        }

        public bool Remove(MatchmakingTicket ticket) => _queue.Remove(ticket);

        /// <summary>Ages the queue. Longer waits widen the skill tolerance and raise priority.</summary>
        public void Tick(float deltaSeconds)
        {
            for (int i = 0; i < _queue.Count; i++) _queue[i].WaitSeconds += deltaSeconds;
        }

        /// <summary>
        /// Attempts to form one match for a mode. On success the chosen tickets leave the queue.
        /// </summary>
        public MatchmakingResult TryForm(ContentId modeId, uint seed = 0)
        {
            if (!_content.GameModes.TryGet(modeId, out GameModeDefinition mode))
            {
                return new MatchmakingResult
                {
                    Outcome = MatchmakingOutcome.NoSuitableMap,
                    ReasonKey = "matchmaking.error.unknown_mode",
                };
            }

            var candidates = new List<MatchmakingTicket>();
            for (int i = 0; i < _queue.Count; i++)
                if (_queue[i].ModeId == modeId) candidates.Add(_queue[i]);

            int queuedForMode = 0;
            for (int i = 0; i < candidates.Count; i++) queuedForMode += candidates[i].Size;
            if (queuedForMode < mode.MinPlayers && !mode.FillWithBots)
                return Failure(MatchmakingOutcome.NotEnoughPlayers, "matchmaking.waiting.players");

            // Longest wait first. Without it a party that happens to be convenient to balance is
            // matched repeatedly while an awkward one waits forever, and nobody can see why.
            candidates.Sort((a, b) => b.WaitSeconds.CompareTo(a.WaitSeconds));

            List<MatchmakingTicket> selected = Select(candidates, mode, out int excludedByAvoidance);
            bool blockedSomeone = excludedByAvoidance > 0;
            int selectedPlayers = 0;
            for (int i = 0; i < selected.Count; i++) selectedPlayers += selected[i].Size;

            if (selectedPlayers < mode.MinPlayers && !mode.FillWithBots)
            {
                return Failure(
                    blockedSomeone ? MatchmakingOutcome.BlockedByAvoidance
                                   : MatchmakingOutcome.NotEnoughPlayers,
                    blockedSomeone ? "matchmaking.waiting.avoidance" : "matchmaking.waiting.players",
                    excludedByAvoidance);
            }
            if (selected.Count == 0)
                return Failure(MatchmakingOutcome.NotEnoughPlayers, "matchmaking.waiting.players",
                               excludedByAvoidance);

            MapDefinition map = ChooseMap(mode, selected, seed);
            if (map == null)
                return Failure(MatchmakingOutcome.NoSuitableMap, "matchmaking.error.no_map");

            var proposal = new MatchProposal { Mode = mode, Map = map };
            List<MatchmakingTicket> unplaced = AssignTeams(selected, mode, proposal);

            FillWithBots(mode, proposal);

            // Only what actually landed on a team leaves the queue. A ticket that was selected
            // but fitted nowhere once the sides filled up must stay queued: removing it takes
            // those players out of matchmaking and puts them in no match at all, which looks
            // from the outside like the queue silently losing people. It did, until a run of
            // sixty showed 56 placed and none still waiting.
            for (int i = 0; i < selected.Count; i++)
                if (!unplaced.Contains(selected[i])) _queue.Remove(selected[i]);

            return new MatchmakingResult
            {
                Outcome = MatchmakingOutcome.Formed,
                Proposal = proposal,
                ReasonKey = "matchmaking.formed",
                ExcludedByAvoidance = excludedByAvoidance,
            };
        }

        private static MatchmakingResult Failure(MatchmakingOutcome outcome, string reasonKey,
                                                 int excludedByAvoidance = 0) =>
            new MatchmakingResult
            {
                Outcome = outcome, ReasonKey = reasonKey,
                ExcludedByAvoidance = excludedByAvoidance,
            };

        /// <summary>
        /// Tops the lobby up with bots, keeping the sides even.
        /// </summary>
        private static void FillWithBots(GameModeDefinition mode, MatchProposal proposal)
        {
            if (!mode.FillWithBots) return;

            if (!mode.IsTeamBased)
            {
                proposal.BotsForAlpha =
                    System.Math.Max(0, mode.MaxPlayers - proposal.HumanPlayers);
                return;
            }

            // Each side is brought up to the team size independently, which evens out a lobby
            // that arrived lopsided — four humans on one side and one on the other becomes
            // 4+1 against 1+4 rather than a four-man advantage staffed by bots.
            proposal.BotsForAlpha = System.Math.Max(0, mode.TeamSize - proposal.AlphaPlayers);
            proposal.BotsForBravo = System.Math.Max(0, mode.TeamSize - proposal.BravoPlayers);
        }

        /// <summary>
        /// Greedily fills a match, skipping any party that cannot coexist with those chosen.
        /// </summary>
        private List<MatchmakingTicket> Select(List<MatchmakingTicket> candidates,
                                               GameModeDefinition mode, out int excludedByAvoidance)
        {
            excludedByAvoidance = 0;
            var selected = new List<MatchmakingTicket>();
            var chosenAccounts = new List<string>();

            if (candidates.Count == 0) return selected;
            int seats = System.Math.Min(mode.MaxPlayers,
                                        mode.IsTeamBased ? mode.TeamSize * 2 : mode.MaxPlayers);

            // Skill tolerance is anchored on the longest-waiting ticket, which is the one the
            // queue owes a match to. Anchoring on an average would let one outlier drag the
            // window away from everybody.
            MatchmakingTicket anchor = candidates[0];
            int tolerance = SkillRatings.ToleranceAfter(anchor.WaitSeconds);

            for (int i = 0; i < candidates.Count; i++)
            {
                MatchmakingTicket ticket = candidates[i];

                int used = 0;
                for (int s = 0; s < selected.Count; s++) used += selected[s].Size;
                if (used + ticket.Size > seats) continue;

                if (ticket.Size > MaxPartySizeFor(mode)) continue;
                if (System.Math.Abs(ticket.SkillRating - anchor.SkillRating) > tolerance) continue;

                if (ConflictsWithAny(ticket, chosenAccounts))
                {
                    excludedByAvoidance++;
                    continue;
                }

                selected.Add(ticket);
                chosenAccounts.AddRange(ticket.Accounts);
                if (used + ticket.Size >= seats) break;
            }
            return selected;
        }

        private static int MaxPartySizeFor(GameModeDefinition mode) =>
            mode.IsTeamBased ? System.Math.Max(1, mode.TeamSize) : Party.AbsoluteMaxSize;

        /// <summary>True if anybody in this ticket has blocked, or been blocked by, anyone
        /// already selected.</summary>
        private bool ConflictsWithAny(MatchmakingTicket ticket, List<string> chosen)
        {
            if (_graph == null) return false;

            // Within the ticket first. A party whose own members have blocked each other should
            // not exist — Party.EnforceBlocks sees to that — but the matchmaker receives tickets,
            // not parties, and cannot verify where they came from. Checking only against
            // already-chosen accounts let such a party through every other rule here, and a
            // sixty-party queue found it immediately where four hand-written tickets never would.
            for (int i = 0; i < ticket.Accounts.Count; i++)
                for (int j = i + 1; j < ticket.Accounts.Count; j++)
                    if (!_graph.MayInteract(ticket.Accounts[i], ticket.Accounts[j])) return true;

            for (int i = 0; i < ticket.Accounts.Count; i++)
                for (int j = 0; j < chosen.Count; j++)
                    if (!_graph.MayInteract(ticket.Accounts[i], chosen[j])) return true;
            return false;
        }

        private MapDefinition ChooseMap(GameModeDefinition mode, List<MatchmakingTicket> selected,
                                        uint seed)
        {
            var suitable = new List<MapDefinition>();
            var preferred = new List<MapDefinition>();

            var wanted = new HashSet<string>();
            for (int i = 0; i < selected.Count; i++)
                for (int w = 0; w < selected[i].PreferredWorlds.Length; w++)
                    wanted.Add(selected[i].PreferredWorlds[w].ToString());

            foreach (MapDefinition map in _content.Maps.All)
            {
                if (!Supports(map, mode.Kind)) continue;
                int players = 0;
                for (int i = 0; i < selected.Count; i++) players += selected[i].Size;
                if (map.RecommendedMaxPlayers > 0 && players > map.RecommendedMaxPlayers) continue;

                suitable.Add(map);
                if (wanted.Count > 0 && wanted.Contains(map.WorldId.ToString())) preferred.Add(map);
            }

            // A world preference narrows the pool but never empties it: a player who has asked
            // for one era gets it when possible and a match when not, rather than waiting
            // forever for a map that may not exist.
            List<MapDefinition> pool = preferred.Count > 0 ? preferred : suitable;
            if (pool.Count == 0) return null;

            var random = DeterministicRandom.Seeded(seed, (uint)pool.Count);
            return pool[random.NextInt(pool.Count)];
        }

        private static bool Supports(MapDefinition map, GameModeKind kind)
        {
            if (map.SupportedModes == null || map.SupportedModes.Length == 0) return true;
            for (int i = 0; i < map.SupportedModes.Length; i++)
                if (map.SupportedModes[i] == kind) return true;
            return false;
        }

        /// <summary>
        /// Splits the chosen parties into two sides.
        /// </summary>
        /// <remarks>
        /// Largest party first, each onto whichever side has room and is currently behind. This
        /// is greedy longest-processing-time-first, which is not optimal and is the right choice
        /// anyway: the optimal split is a partition problem, and spending milliseconds on it
        /// would buy a balance difference far smaller than the noise in the skill numbers
        /// feeding it. Placing the largest parties first is what matters, because a five-stack
        /// placed last has nowhere to go.
        /// </remarks>
        /// <returns>Tickets that fitted on neither side, which must stay in the queue.</returns>
        private static List<MatchmakingTicket> AssignTeams(List<MatchmakingTicket> selected,
                                                           GameModeDefinition mode,
                                                           MatchProposal proposal)
        {
            var unplaced = new List<MatchmakingTicket>();
            if (!mode.IsTeamBased)
            {
                // Free-for-all still uses Alpha as a holding list; the match assigns Team.None.
                for (int i = 0; i < selected.Count; i++) proposal.Alpha.Add(selected[i]);
                return unplaced;
            }

            var ordered = new List<MatchmakingTicket>(selected);
            ordered.Sort((a, b) =>
            {
                int bySize = b.Size.CompareTo(a.Size);
                // Never returns 0 for distinct tickets of equal size, so an unstable sort cannot
                // make the assignment depend on input order.
                return bySize != 0 ? bySize : b.SkillRating.CompareTo(a.SkillRating);
            });

            int cap = mode.TeamSize;
            for (int i = 0; i < ordered.Count; i++)
            {
                MatchmakingTicket ticket = ordered[i];
                bool alphaFits = proposal.AlphaPlayers + ticket.Size <= cap;
                bool bravoFits = proposal.BravoPlayers + ticket.Size <= cap;

                if (alphaFits && !bravoFits) { proposal.Alpha.Add(ticket); continue; }
                if (bravoFits && !alphaFits) { proposal.Bravo.Add(ticket); continue; }
                if (!alphaFits) { unplaced.Add(ticket); continue; }   // fits nowhere

                // Both fit: put it on the smaller side, and break a size tie on skill.
                if (proposal.AlphaPlayers < proposal.BravoPlayers) proposal.Alpha.Add(ticket);
                else if (proposal.BravoPlayers < proposal.AlphaPlayers) proposal.Bravo.Add(ticket);
                else if (proposal.AlphaSkill <= proposal.BravoSkill) proposal.Alpha.Add(ticket);
                else proposal.Bravo.Add(ticket);
            }
            return unplaced;
        }
    }
}
