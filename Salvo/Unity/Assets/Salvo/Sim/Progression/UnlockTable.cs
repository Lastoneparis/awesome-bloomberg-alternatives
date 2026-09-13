using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>What kind of thing a level grants.</summary>
    public enum UnlockKind : byte
    {
        /// <summary>A visual only. Never touches the simulation.</summary>
        Cosmetic,
        /// <summary>An attachment: a sidegrade with a stated downside, never a pure upgrade.</summary>
        Attachment,
        /// <summary>A title or badge shown on a scoreboard.</summary>
        Title,
    }

    public struct UnlockEntry
    {
        public ContentId Id;
        public string DisplayNameKey;
        public UnlockKind Kind;
        public int Level;

        public UnlockEntry(int level, ContentId id, string displayNameKey, UnlockKind kind)
        {
            Level = level;
            Id = id;
            DisplayNameKey = displayNameKey;
            Kind = kind;
        }
    }

    /// <summary>
    /// What each level grants.
    /// </summary>
    /// <remarks>
    /// <b>No weapon is ever unlocked.</b> Every weapon in a world is available from level one,
    /// and that is the single most important rule in this file.
    ///
    /// <para>Gating weapons behind levels is the genre default, and it is a fairness problem
    /// wearing a progression costume: a new player meets a veteran carrying something they
    /// cannot yet hold, and the difference is time served rather than skill. The brief forbids
    /// <em>selling</em> a competitive advantage; granting one for grinding is the same advantage
    /// with a slower price, and it is worse in one respect, because it is invisible to anyone
    /// auditing the store.</para>
    ///
    /// <para>So progression grants cosmetics, titles, and attachments — and attachments are
    /// already constrained by <see cref="AttachmentDefinition.Validate"/>, which rejects one
    /// that is strictly better than no attachment. <see cref="Validate"/> enforces the rest:
    /// nothing in this table may be a weapon, and every attachment named must exist and must
    /// cost the player something.</para>
    /// </remarks>
    public sealed class UnlockTable
    {
        private readonly List<UnlockEntry> _entries = new List<UnlockEntry>();

        public IReadOnlyList<UnlockEntry> Entries => _entries;

        public UnlockTable Add(UnlockEntry entry)
        {
            _entries.Add(entry);
            return this;
        }

        public IEnumerable<UnlockEntry> AtLevel(int level)
        {
            foreach (UnlockEntry entry in _entries)
                if (entry.Level == level) yield return entry;
        }

        /// <summary>
        /// Checks the table against the catalogue, and against the rule that progression may not
        /// hand out an advantage.
        /// </summary>
        public List<string> Validate(GameContent content)
        {
            var problems = new List<string>();
            var seen = new HashSet<string>();

            foreach (UnlockEntry entry in _entries)
            {
                string id = entry.Id.ToString();
                if (entry.Id.IsEmpty) { problems.Add("an unlock entry has no id"); continue; }
                if (!seen.Add(id)) problems.Add($"{id}: granted by more than one level");
                if (entry.Level < 1 || entry.Level > XpCurve.MaxLevel)
                    problems.Add($"{id}: level {entry.Level} is outside 1..{XpCurve.MaxLevel}");
                if (string.IsNullOrEmpty(entry.DisplayNameKey))
                    problems.Add($"{id}: DisplayNameKey is empty — UI would show a raw id");

                // The rule, enforced rather than documented: a weapon must never be gated.
                if (content.Weapons.Contains(entry.Id))
                    problems.Add($"{id}: is a weapon. Weapons are available from level 1 — "
                                 + "gating one behind a level is a competitive advantage granted "
                                 + "for time served.");

                if (entry.Kind != UnlockKind.Attachment) continue;

                if (!content.Attachments.TryGet(entry.Id, out AttachmentDefinition attachment))
                {
                    problems.Add($"{id}: declared an attachment but is not in the catalogue");
                    continue;
                }
                if (attachment.IsStrictlyBetter())
                    problems.Add($"{id}: is strictly better than no attachment, so unlocking it "
                                 + "is a straight upgrade rather than a new choice");
            }
            return problems;
        }
    }
}
