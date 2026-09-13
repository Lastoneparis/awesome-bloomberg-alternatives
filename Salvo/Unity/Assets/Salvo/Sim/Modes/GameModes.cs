namespace Salvo.Sim
{
    /// <summary>
    /// Builds the <see cref="IGameMode"/> that runs a given definition.
    /// </summary>
    /// <remarks>
    /// One place, because the mapping was starting to be copied into every caller that needed a
    /// match — and a copied switch is one that will be missing a case the next time a mode is
    /// added. Which is exactly what happens: the copies each knew about deathmatch and
    /// free-for-all, and neither would have known about the round-based one.
    /// </remarks>
    public static class GameModes
    {
        /// <summary>
        /// Throws for a kind with no implementation, rather than quietly substituting deathmatch.
        /// A mode that silently becomes a different mode is a far worse outcome than a match that
        /// refuses to start.
        /// </summary>
        public static IGameMode Create(GameModeDefinition definition)
        {
            if (definition == null) throw new System.ArgumentNullException(nameof(definition));

            return definition.Kind switch
            {
                GameModeKind.TeamDeathmatch => new TeamDeathmatchMode(definition),
                GameModeKind.FreeForAll => new FreeForAllMode(definition),
                GameModeKind.RoundObjective => new OverloadMode(definition),
                _ => throw new System.NotSupportedException(
                    $"game mode '{definition.Id}' is of kind {definition.Kind}, "
                    + "which has no implementation yet"),
            };
        }

        /// <summary>True when <see cref="Create"/> would succeed. For content validation and for
        /// a menu that should not offer a mode nothing can run.</summary>
        public static bool IsImplemented(GameModeKind kind) => kind switch
        {
            GameModeKind.TeamDeathmatch => true,
            GameModeKind.FreeForAll => true,
            GameModeKind.RoundObjective => true,
            _ => false,
        };
    }
}
