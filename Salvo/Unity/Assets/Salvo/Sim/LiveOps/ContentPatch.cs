using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>
    /// Content added or changed after the client shipped.
    /// </summary>
    /// <remarks>
    /// The mechanical half of live content: a season adds weapons, maps and modes, and players
    /// receive them without a store update. A patch is applied over a base catalogue to produce
    /// a new one; it never mutates the base, so the original is still there to diff against, to
    /// roll back to, and to serve to clients that have not taken the patch yet.
    ///
    /// <para><b>A patch can add and it can replace; it cannot remove.</b> That is a deliberate
    /// restriction rather than an omission. Removing a weapon mid-season breaks every saved
    /// loadout referencing it, every match replay, and every player's statistics page — and it
    /// does so on the server, where the player cannot see why their gun vanished. Retiring
    /// content properly means leaving the definition in place and taking it out of the pools
    /// that let it be chosen, which a replace does perfectly well.</para>
    ///
    /// <para>What this deliberately does not do is ship <em>code</em>. A patch is data.
    /// A new game mode's rules are an <see cref="IGameMode"/> implementation and need a client
    /// update; a new weapon, map, attachment or balance number does not. That line is where it
    /// is because moving it means shipping executable content to a phone, which is both an
    /// App Store problem and a security one.</para>
    /// </remarks>
    public sealed class ContentPatch
    {
        public string Version = "0.0.0";
        public readonly List<WeaponDefinition> Weapons = new List<WeaponDefinition>();
        public readonly List<AttachmentDefinition> Attachments = new List<AttachmentDefinition>();
        public readonly List<MapDefinition> Maps = new List<MapDefinition>();
        public readonly List<GameModeDefinition> GameModes = new List<GameModeDefinition>();
        public readonly List<FactionDefinition> Factions = new List<FactionDefinition>();
        public readonly List<CharacterDefinition> Characters = new List<CharacterDefinition>();
        public readonly List<WorldDefinition> Worlds = new List<WorldDefinition>();

        public bool IsEmpty =>
            Weapons.Count == 0 && Attachments.Count == 0 && Maps.Count == 0
            && GameModes.Count == 0 && Factions.Count == 0 && Characters.Count == 0
            && Worlds.Count == 0;

        /// <summary>
        /// Produces a new catalogue with this patch applied. The input is untouched.
        /// </summary>
        public GameContent ApplyTo(GameContent baseContent)
        {
            if (baseContent == null) throw new System.ArgumentNullException(nameof(baseContent));

            return new GameContent(
                Merge(baseContent.Weapons, Weapons, w => w.Id),
                Merge(baseContent.Attachments, Attachments, a => a.Id),
                Merge(baseContent.Characters, Characters, c => c.Id),
                Merge(baseContent.Factions, Factions, f => f.Id),
                Merge(baseContent.Maps, Maps, m => m.Id),
                Merge(baseContent.Worlds, Worlds, w => w.Id),
                Merge(baseContent.GameModes, GameModes, g => g.Id),
                // Bot difficulties are rules rather than content, and a patch has no business
                // changing how hard the bots are without a build anyone reviewed.
                CopyOf(baseContent.BotDifficulties, d => d.Id));
        }

        private static InMemoryCatalog<T> Merge<T>(IContentCatalog<T> baseCatalog,
                                                   List<T> overrides,
                                                   System.Func<T, ContentId> idOf) where T : class
        {
            var merged = new InMemoryCatalog<T>();
            var replaced = new HashSet<string>();
            for (int i = 0; i < overrides.Count; i++) replaced.Add(idOf(overrides[i]).ToString());

            foreach (T item in baseCatalog.All)
            {
                // Anything the patch replaces is skipped here and added below, so the patched
                // version wins and the base ordering is otherwise preserved.
                if (replaced.Contains(idOf(item).ToString())) continue;
                merged.Add(idOf(item), item);
            }
            for (int i = 0; i < overrides.Count; i++) merged.Add(idOf(overrides[i]), overrides[i]);
            return merged;
        }

        private static InMemoryCatalog<T> CopyOf<T>(IContentCatalog<T> source,
                                                    System.Func<T, ContentId> idOf) where T : class
        {
            var copy = new InMemoryCatalog<T>();
            foreach (T item in source.All) copy.Add(idOf(item), item);
            return copy;
        }

        /// <summary>
        /// Checks a patch before it is applied anywhere.
        /// </summary>
        /// <remarks>
        /// Run against the <em>result</em>, not the patch in isolation, because the interesting
        /// failures are relational: a new attachment naming a weapon that does not exist, a mode
        /// added without a map that supports it, a replacement weapon that is now strictly
        /// better than everything else. A patch that validates alone and breaks the catalogue it
        /// lands on is exactly the outage this is meant to prevent.
        /// </remarks>
        public List<string> ValidateAgainst(GameContent baseContent)
        {
            var problems = new List<string>();
            if (IsEmpty)
            {
                problems.Add("the patch is empty");
                return problems;
            }

            GameContent result;
            try
            {
                result = ApplyTo(baseContent);
            }
            catch (System.Exception error)
            {
                problems.Add($"the patch could not be applied: {error.Message}");
                return problems;
            }

            problems.AddRange(result.Validate());

            // A patch that adds a mode nothing can run is a menu entry that fails when clicked.
            foreach (GameModeDefinition mode in GameModes)
            {
                if (!Salvo.Sim.GameModes.IsImplemented(mode.Kind))
                    problems.Add($"{mode.Id}: kind {mode.Kind} has no implementation in this "
                                 + "build — a patch ships data, not code, so this mode would "
                                 + "appear in the menu and fail when chosen");
            }
            return problems;
        }
    }
}
