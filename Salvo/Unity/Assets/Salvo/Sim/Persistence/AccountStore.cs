using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>Where accounts are kept.</summary>
    /// <remarks>
    /// An interface because the answer differs by deployment: a dedicated server writes to a
    /// database, a single-player build writes to a file, and a test writes to memory. The rules
    /// about atomicity and corruption recovery belong to each implementation, but the contract —
    /// that loading a missing account is not an error, and that a failed save says so — is shared.
    /// </remarks>
    public interface IAccountStore
    {
        /// <summary>Loads into <paramref name="progress"/>. A missing account returns
        /// <see cref="SaveReadStatus.Empty"/>, which is a new player rather than a failure.</summary>
        SaveReadResult Load(string accountId, PlayerProgress progress, SocialGraph graph = null);

        /// <summary>Saves, atomically. Returns false if the account was not durably written.</summary>
        bool Save(PlayerProgress progress, SocialGraph graph = null);

        bool Exists(string accountId);

        /// <summary>Erases an account. Account deletion is a store requirement, so it is part of
        /// the contract rather than something each store improvises.</summary>
        bool Delete(string accountId);
    }

    /// <summary>An in-memory store. For tests, and for a server that keeps accounts elsewhere.</summary>
    public sealed class InMemoryAccountStore : IAccountStore
    {
        private readonly Dictionary<string, string> _saves = new Dictionary<string, string>();

        public int Count => _saves.Count;
        /// <summary>The raw saved text, for a test that wants to corrupt or inspect it.</summary>
        public string RawSave(string accountId) =>
            _saves.TryGetValue(accountId, out string text) ? text : null;
        public void SetRawSave(string accountId, string text) => _saves[accountId] = text;

        public SaveReadResult Load(string accountId, PlayerProgress progress, SocialGraph graph = null)
        {
            if (!_saves.TryGetValue(accountId, out string text))
                return new SaveReadResult { Status = SaveReadStatus.Empty };
            return SaveFormat.Read(text, progress, graph);
        }

        public bool Save(PlayerProgress progress, SocialGraph graph = null)
        {
            if (progress == null || string.IsNullOrEmpty(progress.AccountId)) return false;
            _saves[progress.AccountId] = SaveFormat.Write(progress, graph);
            return true;
        }

        public bool Exists(string accountId) => _saves.ContainsKey(accountId);
        public bool Delete(string accountId) => _saves.Remove(accountId);
    }

    /// <summary>
    /// Accounts as files on disk.
    /// </summary>
    /// <remarks>
    /// Two things here are not optional, and both exist because the failure they prevent costs a
    /// player everything they have earned.
    ///
    /// <para><b>Writes are atomic.</b> Saving writes a temporary file, flushes it, and then
    /// renames it over the target — a rename within a directory is atomic on every filesystem
    /// this will run on. Writing directly into the live file means a crash, a battery dying or a
    /// process kill partway through leaves a half-written save, and the player's account is gone.
    /// Games are killed by the operating system routinely; this is a normal event, not an
    /// exotic one.</para>
    ///
    /// <para><b>The previous save is kept.</b> Before a rename the existing file is moved aside
    /// as a backup, so a save that is somehow corrupt still has an intact predecessor to fall
    /// back to. <see cref="Load"/> does that automatically and reports it, because the
    /// alternative — showing a level-one account to someone who was level forty — is the worst
    /// outcome available and the one a player will never forgive.</para>
    /// </remarks>
    public sealed class FileAccountStore : IAccountStore
    {
        private readonly string _directory;

        /// <summary>Set when a load fell back to a backup. Worth logging loudly: it means a save
        /// was lost, even though the player did not notice.</summary>
        public int BackupRecoveries { get; private set; }
        public int FailedSaves { get; private set; }

        public FileAccountStore(string directory)
        {
            _directory = directory ?? throw new System.ArgumentNullException(nameof(directory));
            System.IO.Directory.CreateDirectory(_directory);
        }

        private string PathFor(string accountId) =>
            System.IO.Path.Combine(_directory, SafeName(accountId) + ".sav");
        private string BackupFor(string accountId) => PathFor(accountId) + ".bak";
        private string TempFor(string accountId) => PathFor(accountId) + ".tmp";

        /// <summary>
        /// Turns an account id into something safe to use as a filename.
        /// </summary>
        /// <remarks>
        /// An id is not necessarily a filename. One containing a path separator would write
        /// outside the save directory, which is a directory-traversal bug in the most
        /// security-sensitive file the game owns. Anything outside a conservative set becomes an
        /// underscore plus a hash, so distinct ids never collide after sanitising.
        /// </remarks>
        private static string SafeName(string accountId)
        {
            if (string.IsNullOrEmpty(accountId)) return "_empty";

            var builder = new System.Text.StringBuilder(accountId.Length);
            bool changed = false;
            foreach (char c in accountId)
            {
                bool safe = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
                            || (c >= '0' && c <= '9') || c == '.' || c == '-' || c == '_';
                if (safe) builder.Append(c);
                else { builder.Append('_'); changed = true; }
            }
            if (!changed) return builder.ToString();

            // Distinct ids must not collide once sanitised, or two players share a save.
            uint hash = 2166136261u;
            foreach (char c in accountId) { hash ^= c; hash *= 16777619u; }
            return builder.Append('-').Append(hash.ToString("x8")).ToString();
        }

        public SaveReadResult Load(string accountId, PlayerProgress progress, SocialGraph graph = null)
        {
            string path = PathFor(accountId);
            if (!System.IO.File.Exists(path))
            {
                // No primary, but perhaps an interrupted save left a backup behind.
                if (System.IO.File.Exists(BackupFor(accountId)))
                    return LoadFrom(BackupFor(accountId), progress, graph, isBackup: true);
                return new SaveReadResult { Status = SaveReadStatus.Empty };
            }

            SaveReadResult result = LoadFrom(path, progress, graph, isBackup: false);
            if (result.Status != SaveReadStatus.Corrupt) return result;

            // Corrupt primary. A backup that loads is far better than an empty account, and the
            // player losing one match of progress beats losing all of it.
            if (!System.IO.File.Exists(BackupFor(accountId))) return result;

            SaveReadResult fallback = LoadFrom(BackupFor(accountId), progress, graph, isBackup: true);
            if (!fallback.Ok) return result;

            BackupRecoveries++;
            return new SaveReadResult
            {
                Status = SaveReadStatus.Ok,
                Detail = $"primary save was unreadable ({result.Detail}); recovered from backup",
            };
        }

        private static SaveReadResult LoadFrom(string path, PlayerProgress progress,
                                               SocialGraph graph, bool isBackup)
        {
            try
            {
                return SaveFormat.Read(System.IO.File.ReadAllText(path), progress, graph);
            }
            catch (System.Exception error)
            {
                return new SaveReadResult
                {
                    Status = SaveReadStatus.Corrupt,
                    Detail = $"could not read {(isBackup ? "backup" : "save")}: {error.Message}",
                };
            }
        }

        public bool Save(PlayerProgress progress, SocialGraph graph = null)
        {
            if (progress == null || string.IsNullOrEmpty(progress.AccountId)) return false;

            string path = PathFor(progress.AccountId);
            string temp = TempFor(progress.AccountId);
            string backup = BackupFor(progress.AccountId);

            try
            {
                string text = SaveFormat.Write(progress, graph);

                // Flushed to disk before the rename. Without the flush the rename can land while
                // the contents are still in a buffer, and a power loss then leaves a correctly
                // named file full of nothing — which is worse than a half-written one, because
                // it looks intact.
                using (var stream = new System.IO.FileStream(temp, System.IO.FileMode.Create,
                                                             System.IO.FileAccess.Write))
                using (var writer = new System.IO.StreamWriter(stream))
                {
                    writer.Write(text);
                    writer.Flush();
                    stream.Flush(flushToDisk: true);
                }

                if (System.IO.File.Exists(path))
                {
                    if (System.IO.File.Exists(backup)) System.IO.File.Delete(backup);
                    System.IO.File.Move(path, backup);
                }
                System.IO.File.Move(temp, path);
                return true;
            }
            catch (System.Exception)
            {
                FailedSaves++;
                try { if (System.IO.File.Exists(temp)) System.IO.File.Delete(temp); }
                catch (System.Exception) { /* the temp file is litter, not a failure */ }
                return false;
            }
        }

        public bool Exists(string accountId) =>
            System.IO.File.Exists(PathFor(accountId)) || System.IO.File.Exists(BackupFor(accountId));

        public bool Delete(string accountId)
        {
            bool deleted = false;
            // Every copy, including the backup. A deletion that leaves a recoverable backup is
            // not a deletion.
            foreach (string path in new[] { PathFor(accountId), BackupFor(accountId),
                                            TempFor(accountId) })
            {
                try
                {
                    if (!System.IO.File.Exists(path)) continue;
                    System.IO.File.Delete(path);
                    deleted = true;
                }
                catch (System.Exception) { return false; }
            }
            return deleted;
        }
    }
}
