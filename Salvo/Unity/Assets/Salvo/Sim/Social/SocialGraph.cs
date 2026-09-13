using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>Why a social action was refused. A key, never a sentence (§22).</summary>
    public enum SocialResult : byte
    {
        Ok,
        /// <summary>Already friends, request already sent, already blocked.</summary>
        AlreadyApplies,
        /// <summary>One party has blocked the other.</summary>
        Blocked,
        /// <summary>A player tried to act on themselves.</summary>
        Self,
        /// <summary>The friend list is full.</summary>
        ListFull,
        /// <summary>No such pending request.</summary>
        NotFound,
    }

    /// <summary>
    /// Who knows whom, who is waiting on whom, and who wants nothing to do with whom.
    /// </summary>
    /// <remarks>
    /// <b>Blocking is the load-bearing feature here, not friending.</b> Friend lists fail
    /// harmlessly; block lists fail by exposing someone to a person they have deliberately shut
    /// out, and a block list that is merely a filter on a friends UI is not a block list at all.
    /// So blocking is enforced at the graph level and is stronger than every other relationship:
    /// it removes an existing friendship, cancels pending requests in both directions, and makes
    /// any future request from either side fail. Every method that could create a link checks it
    /// first.
    ///
    /// <para>It is also deliberately <em>mutual in effect while one-sided in intent</em>. If A
    /// blocks B, then B cannot reach A — and A cannot reach B either. A one-directional block
    /// lets the blocker keep sending invitations to someone who has no way to refuse them, which
    /// is a harassment vector rather than a convenience.</para>
    ///
    /// <para>The graph stores account ids and nothing else. No names, no history, no timestamps,
    /// no "people you may know" — §33 of the brief is explicit about not building invasive
    /// privacy practices, and the cheapest way to honour that is to have nowhere to put the
    /// data. A display name belongs to the account record and is fetched when a list is shown.</para>
    /// </remarks>
    public sealed class SocialGraph
    {
        /// <summary>A cap exists so the list stays something a person can manage, and so one
        /// account cannot make itself expensive to serve.</summary>
        public const int MaxFriends = 200;
        public const int MaxBlocked = 500;
        public const int MaxPendingOutgoing = 50;

        private readonly Dictionary<string, HashSet<string>> _friends =
            new Dictionary<string, HashSet<string>>();
        private readonly Dictionary<string, HashSet<string>> _outgoing =
            new Dictionary<string, HashSet<string>>();
        private readonly Dictionary<string, HashSet<string>> _blocked =
            new Dictionary<string, HashSet<string>>();

        private static HashSet<string> Bucket(Dictionary<string, HashSet<string>> map, string key)
        {
            if (!map.TryGetValue(key, out HashSet<string> set))
            {
                set = new HashSet<string>();
                map[key] = set;
            }
            return set;
        }

        private static IReadOnlyCollection<string> Read(Dictionary<string, HashSet<string>> map,
                                                        string key) =>
            map.TryGetValue(key, out HashSet<string> set)
                ? (IReadOnlyCollection<string>)set
                : System.Array.Empty<string>();

        public IReadOnlyCollection<string> FriendsOf(string account) => Read(_friends, account);
        public IReadOnlyCollection<string> OutgoingRequestsOf(string account) => Read(_outgoing, account);
        public IReadOnlyCollection<string> BlockedBy(string account) => Read(_blocked, account);

        public bool AreFriends(string a, string b) =>
            _friends.TryGetValue(a, out HashSet<string> set) && set.Contains(b);

        /// <summary>
        /// True when either has blocked the other.
        /// </summary>
        /// <remarks>
        /// Checked in both directions everywhere. Asking only "has A blocked B" would let the
        /// blocker keep contacting someone who has shut them out.
        /// </remarks>
        public bool IsBlockedEitherWay(string a, string b) =>
            (_blocked.TryGetValue(a, out HashSet<string> byA) && byA.Contains(b))
            || (_blocked.TryGetValue(b, out HashSet<string> byB) && byB.Contains(a));

        /// <summary>Incoming requests, derived rather than stored — one source of truth for a
        /// pending request, so the two directions cannot disagree.</summary>
        public List<string> IncomingRequestsFor(string account)
        {
            var incoming = new List<string>();
            foreach (KeyValuePair<string, HashSet<string>> entry in _outgoing)
                if (entry.Value.Contains(account)) incoming.Add(entry.Key);
            incoming.Sort(System.StringComparer.Ordinal);
            return incoming;
        }

        public SocialResult SendRequest(string from, string to)
        {
            if (string.IsNullOrEmpty(from) || string.IsNullOrEmpty(to)) return SocialResult.NotFound;
            if (from == to) return SocialResult.Self;
            if (IsBlockedEitherWay(from, to)) return SocialResult.Blocked;
            if (AreFriends(from, to)) return SocialResult.AlreadyApplies;

            HashSet<string> outgoing = Bucket(_outgoing, from);
            if (outgoing.Contains(to)) return SocialResult.AlreadyApplies;
            if (outgoing.Count >= MaxPendingOutgoing) return SocialResult.ListFull;
            if (FriendsOf(from).Count >= MaxFriends) return SocialResult.ListFull;

            // If they already asked us, this is an acceptance rather than a second request.
            // Without this, two people who ask each other at the same moment end up with two
            // pending requests and no friendship, and neither can work out why.
            if (_outgoing.TryGetValue(to, out HashSet<string> theirs) && theirs.Contains(from))
                return Accept(to, from);

            outgoing.Add(to);
            return SocialResult.Ok;
        }

        /// <summary>Accepts <paramref name="from"/>'s request to <paramref name="by"/>.</summary>
        public SocialResult Accept(string from, string by)
        {
            if (from == by) return SocialResult.Self;
            if (IsBlockedEitherWay(from, by)) return SocialResult.Blocked;
            if (!_outgoing.TryGetValue(from, out HashSet<string> outgoing)
                || !outgoing.Contains(by)) return SocialResult.NotFound;

            if (FriendsOf(from).Count >= MaxFriends || FriendsOf(by).Count >= MaxFriends)
                return SocialResult.ListFull;

            outgoing.Remove(by);
            Bucket(_friends, from).Add(by);
            Bucket(_friends, by).Add(from);
            return SocialResult.Ok;
        }

        /// <summary>
        /// Re-establishes a friendship that already existed, without a request.
        /// </summary>
        /// <remarks>
        /// For loading saved state, and deliberately not a general-purpose "make these two
        /// friends". It still honours blocks: a save written before one side blocked the other
        /// must not resurrect the friendship that block was meant to sever, and a save is not a
        /// reason to override a decision a player made since.
        /// </remarks>
        public SocialResult RestoreFriendship(string a, string b)
        {
            if (string.IsNullOrEmpty(a) || string.IsNullOrEmpty(b)) return SocialResult.NotFound;
            if (a == b) return SocialResult.Self;
            if (IsBlockedEitherWay(a, b)) return SocialResult.Blocked;
            if (FriendsOf(a).Count >= MaxFriends || FriendsOf(b).Count >= MaxFriends)
                return SocialResult.ListFull;

            Bucket(_friends, a).Add(b);
            Bucket(_friends, b).Add(a);
            return SocialResult.Ok;
        }

        public SocialResult Decline(string from, string by)
        {
            if (!_outgoing.TryGetValue(from, out HashSet<string> outgoing)
                || !outgoing.Remove(by)) return SocialResult.NotFound;
            return SocialResult.Ok;
        }

        public SocialResult CancelRequest(string from, string to) => Decline(from, to);

        public SocialResult Unfriend(string a, string b)
        {
            bool removed = _friends.TryGetValue(a, out HashSet<string> setA) && setA.Remove(b);
            if (_friends.TryGetValue(b, out HashSet<string> setB)) setB.Remove(a);
            return removed ? SocialResult.Ok : SocialResult.NotFound;
        }

        /// <summary>
        /// Blocks <paramref name="other"/> for <paramref name="account"/>, and severs everything
        /// that existed between them.
        /// </summary>
        /// <remarks>
        /// The severing is the point. A block that leaves the friendship in place is a block that
        /// does nothing the moment any code path looks at the friend list instead of the block
        /// list — and there will always be such a path.
        /// </remarks>
        public SocialResult Block(string account, string other)
        {
            if (string.IsNullOrEmpty(account) || string.IsNullOrEmpty(other)) return SocialResult.NotFound;
            if (account == other) return SocialResult.Self;

            HashSet<string> blocked = Bucket(_blocked, account);
            if (blocked.Contains(other)) return SocialResult.AlreadyApplies;
            if (blocked.Count >= MaxBlocked) return SocialResult.ListFull;

            blocked.Add(other);
            Unfriend(account, other);
            CancelRequest(account, other);
            CancelRequest(other, account);
            return SocialResult.Ok;
        }

        /// <summary>
        /// Unblocks. Deliberately does not restore the friendship: re-adding someone is a
        /// decision both people should get to make again.
        /// </summary>
        public SocialResult Unblock(string account, string other)
        {
            if (!_blocked.TryGetValue(account, out HashSet<string> blocked)
                || !blocked.Remove(other)) return SocialResult.NotFound;
            return SocialResult.Ok;
        }

        /// <summary>
        /// Erases an account from the graph entirely, in every direction.
        /// </summary>
        /// <remarks>
        /// Account deletion is a store requirement (§37) and a legal one in several
        /// jurisdictions, and a half-deletion is worse than none: an account that disappears from
        /// its own friend list but lingers in everyone else's is still personal data, and it
        /// still shows up as a ghost entry nobody can remove.
        ///
        /// <para>That includes other people's <em>block</em> lists, which is worth stating
        /// because keeping them is the tempting choice: surely a block should outlive the
        /// blocked account? It should not, and the reasoning is practical rather than legal. A
        /// deleted account's id is never reissued, so the retained entry protects nobody — it is
        /// a dead identifier that can only serve as a record of who someone once blocked. The
        /// safety case for retention would need ids to be reusable, and if they ever become so,
        /// the fix is to keep a hash of the deleted id rather than to keep the id.</para>
        /// </remarks>
        public void ForgetAccount(string account)
        {
            _friends.Remove(account);
            _outgoing.Remove(account);
            _blocked.Remove(account);

            foreach (KeyValuePair<string, HashSet<string>> entry in _friends) entry.Value.Remove(account);
            foreach (KeyValuePair<string, HashSet<string>> entry in _outgoing) entry.Value.Remove(account);
            foreach (KeyValuePair<string, HashSet<string>> entry in _blocked) entry.Value.Remove(account);
        }

        /// <summary>
        /// True if <paramref name="account"/> appears anywhere in the graph. For verifying a
        /// deletion actually deleted, which is a claim worth being able to check rather than
        /// assert.
        /// </summary>
        public bool KnowsAnythingAbout(string account)
        {
            if (_friends.ContainsKey(account) || _outgoing.ContainsKey(account)
                || _blocked.ContainsKey(account)) return true;

            foreach (KeyValuePair<string, HashSet<string>> entry in _friends)
                if (entry.Value.Contains(account)) return true;
            foreach (KeyValuePair<string, HashSet<string>> entry in _outgoing)
                if (entry.Value.Contains(account)) return true;
            foreach (KeyValuePair<string, HashSet<string>> entry in _blocked)
                if (entry.Value.Contains(account)) return true;
            return false;
        }

        /// <summary>
        /// Whether two accounts may be shown to, invited by, or matched with one another.
        /// </summary>
        /// <remarks>
        /// The single question every other system should ask. Party invitations, lobby
        /// visibility, voice, and the post-match scoreboard all go through here, so a block is
        /// enforced in one place rather than remembered in five.
        /// </remarks>
        public bool MayInteract(string a, string b) => a != b && !IsBlockedEitherWay(a, b);
    }
}
