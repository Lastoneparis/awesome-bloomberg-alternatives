using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>What a player has done across every match they have played.</summary>
    public struct CareerStats
    {
        public int MatchesPlayed;
        public int MatchesWon;
        public int Kills;
        public int Deaths;
        public int Assists;
        public int Headshots;
        public int ObjectivesCompleted;
        public long DamageDealt;
        public long SecondsPlayed;
        public int BestKillStreak;

        public float KillDeathRatio => Deaths == 0 ? Kills : (float)Kills / Deaths;
        public float WinRate => MatchesPlayed == 0 ? 0f : (float)MatchesWon / MatchesPlayed;
        public float HeadshotRate => Kills == 0 ? 0f : (float)Headshots / Kills;
    }

    /// <summary>Per-weapon usage, so a player can see what they actually play.</summary>
    /// <summary>
    /// Per-weapon usage, so a player can see what they actually play.
    /// </summary>
    /// <remarks>
    /// <see cref="ShotsFired"/> and <see cref="ShotsHit"/> are counted in <em>projectiles</em>,
    /// not trigger pulls, so that accuracy means the same thing for a rifle firing one round and
    /// a shotgun firing eight.
    /// </remarks>
    public struct WeaponStats
    {
        public int Kills;
        public int Headshots;
        public long DamageDealt;
        /// <summary>Projectiles sent, summed over shots.</summary>
        public int ShotsFired;
        /// <summary>Projectiles that struck a player.</summary>
        public int ShotsHit;

        public float Accuracy =>
            ShotsFired == 0 ? 0f : SalvoMath.Clamp01((float)ShotsHit / ShotsFired);
    }

    /// <summary>
    /// A player's account-level progress.
    /// </summary>
    /// <remarks>
    /// Server-owned, like everything else that a player would benefit from editing. It is
    /// deliberately not part of <see cref="PlayerRuntime"/>: a match does not need to know a
    /// player's career, and keeping them apart means a match cannot accidentally write to it
    /// mid-round.
    /// </remarks>
    public sealed class PlayerProgress
    {
        public string AccountId = "";
        public long TotalXp;
        public CareerStats Career;

        private readonly Dictionary<string, WeaponStats> _weapons = new Dictionary<string, WeaponStats>();
        private readonly HashSet<string> _unlocked = new HashSet<string>();

        public int Level => XpCurve.LevelForTotalXp(TotalXp);
        public float LevelProgress => XpCurve.ProgressThroughLevel(TotalXp);
        public IReadOnlyCollection<string> Unlocked => _unlocked;

        public WeaponStats StatsFor(ContentId weapon) =>
            _weapons.TryGetValue(weapon.ToString(), out WeaponStats stats) ? stats : default;

        /// <summary>Every weapon this account has a record for. For saving and for a stats screen.</summary>
        public IReadOnlyCollection<string> WeaponIds => _weapons.Keys;

        /// <summary>
        /// Marks something unlocked without consulting a level.
        /// </summary>
        /// <remarks>
        /// For loading a save, and for nothing else. An unlock a player already earned must
        /// survive a change to the unlock table — if the level for an item is raised, someone who
        /// had it does not lose it. That is why the saved set is authoritative on load rather
        /// than being recomputed from the level.
        /// </remarks>
        public void GrantDirect(ContentId id)
        {
            if (!id.IsEmpty) _unlocked.Add(id.ToString());
        }

        /// <summary>
        /// Replaces this record's contents with another's.
        /// </summary>
        /// <remarks>
        /// Loading stages into a fresh instance and copies across only once the whole save has
        /// parsed, so a save that turns out to be corrupt halfway through leaves the live record
        /// untouched instead of half-overwritten.
        /// </remarks>
        public void CopyFrom(PlayerProgress other)
        {
            if (other == null) return;
            AccountId = other.AccountId;
            TotalXp = other.TotalXp;
            Career = other.Career;

            _weapons.Clear();
            foreach (KeyValuePair<string, WeaponStats> entry in other._weapons)
                _weapons[entry.Key] = entry.Value;

            _unlocked.Clear();
            foreach (string id in other._unlocked) _unlocked.Add(id);
        }

        public void RecordWeapon(ContentId weapon, System.Func<WeaponStats, WeaponStats> update)
        {
            string key = weapon.ToString();
            _weapons.TryGetValue(key, out WeaponStats stats);
            _weapons[key] = update(stats);
        }

        public bool HasUnlocked(ContentId id) => _unlocked.Contains(id.ToString());

        /// <summary>
        /// Grants everything the player's level entitles them to. Idempotent, and it recomputes
        /// from the level rather than tracking deltas — so a player whose account was restored
        /// from an old backup, or who was granted experience out of band, ends up with exactly
        /// the unlocks their level says, not a set that depends on the order things happened in.
        /// </summary>
        public IReadOnlyList<UnlockEntry> GrantUnlocksFor(UnlockTable table)
        {
            var newlyGranted = new List<UnlockEntry>();
            int level = Level;
            foreach (UnlockEntry entry in table.Entries)
            {
                if (entry.Level > level) continue;
                if (_unlocked.Add(entry.Id.ToString())) newlyGranted.Add(entry);
            }
            return newlyGranted;
        }

        /// <summary>Folds one finished match into the career record.</summary>
        public void Apply(MatchRewards rewards)
        {
            TotalXp += rewards.TotalXp;
            Career.MatchesPlayed++;
            if (rewards.Won) Career.MatchesWon++;
            Career.Kills += rewards.Kills;
            Career.Deaths += rewards.Deaths;
            Career.Assists += rewards.Assists;
            Career.Headshots += rewards.Headshots;
            Career.ObjectivesCompleted += rewards.ObjectiveActions;
            Career.DamageDealt += (long)rewards.DamageDealt;
            Career.SecondsPlayed += rewards.SecondsPlayed;
            if (rewards.BestStreak > Career.BestKillStreak) Career.BestKillStreak = rewards.BestStreak;
        }
    }
}
