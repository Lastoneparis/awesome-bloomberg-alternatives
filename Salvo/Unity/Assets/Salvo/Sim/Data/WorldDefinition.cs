using System;

namespace Salvo.Sim
{
    /// <summary>
    /// An era or setting: Modern, WWII, Cold War, Future, Sci-Fi, Ancient (§10).
    /// </summary>
    /// <remarks>
    /// The top of the content tree. A world owns its factions, its weapon pool, its maps
    /// and its presentation theme — and owns no behaviour at all. That is the whole point:
    /// adding WWII must not require the player controller to learn what century it is.
    ///
    /// The simulation reads only <see cref="WeaponPool"/> and <see cref="Factions"/>. Every
    /// other field is a key the presentation layer resolves.
    /// </remarks>
    [Serializable]
    public class WorldDefinition
    {
        public ContentId Id;
        public string DisplayNameKey = "";
        public string DescriptionKey = "";

        /// <summary>Roughly when this world is set. Sorting and UI only; no gameplay
        /// meaning, because gameplay must not branch on era.</summary>
        public int EraYear = 2020;

        /// <summary>Weapons legal in this world. A match in a world may not spawn a weapon
        /// that is not in its pool — that check is the entire era-consistency system.</summary>
        public ContentId[] WeaponPool = Array.Empty<ContentId>();
        public ContentId[] Factions = Array.Empty<ContentId>();
        public ContentId[] Maps = Array.Empty<ContentId>();

        // Presentation keys, resolved by the Unity layer.
        public ContentId UiThemeKey;
        public ContentId MusicKey;
        public ContentId AmbienceKey;

        public void Validate(System.Collections.Generic.List<string> problems)
        {
            if (Id.IsEmpty) problems.Add("world has no Id");
            string name = Id.ToString();
            if (WeaponPool.Length == 0) problems.Add($"{name}: no weapons — nothing to fight with");
            if (Factions.Length < 2) problems.Add($"{name}: needs at least two factions");
            if (Maps.Length == 0) problems.Add($"{name}: no maps");
            if (string.IsNullOrEmpty(DisplayNameKey)) problems.Add($"{name}: DisplayNameKey is empty");
        }
    }

    /// <summary>
    /// One side within a world: who they are, what they look like, what they can carry.
    /// Original fictional organisations only — never a real military's insignia or name.
    /// </summary>
    [Serializable]
    public class FactionDefinition
    {
        public ContentId Id;
        public string DisplayNameKey = "";
        public ContentId WorldId;

        /// <summary>Characters this faction fields. Cosmetic; no stat differences ever,
        /// because a faction that shoots harder is pay-to-win by another name.</summary>
        public ContentId[] Characters = Array.Empty<ContentId>();

        /// <summary>Narrower than the world pool where a faction should feel distinct.
        /// Empty means the whole world pool.</summary>
        public ContentId[] WeaponPool = Array.Empty<ContentId>();

        /// <summary>Packed RGB, for minimap and HUD. Accessibility palettes override it.</summary>
        public uint ColourRgb = 0x4C8DFF;

        public void Validate(System.Collections.Generic.List<string> problems)
        {
            if (Id.IsEmpty) problems.Add("faction has no Id");
            if (string.IsNullOrEmpty(DisplayNameKey))
                problems.Add($"{Id}: DisplayNameKey is empty");
        }
    }

    /// <summary>
    /// A playable character. Cosmetic only — every character moves, aims and dies
    /// identically, so picking one is never a competitive decision (§12).
    /// </summary>
    [Serializable]
    public class CharacterDefinition
    {
        public ContentId Id;
        public string DisplayNameKey = "";
        public ContentId FactionId;
        public ContentId ModelKey;
        public ContentId VoiceKey;

        /// <summary>Hitbox height in metres. Identical for every character on purpose: a
        /// shorter character would be strictly harder to hit.</summary>
        public const float StandingHeight = 1.8f;
        public const float CrouchingHeight = 1.25f;
        public const float Radius = 0.4f;

        public void Validate(System.Collections.Generic.List<string> problems)
        {
            if (Id.IsEmpty) problems.Add("character has no Id");
            if (string.IsNullOrEmpty(DisplayNameKey))
                problems.Add($"{Id}: DisplayNameKey is empty");
        }
    }
}
