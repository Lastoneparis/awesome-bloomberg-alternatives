using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>Which weapon a player is holding.</summary>
    public enum WeaponSlot : byte { Primary = 0, Secondary = 1, Melee = 2 }

    /// <summary>One weapon plus the attachments fitted to it.</summary>
    public struct WeaponBuild
    {
        public ContentId WeaponId;
        /// <summary>At most one per <see cref="AttachmentSlot"/>. A list rather than a fixed
        /// array because most builds fit one or two and the array would be mostly empty.</summary>
        public ContentId[] Attachments;

        public WeaponBuild(ContentId weaponId, params ContentId[] attachments)
        {
            WeaponId = weaponId;
            Attachments = attachments ?? System.Array.Empty<ContentId>();
        }
    }

    /// <summary>
    /// What a player carries into a match.
    /// </summary>
    /// <remarks>
    /// Cosmetics are deliberately not here. A loadout is simulation input — it decides what the
    /// server computes — whereas a skin decides what a client draws. Keeping them apart is what
    /// guarantees a cosmetic can never reach the damage model, which is the structural half of
    /// the promise in §31 that nothing sold confers an advantage. The other half is
    /// <see cref="CosmeticIsNeverGameplay"/>, which states it where a future reader will look.
    /// </remarks>
    public struct Loadout
    {
        public WeaponBuild Primary;
        public WeaponBuild Secondary;
        public WeaponBuild Melee;

        public ContentId CharacterId;

        /// <summary>
        /// A standing note for anyone extending this type: if you are about to add a field here
        /// that a store sells, stop. Loadout is read by the authoritative simulation. Anything
        /// in it can change a fight. Cosmetic identity belongs on the presentation-side player
        /// record, which the simulation never sees.
        /// </summary>
        public const string CosmeticIsNeverGameplay =
            "Loadout is simulation state. Cosmetics belong to presentation, never here.";

        public WeaponBuild this[WeaponSlot slot] => slot switch
        {
            WeaponSlot.Primary => Primary,
            WeaponSlot.Secondary => Secondary,
            _ => Melee,
        };

        public static Loadout Default(ContentId primary, ContentId secondary, ContentId melee,
                                      ContentId character = default) => new Loadout
        {
            Primary = new WeaponBuild(primary),
            Secondary = new WeaponBuild(secondary),
            Melee = new WeaponBuild(melee),
            CharacterId = character,
        };
    }

    /// <summary>
    /// Turns a <see cref="WeaponBuild"/> into the single <see cref="WeaponDefinition"/> the
    /// simulation actually uses, with every attachment folded in.
    /// </summary>
    /// <remarks>
    /// Resolution happens once when a player spawns, not per shot. Two reasons: the per-shot
    /// cost would be paid 64 times a second per player on the server, and more importantly a
    /// player's weapon must not change mid-magazine because a catalogue reloaded underneath
    /// them.
    /// </remarks>
    public sealed class LoadoutResolver
    {
        private readonly GameContent _content;
        private readonly Dictionary<string, WeaponDefinition> _cache =
            new Dictionary<string, WeaponDefinition>();

        public LoadoutResolver(GameContent content) { _content = content; }

        public void ClearCache() => _cache.Clear();

        /// <summary>
        /// The resolved weapon, or null if the build names something the catalogue does not have.
        /// Null rather than a substitute: quietly handing a player a different weapon than the
        /// one they chose is worse than failing loudly at spawn.
        /// </summary>
        public WeaponDefinition Resolve(WeaponBuild build)
        {
            if (build.WeaponId.IsEmpty) return null;
            string key = CacheKey(build);
            if (_cache.TryGetValue(key, out WeaponDefinition cached)) return cached;

            if (!_content.Weapons.TryGet(build.WeaponId, out WeaponDefinition weapon)) return null;

            WeaponDefinition resolved = weapon;
            if (build.Attachments != null)
            {
                var usedSlots = new HashSet<AttachmentSlot>();
                for (int i = 0; i < build.Attachments.Length; i++)
                {
                    if (!_content.Attachments.TryGet(build.Attachments[i],
                                                     out AttachmentDefinition attachment)) continue;
                    // One attachment per slot. Without this a client could send the same optic
                    // five times and stack its recoil reduction into an aimbot.
                    if (!usedSlots.Add(attachment.Slot)) continue;
                    if (!IsCompatible(attachment, weapon)) continue;
                    resolved = attachment.ApplyTo(resolved);
                }
            }

            _cache[key] = resolved;
            return resolved;
        }

        private static bool IsCompatible(AttachmentDefinition attachment, WeaponDefinition weapon)
        {
            if (attachment.CompatibleWeapons == null || attachment.CompatibleWeapons.Length == 0)
                return true;    // an empty list means universal
            for (int i = 0; i < attachment.CompatibleWeapons.Length; i++)
                if (attachment.CompatibleWeapons[i] == weapon.Id) return true;
            return false;
        }

        private static string CacheKey(WeaponBuild build)
        {
            if (build.Attachments == null || build.Attachments.Length == 0)
                return build.WeaponId.ToString();
            var builder = new System.Text.StringBuilder(build.WeaponId.ToString());
            for (int i = 0; i < build.Attachments.Length; i++)
            {
                builder.Append('|');
                builder.Append(build.Attachments[i].ToString());
            }
            return builder.ToString();
        }
    }
}
