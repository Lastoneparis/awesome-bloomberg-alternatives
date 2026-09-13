using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>
    /// A group of players who queue and play together.
    /// </summary>
    /// <remarks>
    /// Deliberately small and boring, because parties are where social systems leak. Three rules
    /// carry most of the weight:
    ///
    /// <list type="bullet">
    /// <item>Every invitation goes through <see cref="SocialGraph.MayInteract"/>, so a block is
    /// enforced here rather than remembered here. A party invite that bypasses the block list
    /// is a direct line to someone who has shut you out.</item>
    /// <item>A party can never exceed the team size of the mode it queues for. A party of six
    /// queueing for a 5v5 either splits a team across two matches or silently drops someone,
    /// and both are worse than refusing the sixth invitation.</item>
    /// <item>Leadership migrates when the leader leaves. A leaderless party cannot invite,
    /// queue, or disband, and the members cannot tell why — it just stops working.</item>
    /// </list>
    /// </remarks>
    public sealed class Party
    {
        private readonly List<string> _members = new List<string>();
        private readonly List<string> _invited = new List<string>();
        private readonly HashSet<string> _ready = new HashSet<string>();

        /// <summary>Ceiling across every mode. A party may still be capped lower by the mode it
        /// queues for — see <see cref="MaxSizeFor"/>.</summary>
        public const int AbsoluteMaxSize = 5;

        public string Leader { get; private set; }
        public IReadOnlyList<string> Members => _members;
        public IReadOnlyList<string> Invited => _invited;
        public int Size => _members.Count;
        public bool IsEmpty => _members.Count == 0;

        public Party(string founder)
        {
            if (string.IsNullOrEmpty(founder))
                throw new System.ArgumentException("a party needs a founder", nameof(founder));
            Leader = founder;
            _members.Add(founder);
        }

        public bool Contains(string account) => _members.Contains(account);
        public bool IsReady(string account) => _ready.Contains(account);
        /// <summary>True when every member has readied. A one-person party is ready when they are.</summary>
        public bool EveryoneReady()
        {
            for (int i = 0; i < _members.Count; i++)
                if (!_ready.Contains(_members[i])) return false;
            return _members.Count > 0;
        }

        /// <summary>
        /// The largest party that may queue for a mode.
        /// </summary>
        /// <remarks>
        /// A free-for-all has a team size of one, and a party in a free-for-all is a group of
        /// people who want to be in the same match while trying to kill each other — which is
        /// legitimate, so the cap there is the absolute maximum rather than one.
        /// </remarks>
        public static int MaxSizeFor(GameModeDefinition mode)
        {
            if (mode == null) return AbsoluteMaxSize;
            if (!mode.IsTeamBased) return AbsoluteMaxSize;
            return System.Math.Min(AbsoluteMaxSize, System.Math.Max(1, mode.TeamSize));
        }

        public SocialResult Invite(string inviter, string invitee, SocialGraph graph,
                                   GameModeDefinition mode = null)
        {
            if (inviter != Leader) return SocialResult.NotFound;
            if (string.IsNullOrEmpty(invitee)) return SocialResult.NotFound;
            if (Contains(invitee)) return SocialResult.AlreadyApplies;
            if (_invited.Contains(invitee)) return SocialResult.AlreadyApplies;

            // Every member, not just the leader. A party is a room, and putting someone in a
            // room with a person who has blocked them is the same failure whoever opened the
            // door.
            for (int i = 0; i < _members.Count; i++)
                if (graph != null && !graph.MayInteract(_members[i], invitee))
                    return SocialResult.Blocked;

            int cap = MaxSizeFor(mode);
            if (_members.Count + _invited.Count >= cap) return SocialResult.ListFull;

            _invited.Add(invitee);
            return SocialResult.Ok;
        }

        public SocialResult AcceptInvite(string invitee, SocialGraph graph,
                                         GameModeDefinition mode = null)
        {
            if (!_invited.Remove(invitee)) return SocialResult.NotFound;

            // Re-checked on acceptance, not only on invitation. Someone may have blocked the
            // invitee in between, and the invitation is not a licence that outlives that.
            for (int i = 0; i < _members.Count; i++)
                if (graph != null && !graph.MayInteract(_members[i], invitee))
                    return SocialResult.Blocked;

            if (_members.Count >= MaxSizeFor(mode)) return SocialResult.ListFull;

            _members.Add(invitee);
            return SocialResult.Ok;
        }

        public SocialResult DeclineInvite(string invitee) =>
            _invited.Remove(invitee) ? SocialResult.Ok : SocialResult.NotFound;

        /// <summary>
        /// Removes a member, migrating leadership if it was the leader.
        /// </summary>
        /// <remarks>
        /// Migration is to the longest-standing remaining member rather than at random, so the
        /// outcome is predictable to everyone in the party and reproducible in a bug report.
        /// </remarks>
        public SocialResult Leave(string account)
        {
            if (!_members.Remove(account)) return SocialResult.NotFound;
            _ready.Remove(account);

            if (Leader == account) Leader = _members.Count > 0 ? _members[0] : null;
            return SocialResult.Ok;
        }

        public SocialResult Kick(string by, string account)
        {
            if (by != Leader) return SocialResult.NotFound;
            if (by == account) return SocialResult.Self;
            return Leave(account);
        }

        public void SetReady(string account, bool ready)
        {
            if (!Contains(account)) return;
            if (ready) _ready.Add(account);
            else _ready.Remove(account);
        }

        /// <summary>
        /// Drops everyone a block now prevents from being here.
        /// </summary>
        /// <remarks>
        /// Called when the graph changes, because a block made while a party already exists must
        /// take effect immediately. Without it, blocking someone you are currently partied with
        /// does nothing until the party happens to disband — which is precisely when it matters
        /// least.
        /// </remarks>
        public List<string> EnforceBlocks(SocialGraph graph)
        {
            var removed = new List<string>();
            if (graph == null) return removed;

            for (int i = _members.Count - 1; i > 0; i--)
            {
                bool allowed = true;
                for (int j = 0; j < _members.Count && allowed; j++)
                {
                    if (i == j) continue;
                    if (!graph.MayInteract(_members[i], _members[j])) allowed = false;
                }
                if (allowed) continue;
                removed.Add(_members[i]);
                Leave(_members[i]);
            }

            for (int i = _invited.Count - 1; i >= 0; i--)
            {
                for (int j = 0; j < _members.Count; j++)
                {
                    if (graph.MayInteract(_members[j], _invited[i])) continue;
                    _invited.RemoveAt(i);
                    break;
                }
            }
            return removed;
        }

        /// <summary>
        /// Whether this party may queue for a mode.
        /// </summary>
        public bool CanQueueFor(GameModeDefinition mode, out string reasonKey)
        {
            reasonKey = "";
            if (mode == null) { reasonKey = "party.error.no_mode"; return false; }
            if (_members.Count == 0) { reasonKey = "party.error.empty"; return false; }
            if (_members.Count > MaxSizeFor(mode))
            {
                reasonKey = "party.error.too_large_for_mode";
                return false;
            }
            if (!EveryoneReady()) { reasonKey = "party.error.not_everyone_ready"; return false; }
            return true;
        }
    }
}
