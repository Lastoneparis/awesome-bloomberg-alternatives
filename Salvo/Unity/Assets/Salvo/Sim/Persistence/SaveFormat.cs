using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Salvo.Sim
{
    /// <summary>How reading a save turned out.</summary>
    public enum SaveReadStatus : byte
    {
        Ok,
        /// <summary>Nothing there. A new account, not an error.</summary>
        Empty,
        /// <summary>Written by a newer build. Refused rather than partially read.</summary>
        TooNew,
        /// <summary>Unreadable. The caller should try a backup before assuming loss.</summary>
        Corrupt,
    }

    public struct SaveReadResult
    {
        public SaveReadStatus Status;
        public string Detail;
        public bool Ok => Status == SaveReadStatus.Ok;
    }

    /// <summary>
    /// Reads and writes an account's saved state.
    /// </summary>
    /// <remarks>
    /// A line-oriented text format, chosen over a binary one deliberately. Save data is the one
    /// thing in a game that genuinely cannot be regenerated: a lost match is a bad evening, a
    /// lost account is a player who stops playing. When one does go wrong the first thing anyone
    /// needs is to look at it, and a bit-packed blob cannot be looked at. The cost is size, which
    /// for a few hundred lines per account is not a cost.
    ///
    /// <para>Every file starts with a version. <b>A save from a newer build is refused, never
    /// partially read.</b> The tempting behaviour — read what you recognise and ignore the rest —
    /// silently destroys whatever the newer build added the moment the older one saves back over
    /// it. A player who briefly opens an old client would lose everything earned since. Refusing
    /// is visible and recoverable; silent truncation is neither.</para>
    ///
    /// <para>Unknown keys <em>within</em> a known version are skipped rather than rejected,
    /// because that case is a forward-compatible addition inside the same schema and the
    /// alternative would make every additive change a breaking one.</para>
    /// </remarks>
    public static class SaveFormat
    {
        /// <summary>Bumped whenever the schema changes in a way an older build could not
        /// round-trip. <see cref="Migrations"/> must gain an entry at the same time.</summary>
        public const int CurrentVersion = 2;
        public const string Magic = "salvo-save";

        // ---- writing ---------------------------------------------------------------------

        public static string Write(PlayerProgress progress, SocialGraph graph = null)
        {
            if (progress == null) throw new System.ArgumentNullException(nameof(progress));

            var builder = new StringBuilder();
            builder.Append(Magic).Append(' ').Append(CurrentVersion).Append('\n');
            Line(builder, "account", progress.AccountId);
            Line(builder, "xp", progress.TotalXp);

            CareerStats career = progress.Career;
            Line(builder, "career.matches", career.MatchesPlayed);
            Line(builder, "career.wins", career.MatchesWon);
            Line(builder, "career.kills", career.Kills);
            Line(builder, "career.deaths", career.Deaths);
            Line(builder, "career.assists", career.Assists);
            Line(builder, "career.headshots", career.Headshots);
            Line(builder, "career.objectives", career.ObjectivesCompleted);
            Line(builder, "career.damage", career.DamageDealt);
            Line(builder, "career.seconds", career.SecondsPlayed);
            Line(builder, "career.beststreak", career.BestKillStreak);

            // Sorted, so the same state always produces the same bytes. That makes a save
            // diffable between two runs, which is how a "progress is being lost" report gets
            // answered in minutes instead of days.
            var weaponIds = new List<string>(progress.WeaponIds);
            weaponIds.Sort(System.StringComparer.Ordinal);
            foreach (string id in weaponIds)
            {
                WeaponStats stats = progress.StatsFor(id);
                builder.Append("weapon ").Append(Escape(id)).Append(' ')
                       .Append(stats.Kills).Append(' ').Append(stats.Headshots).Append(' ')
                       .Append(stats.DamageDealt).Append(' ').Append(stats.ShotsFired).Append(' ')
                       .Append(stats.ShotsHit).Append('\n');
            }

            var unlocks = new List<string>(progress.Unlocked);
            unlocks.Sort(System.StringComparer.Ordinal);
            foreach (string id in unlocks) Line(builder, "unlock", id);

            if (graph != null && !string.IsNullOrEmpty(progress.AccountId))
            {
                WriteSorted(builder, "friend", graph.FriendsOf(progress.AccountId));
                WriteSorted(builder, "block", graph.BlockedBy(progress.AccountId));
                WriteSorted(builder, "outgoing", graph.OutgoingRequestsOf(progress.AccountId));
            }
            return builder.ToString();
        }

        private static void WriteSorted(StringBuilder builder, string key,
                                        IReadOnlyCollection<string> values)
        {
            var sorted = new List<string>(values);
            sorted.Sort(System.StringComparer.Ordinal);
            foreach (string value in sorted) Line(builder, key, value);
        }

        private static void Line(StringBuilder builder, string key, string value) =>
            builder.Append(key).Append(' ').Append(Escape(value)).Append('\n');

        private static void Line(StringBuilder builder, string key, long value) =>
            builder.Append(key).Append(' ')
                   .Append(value.ToString(CultureInfo.InvariantCulture)).Append('\n');

        /// <summary>
        /// Makes a value safe to sit in a space-separated line.
        /// </summary>
        /// <remarks>
        /// Account ids are ours and contain no spaces, but a save format that only works for
        /// well-behaved input is a save format that breaks the first time somebody's id comes
        /// from a platform that allows more than we expected.
        /// </remarks>
        private static string Escape(string value)
        {
            if (string.IsNullOrEmpty(value)) return "-";
            return value.Replace("\\", "\\\\").Replace(" ", "\\s")
                        .Replace("\n", "\\n").Replace("\r", "");
        }

        private static string Unescape(string value)
        {
            if (value == "-") return "";
            var builder = new StringBuilder(value.Length);
            for (int i = 0; i < value.Length; i++)
            {
                if (value[i] != '\\' || i + 1 >= value.Length) { builder.Append(value[i]); continue; }
                i++;
                builder.Append(value[i] switch { 's' => ' ', 'n' => '\n', _ => value[i] });
            }
            return builder.ToString();
        }

        // ---- reading ---------------------------------------------------------------------

        /// <summary>
        /// Reads into <paramref name="progress"/>, and into <paramref name="graph"/> if given.
        /// </summary>
        /// <remarks>
        /// The target is only mutated once the header has been accepted, so a refused or corrupt
        /// save leaves the caller's existing state untouched rather than half-overwritten.
        /// </remarks>
        public static SaveReadResult Read(string text, PlayerProgress progress,
                                          SocialGraph graph = null)
        {
            if (progress == null) throw new System.ArgumentNullException(nameof(progress));
            if (string.IsNullOrEmpty(text))
                return new SaveReadResult { Status = SaveReadStatus.Empty };

            string[] lines = text.Replace("\r\n", "\n").Split('\n');
            string[] header = lines[0].Split(' ');
            if (header.Length < 2 || header[0] != Magic)
                return Fail($"not a Salvo save: first line was '{lines[0]}'");
            if (!int.TryParse(header[1], NumberStyles.Integer, CultureInfo.InvariantCulture,
                              out int version))
                return Fail($"unreadable version '{header[1]}'");
            if (version < 1)
                return Fail($"version {version} is not a version");

            if (version > CurrentVersion)
            {
                // Refused, not partially read. See the note on the class.
                return new SaveReadResult
                {
                    Status = SaveReadStatus.TooNew,
                    Detail = $"save is version {version}; this build understands up to "
                             + $"{CurrentVersion}. Refusing rather than dropping what it added.",
                };
            }

            var staging = new PlayerProgress();
            var friends = new List<string>();
            var blocks = new List<string>();
            var outgoing = new List<string>();

            for (int i = 1; i < lines.Length; i++)
            {
                string line = lines[i].Trim();
                if (line.Length == 0 || line[0] == '#') continue;

                string[] parts = line.Split(' ');
                string key = parts[0];
                string first = parts.Length > 1 ? Unescape(parts[1]) : "";

                switch (key)
                {
                    case "account": staging.AccountId = first; break;
                    case "xp": staging.TotalXp = ParseLong(parts, 1); break;

                    case "career.matches": staging.Career.MatchesPlayed = (int)ParseLong(parts, 1); break;
                    case "career.wins": staging.Career.MatchesWon = (int)ParseLong(parts, 1); break;
                    case "career.kills": staging.Career.Kills = (int)ParseLong(parts, 1); break;
                    case "career.deaths": staging.Career.Deaths = (int)ParseLong(parts, 1); break;
                    case "career.assists": staging.Career.Assists = (int)ParseLong(parts, 1); break;
                    case "career.headshots": staging.Career.Headshots = (int)ParseLong(parts, 1); break;
                    case "career.objectives":
                        staging.Career.ObjectivesCompleted = (int)ParseLong(parts, 1); break;
                    case "career.damage": staging.Career.DamageDealt = ParseLong(parts, 1); break;
                    case "career.seconds": staging.Career.SecondsPlayed = ParseLong(parts, 1); break;
                    case "career.beststreak":
                        staging.Career.BestKillStreak = (int)ParseLong(parts, 1); break;

                    case "weapon":
                        if (parts.Length < 7) return Fail($"line {i + 1}: truncated weapon record");
                        staging.RecordWeapon(first, _ => new WeaponStats
                        {
                            Kills = (int)ParseLong(parts, 2),
                            Headshots = (int)ParseLong(parts, 3),
                            DamageDealt = ParseLong(parts, 4),
                            ShotsFired = (int)ParseLong(parts, 5),
                            ShotsHit = (int)ParseLong(parts, 6),
                        });
                        break;

                    case "unlock": staging.GrantDirect(first); break;
                    case "friend": friends.Add(first); break;
                    case "block": blocks.Add(first); break;
                    case "outgoing": outgoing.Add(first); break;

                    // An unrecognised key inside a version we do understand is a
                    // forward-compatible addition. Skipping it is what keeps an additive change
                    // from being a breaking one.
                    default: break;
                }
            }

            Migrations.Apply(version, staging);
            progress.CopyFrom(staging);

            if (graph != null && !string.IsNullOrEmpty(staging.AccountId))
            {
                // Blocks first. If a save somehow lists the same account as both friend and
                // blocked, the block must win — it is the safety-relevant one, and applying them
                // in the other order would leave a friendship a block was meant to have severed.
                foreach (string id in blocks) graph.Block(staging.AccountId, id);
                foreach (string id in friends) graph.RestoreFriendship(staging.AccountId, id);
                foreach (string id in outgoing) graph.SendRequest(staging.AccountId, id);
            }

            return new SaveReadResult { Status = SaveReadStatus.Ok };
        }

        private static SaveReadResult Fail(string detail) =>
            new SaveReadResult { Status = SaveReadStatus.Corrupt, Detail = detail };

        private static long ParseLong(string[] parts, int index)
        {
            if (index >= parts.Length) return 0;
            return long.TryParse(parts[index], NumberStyles.Integer, CultureInfo.InvariantCulture,
                                 out long value) ? value : 0;
        }
    }

    /// <summary>
    /// Brings an older save up to the current schema.
    /// </summary>
    /// <remarks>
    /// Each step is a separate, named method applied in order, rather than one function that
    /// knows every version. Migrations are written years apart by people who were not there for
    /// the previous one, and the only thing that makes that survivable is that each step does
    /// one thing and says which version it came from.
    ///
    /// <para>Migrations must never fail. A save that cannot be migrated is an account that
    /// cannot be loaded, which is the outcome all of this exists to avoid — so a step that
    /// cannot work out what to do leaves the field at its default rather than throwing.</para>
    /// </remarks>
    public static class Migrations
    {
        public static void Apply(int fromVersion, PlayerProgress progress)
        {
            if (fromVersion < 2) FromV1ToV2(progress);
        }

        /// <summary>
        /// v1 counted shots in trigger pulls; v2 counts them in projectiles.
        /// </summary>
        /// <remarks>
        /// The shotgun accuracy bug. A v1 save can hold more hits than shots, which decodes to an
        /// accuracy above 100%. The pellet count per weapon is not recoverable from the save —
        /// it was never written — so the honest repair is to raise the fired count to at least
        /// the hit count, which makes the figure sane without inventing a history that did not
        /// happen. Nobody's kills or damage are touched.
        /// </remarks>
        private static void FromV1ToV2(PlayerProgress progress)
        {
            foreach (string id in new List<string>(progress.WeaponIds))
            {
                progress.RecordWeapon(id, stats =>
                {
                    if (stats.ShotsHit > stats.ShotsFired) stats.ShotsFired = stats.ShotsHit;
                    return stats;
                });
            }
        }
    }
}
