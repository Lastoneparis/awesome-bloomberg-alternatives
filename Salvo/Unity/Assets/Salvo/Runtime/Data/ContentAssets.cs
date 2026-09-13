using System.Collections.Generic;
using UnityEngine;
using Salvo.Sim;

namespace Salvo.Runtime
{
    /// <summary>
    /// A <see cref="ScriptableObject"/> that carries one plain-C# definition.
    /// </summary>
    /// <remarks>
    /// The wrapper holds the simulation's own type as a serialized field rather than
    /// re-declaring its fields. That is the whole trick, and it is what stops the two from
    /// drifting: there is one definition of what a weapon is, and the editor asset is a
    /// container for it, not a parallel copy that someone has to remember to keep in step.
    ///
    /// <para>A dedicated server reads the same definitions from JSON and never loads a
    /// ScriptableObject at all. Both paths deserialise into the same type, so a weapon cannot
    /// behave differently on the server than it does in the editor.</para>
    /// </remarks>
    public abstract class DefinitionAsset<T> : ScriptableObject where T : class
    {
        [SerializeField] private T definition;

        public T Definition => definition;

        /// <summary>
        /// Problems with this asset, for the editor to show. Delegates to the simulation's own
        /// validation so the editor cannot disagree with the server about what is valid.
        /// </summary>
        public abstract List<string> Validate();
    }

    [CreateAssetMenu(menuName = "Salvo/Weapon", fileName = "wpn_new")]
    public sealed class WeaponAsset : DefinitionAsset<WeaponDefinition>
    {
        public override List<string> Validate()
        {
            var problems = new List<string>();
            if (Definition == null) problems.Add("asset has no definition");
            else Definition.Validate(problems);
            return problems;
        }
    }

    [CreateAssetMenu(menuName = "Salvo/Attachment", fileName = "att_new")]
    public sealed class AttachmentAsset : DefinitionAsset<AttachmentDefinition>
    {
        public override List<string> Validate()
        {
            var problems = new List<string>();
            if (Definition == null) problems.Add("asset has no definition");
            else Definition.Validate(problems);
            return problems;
        }
    }

    [CreateAssetMenu(menuName = "Salvo/Character", fileName = "char_new")]
    public sealed class CharacterAsset : DefinitionAsset<CharacterDefinition>
    {
        public override List<string> Validate()
        {
            var problems = new List<string>();
            if (Definition == null) problems.Add("asset has no definition");
            else Definition.Validate(problems);
            return problems;
        }
    }

    [CreateAssetMenu(menuName = "Salvo/Faction", fileName = "faction_new")]
    public sealed class FactionAsset : DefinitionAsset<FactionDefinition>
    {
        public override List<string> Validate()
        {
            var problems = new List<string>();
            if (Definition == null) problems.Add("asset has no definition");
            else Definition.Validate(problems);
            return problems;
        }
    }

    [CreateAssetMenu(menuName = "Salvo/World", fileName = "world_new")]
    public sealed class WorldAsset : DefinitionAsset<WorldDefinition>
    {
        public override List<string> Validate()
        {
            var problems = new List<string>();
            if (Definition == null) problems.Add("asset has no definition");
            else Definition.Validate(problems);
            return problems;
        }
    }

    [CreateAssetMenu(menuName = "Salvo/Map", fileName = "map_new")]
    public sealed class MapAsset : DefinitionAsset<MapDefinition>
    {
        public override List<string> Validate()
        {
            var problems = new List<string>();
            if (Definition == null) problems.Add("asset has no definition");
            else Definition.Validate(problems);
            return problems;
        }
    }

    [CreateAssetMenu(menuName = "Salvo/Game Mode", fileName = "mode_new")]
    public sealed class GameModeAsset : DefinitionAsset<GameModeDefinition>
    {
        public override List<string> Validate()
        {
            var problems = new List<string>();
            if (Definition == null) problems.Add("asset has no definition");
            else Definition.Validate(problems);
            return problems;
        }
    }

    [CreateAssetMenu(menuName = "Salvo/Bot Difficulty", fileName = "bot_new")]
    public sealed class BotDifficultyAsset : DefinitionAsset<BotDifficultyDefinition>
    {
        public override List<string> Validate()
        {
            var problems = new List<string>();
            if (Definition == null) problems.Add("asset has no definition");
            else Definition.Validate(problems);
            return problems;
        }
    }

    /// <summary>
    /// Every asset that makes up a build's content, gathered into one object.
    /// </summary>
    /// <remarks>
    /// A single catalogue asset rather than a folder scan. Scanning is convenient and wrong:
    /// what is in a build would then depend on what happens to be on disk, so a half-finished
    /// weapon left in the project would ship. An explicit list means adding content is a
    /// deliberate act that shows up in a diff.
    /// </remarks>
    [CreateAssetMenu(menuName = "Salvo/Content Catalogue", fileName = "salvo_content")]
    public sealed class ContentCatalogueAsset : ScriptableObject
    {
        [SerializeField] private List<WeaponAsset> weapons = new List<WeaponAsset>();
        [SerializeField] private List<AttachmentAsset> attachments = new List<AttachmentAsset>();
        [SerializeField] private List<CharacterAsset> characters = new List<CharacterAsset>();
        [SerializeField] private List<FactionAsset> factions = new List<FactionAsset>();
        [SerializeField] private List<MapAsset> maps = new List<MapAsset>();
        [SerializeField] private List<WorldAsset> worlds = new List<WorldAsset>();
        [SerializeField] private List<GameModeAsset> gameModes = new List<GameModeAsset>();
        [SerializeField] private List<BotDifficultyAsset> botDifficulties =
            new List<BotDifficultyAsset>();

        /// <summary>
        /// Builds the engine-free <see cref="GameContent"/> the simulation runs on.
        /// </summary>
        public GameContent Build()
        {
            // The type arguments are explicit because they cannot be inferred: the lambda's
            // parameter type is what the compiler would need to infer TDefinition from, and it
            // is the thing being inferred. Writing both out is the fix, and it is also clearer
            // about which asset type feeds which definition.
            return new GameContent(
                Catalog<WeaponAsset, WeaponDefinition>(weapons, w => w.Id),
                Catalog<AttachmentAsset, AttachmentDefinition>(attachments, a => a.Id),
                Catalog<CharacterAsset, CharacterDefinition>(characters, c => c.Id),
                Catalog<FactionAsset, FactionDefinition>(factions, f => f.Id),
                Catalog<MapAsset, MapDefinition>(maps, m => m.Id),
                Catalog<WorldAsset, WorldDefinition>(worlds, w => w.Id),
                Catalog<GameModeAsset, GameModeDefinition>(gameModes, m => m.Id),
                Catalog<BotDifficultyAsset, BotDifficultyDefinition>(botDifficulties, d => d.Id));
        }

        // An instance method, not static, so the error messages can name which catalogue asset
        // the bad entry is in. With several catalogues in a project, "entry 3 is missing" on its
        // own is not an actionable message.
        private InMemoryCatalog<TDefinition> Catalog<TAsset, TDefinition>(
            List<TAsset> assets, System.Func<TDefinition, ContentId> idOf)
            where TAsset : DefinitionAsset<TDefinition>
            where TDefinition : class
        {
            var catalog = new InMemoryCatalog<TDefinition>();
            for (int i = 0; i < assets.Count; i++)
            {
                // A null entry is a reference to an asset that was deleted. Skipping it quietly
                // would ship a build missing a weapon; the log line is what makes it findable.
                if (assets[i] == null)
                {
                    Debug.LogError($"[Salvo] {name}: entry {i} of {typeof(TAsset).Name} is missing.");
                    continue;
                }
                TDefinition definition = assets[i].Definition;
                if (definition == null)
                {
                    Debug.LogError($"[Salvo] {assets[i].name} has no definition.");
                    continue;
                }
                catalog.Add(idOf(definition), definition);
            }
            return catalog;
        }

        /// <summary>Every problem across every asset, plus the cross-reference checks.</summary>
        public List<string> Validate()
        {
            var problems = new List<string>();
            void Check<TAsset, TDefinition>(List<TAsset> assets)
                where TAsset : DefinitionAsset<TDefinition> where TDefinition : class
            {
                foreach (TAsset asset in assets)
                {
                    if (asset == null) { problems.Add("a catalogue entry is missing"); continue; }
                    foreach (string problem in asset.Validate())
                        problems.Add($"{asset.name}: {problem}");
                }
            }

            Check<WeaponAsset, WeaponDefinition>(weapons);
            Check<AttachmentAsset, AttachmentDefinition>(attachments);
            Check<CharacterAsset, CharacterDefinition>(characters);
            Check<FactionAsset, FactionDefinition>(factions);
            Check<MapAsset, MapDefinition>(maps);
            Check<WorldAsset, WorldDefinition>(worlds);
            Check<GameModeAsset, GameModeDefinition>(gameModes);
            Check<BotDifficultyAsset, BotDifficultyDefinition>(botDifficulties);

            if (problems.Count == 0) problems.AddRange(Build().Validate());
            return problems;
        }
    }
}
