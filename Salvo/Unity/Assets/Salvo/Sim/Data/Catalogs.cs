using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>
    /// Read-only access to one kind of content.
    /// </summary>
    /// <remarks>
    /// An interface rather than a static table, so the same simulation runs against
    /// ScriptableObjects in the Editor, JSON on a dedicated server, a remote Addressables
    /// manifest in a live build, and a three-item fixture in a unit test. The simulation
    /// never learns which it got.
    /// </remarks>
    public interface IContentCatalog<T> where T : class
    {
        T Get(ContentId id);
        bool TryGet(ContentId id, out T value);
        IReadOnlyList<T> All { get; }
        bool Contains(ContentId id);
    }

    /// <summary>Every catalog the simulation needs, passed as one object so adding a
    /// content type does not change every signature that touches content.</summary>
    public sealed class GameContent
    {
        public IContentCatalog<WeaponDefinition> Weapons { get; }
        public IContentCatalog<AttachmentDefinition> Attachments { get; }
        public IContentCatalog<CharacterDefinition> Characters { get; }
        public IContentCatalog<FactionDefinition> Factions { get; }
        public IContentCatalog<MapDefinition> Maps { get; }
        public IContentCatalog<WorldDefinition> Worlds { get; }
        public IContentCatalog<GameModeDefinition> GameModes { get; }
        public IContentCatalog<BotDifficultyDefinition> BotDifficulties { get; }

        public GameContent(
            IContentCatalog<WeaponDefinition> weapons,
            IContentCatalog<AttachmentDefinition> attachments,
            IContentCatalog<CharacterDefinition> characters,
            IContentCatalog<FactionDefinition> factions,
            IContentCatalog<MapDefinition> maps,
            IContentCatalog<WorldDefinition> worlds,
            IContentCatalog<GameModeDefinition> gameModes,
            IContentCatalog<BotDifficultyDefinition> botDifficulties)
        {
            Weapons = weapons;
            Attachments = attachments;
            Characters = characters;
            Factions = factions;
            Maps = maps;
            Worlds = worlds;
            GameModes = gameModes;
            BotDifficulties = botDifficulties;
        }

        /// <summary>
        /// Every way the loaded content is internally inconsistent.
        /// </summary>
        /// <remarks>
        /// Cross-references are checked here rather than inside each definition, because a
        /// weapon cannot know whether its world exists. Run at load: content authored by
        /// hand is wrong sometimes, and a dangling id should be a startup error naming the
        /// field, not a null reference thirty seconds into a match.
        /// </remarks>
        public List<string> Validate()
        {
            var problems = new List<string>();

            foreach (WeaponDefinition weapon in Weapons.All) weapon.Validate(problems);
            foreach (AttachmentDefinition attachment in Attachments.All) attachment.Validate(problems);
            foreach (CharacterDefinition character in Characters.All) character.Validate(problems);
            foreach (FactionDefinition faction in Factions.All) faction.Validate(problems);
            foreach (MapDefinition map in Maps.All) map.Validate(problems);
            foreach (WorldDefinition world in Worlds.All) world.Validate(problems);
            foreach (GameModeDefinition mode in GameModes.All) mode.Validate(problems);
            foreach (BotDifficultyDefinition bot in BotDifficulties.All) bot.Validate(problems);

            foreach (WorldDefinition world in Worlds.All)
            {
                foreach (ContentId weaponId in world.WeaponPool)
                    if (!Weapons.Contains(weaponId))
                        problems.Add($"world {world.Id}: weapon pool references missing weapon '{weaponId}'");
                foreach (ContentId factionId in world.Factions)
                    if (!Factions.Contains(factionId))
                        problems.Add($"world {world.Id}: references missing faction '{factionId}'");
                foreach (ContentId mapId in world.Maps)
                    if (!Maps.Contains(mapId))
                        problems.Add($"world {world.Id}: references missing map '{mapId}'");
            }

            foreach (MapDefinition map in Maps.All)
                if (!map.WorldId.IsEmpty && !Worlds.Contains(map.WorldId))
                    problems.Add($"map {map.Id}: belongs to missing world '{map.WorldId}'");

            foreach (WeaponDefinition weapon in Weapons.All)
                if (!weapon.WorldId.IsEmpty && !Worlds.Contains(weapon.WorldId))
                    problems.Add($"weapon {weapon.Id}: belongs to missing world '{weapon.WorldId}'");

            foreach (FactionDefinition faction in Factions.All)
                foreach (ContentId characterId in faction.Characters)
                    if (!Characters.Contains(characterId))
                        problems.Add($"faction {faction.Id}: references missing character '{characterId}'");

            return problems;
        }
    }

    /// <summary>A catalog backed by a dictionary. What the JSON loader, the Unity loader
    /// and the tests all end up producing.</summary>
    public sealed class InMemoryCatalog<T> : IContentCatalog<T> where T : class
    {
        private readonly Dictionary<ContentId, T> _byId = new Dictionary<ContentId, T>();
        private readonly List<T> _ordered = new List<T>();

        public InMemoryCatalog() { }

        public InMemoryCatalog(IEnumerable<T> items, System.Func<T, ContentId> idOf)
        {
            foreach (T item in items) Add(idOf(item), item);
        }

        public void Add(ContentId id, T item)
        {
            if (id.IsEmpty)
                throw new System.ArgumentException("content needs a non-empty id", nameof(id));
            if (_byId.ContainsKey(id))
                throw new System.ArgumentException($"duplicate content id '{id}'", nameof(id));
            _byId.Add(id, item);
            _ordered.Add(item);
        }

        public T Get(ContentId id) =>
            _byId.TryGetValue(id, out T value) ? value : null;

        public bool TryGet(ContentId id, out T value) => _byId.TryGetValue(id, out value);

        public bool Contains(ContentId id) => _byId.ContainsKey(id);

        public IReadOnlyList<T> All => _ordered;
    }
}
