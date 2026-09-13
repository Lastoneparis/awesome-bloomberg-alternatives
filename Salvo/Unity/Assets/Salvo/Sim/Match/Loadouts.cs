namespace Salvo.Sim
{
    /// <summary>
    /// Picks a sensible loadout from whatever a world actually ships.
    /// </summary>
    /// <remarks>
    /// Exists because hardcoding weapon ids at every call site quietly defeats the world system.
    /// It is easy to miss: a runner that always hands out the modern carbine still <em>works</em>
    /// on a 1940s map — the simulation has no opinion about anachronism — so nothing fails and
    /// players simply carry the wrong era's guns. The only way to notice is to not write the
    /// hardcoded version in the first place.
    ///
    /// <para>Choice is by weapon class rather than by id, so a world is free to name its
    /// weapons anything at all and still get a coherent primary, sidearm and melee.</para>
    /// </remarks>
    public static class Loadouts
    {
        /// <summary>
        /// A loadout drawn from <paramref name="worldId"/>'s weapon pool.
        /// </summary>
        /// <param name="variant">
        /// Varies which primary is chosen, so a team of bots is not carrying ten identical
        /// weapons and only one weapon's state machine is ever exercised.
        /// </param>
        /// <returns>
        /// False if the world has no usable weapons — a content error the caller should surface
        /// rather than paper over with a default that may not exist in this era.
        /// </returns>
        public static bool TryBuildDefault(GameContent content, ContentId worldId, int variant,
                                           out Loadout loadout)
        {
            loadout = default;
            if (content == null) return false;

            ContentId secondary = default, melee = default;
            var primaries = new System.Collections.Generic.List<ContentId>();

            foreach (WeaponDefinition weapon in content.Weapons.All)
            {
                if (weapon.WorldId != worldId) continue;

                switch (weapon.Class)
                {
                    case WeaponClass.Melee:
                        if (melee.IsEmpty) melee = weapon.Id;
                        break;
                    case WeaponClass.Pistol:
                        if (secondary.IsEmpty) secondary = weapon.Id;
                        break;
                    default:
                        primaries.Add(weapon.Id);
                        break;
                }
            }

            // Round-robin by variant. An earlier version indexed with a modulo over a running
            // count, which varied the result but in a way nobody could predict from reading it —
            // and which silently gave every variant-0 caller the last weapon in the catalogue.
            // This allocates a small list on a path that runs once per player per match, which
            // is a fair price for being obviously right.
            ContentId primary = primaries.Count == 0
                ? default
                : primaries[((variant % primaries.Count) + primaries.Count) % primaries.Count];

            if (primary.IsEmpty && secondary.IsEmpty) return false;
            if (primary.IsEmpty) primary = secondary;

            loadout = Loadout.Default(primary, secondary, melee);
            return true;
        }

        /// <summary>The world a map belongs to, or empty if the map does not name one.</summary>
        public static ContentId WorldOf(MapDefinition map) => map?.WorldId ?? ContentId.None;
    }
}
