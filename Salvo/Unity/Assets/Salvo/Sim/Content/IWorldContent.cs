using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>
    /// Everything one era contributes to the catalogue.
    /// </summary>
    /// <remarks>
    /// A world is weapons, factions, characters and maps, plus the definition that ties them
    /// together. It is deliberately <em>not</em> game modes or bot difficulties: those are rules,
    /// they are shared by every era, and duplicating them per world is how a "modern" team
    /// deathmatch and a "WWII" team deathmatch quietly acquire different respawn timers.
    ///
    /// <para>The point of this interface is that adding an era is adding a file. If a second
    /// world ever needs a change in <c>Movement/</c>, <c>Combat/</c>, <c>Modes/</c>, <c>AI/</c>
    /// or <c>Net/</c>, the data model has failed to express something and the right response is
    /// to fix the data model — not to branch on the era. Gameplay must never branch on the era;
    /// <see cref="WorldDefinition.EraYear"/> exists for sorting and UI and nothing else.</para>
    /// </remarks>
    public interface IWorldContent
    {
        WorldDefinition World { get; }
        IEnumerable<WeaponDefinition> Weapons();
        IEnumerable<AttachmentDefinition> Attachments();
        IEnumerable<FactionDefinition> Factions();
        IEnumerable<CharacterDefinition> Characters();
        IEnumerable<MapDefinition> Maps();
    }

    /// <summary>Assembles one or more worlds, plus the shared rules, into a <see cref="GameContent"/>.</summary>
    public static class ContentAssembler
    {
        public static GameContent Assemble(IEnumerable<IWorldContent> worlds,
                                           IEnumerable<GameModeDefinition> modes,
                                           IEnumerable<BotDifficultyDefinition> difficulties)
        {
            var weapons = new InMemoryCatalog<WeaponDefinition>();
            var attachments = new InMemoryCatalog<AttachmentDefinition>();
            var characters = new InMemoryCatalog<CharacterDefinition>();
            var factions = new InMemoryCatalog<FactionDefinition>();
            var maps = new InMemoryCatalog<MapDefinition>();
            var worldCatalog = new InMemoryCatalog<WorldDefinition>();

            foreach (IWorldContent world in worlds)
            {
                worldCatalog.Add(world.World.Id, world.World);
                foreach (WeaponDefinition weapon in world.Weapons()) weapons.Add(weapon.Id, weapon);
                foreach (AttachmentDefinition a in world.Attachments()) attachments.Add(a.Id, a);
                foreach (FactionDefinition f in world.Factions()) factions.Add(f.Id, f);
                foreach (CharacterDefinition c in world.Characters()) characters.Add(c.Id, c);
                foreach (MapDefinition m in world.Maps()) maps.Add(m.Id, m);
            }

            var modeCatalog = new InMemoryCatalog<GameModeDefinition>();
            foreach (GameModeDefinition mode in modes) modeCatalog.Add(mode.Id, mode);

            var difficultyCatalog = new InMemoryCatalog<BotDifficultyDefinition>();
            foreach (BotDifficultyDefinition d in difficulties) difficultyCatalog.Add(d.Id, d);

            return new GameContent(weapons, attachments, characters, factions, maps,
                                   worldCatalog, modeCatalog, difficultyCatalog);
        }
    }
}
