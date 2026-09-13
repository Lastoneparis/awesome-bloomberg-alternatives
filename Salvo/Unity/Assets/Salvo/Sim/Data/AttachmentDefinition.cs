using System;

namespace Salvo.Sim
{
    /// <summary>
    /// A weapon attachment.
    /// </summary>
    /// <remarks>
    /// Every attachment is a set of multipliers applied over a <see cref="WeaponDefinition"/>.
    /// There is no attachment-specific code, and there is no attachment that is purely an
    /// upgrade: <see cref="Validate"/> fails the build on one that has no downside, because
    /// an attachment everyone equips is not a choice, it is a patch to the base weapon.
    /// </remarks>
    [Serializable]
    public class AttachmentDefinition
    {
        public ContentId Id;
        public string DisplayNameKey = "";
        public AttachmentSlot Slot = AttachmentSlot.Optic;

        /// <summary>Empty means it fits any weapon that supports the slot.</summary>
        public ContentId[] CompatibleWeapons = Array.Empty<ContentId>();

        // Multipliers. 1 means no change.
        public float DamageMultiplier = 1f;
        public float RecoilMultiplier = 1f;
        public float HipSpreadMultiplier = 1f;
        public float AdsSpreadMultiplier = 1f;
        public float AdsSpeedMultiplier = 1f;
        public float ReloadSpeedMultiplier = 1f;
        public float MoveSpeedMultiplier = 1f;
        public float RangeMultiplier = 1f;
        public float FalloffStartMultiplier = 1f;

        // Additive.
        public int MagazineSizeDelta = 0;
        public float AdsFovMultiplier = 1f;

        public bool SuppressesMuzzleFlash = false;
        /// <summary>Hides the shooter from the minimap. A real advantage, so it must be
        /// paid for elsewhere.</summary>
        public bool HidesFromMinimap = false;

        public ContentId ModelKey;

        /// <summary>
        /// Applies this attachment over a weapon, returning a new definition. The original
        /// is never mutated: catalogs are shared across every match on the server.
        /// </summary>
        public WeaponDefinition ApplyTo(WeaponDefinition source)
        {
            WeaponDefinition result = source.Clone();
            result.BaseDamage *= DamageMultiplier;
            result.RecoilVerticalRadians *= RecoilMultiplier;
            result.RecoilHorizontalRadians *= RecoilMultiplier;
            result.HipSpreadRadians *= HipSpreadMultiplier;
            result.AdsSpreadRadians *= AdsSpreadMultiplier;
            result.AdsSeconds /= System.Math.Max(0.01f, AdsSpeedMultiplier);
            result.ReloadSeconds /= System.Math.Max(0.01f, ReloadSpeedMultiplier);
            result.EmptyReloadSeconds /= System.Math.Max(0.01f, ReloadSpeedMultiplier);
            result.MoveSpeedMultiplier *= MoveSpeedMultiplier;
            result.MaxRangeMetres *= RangeMultiplier;
            result.FalloffStartMetres *= FalloffStartMultiplier;
            result.FalloffEndMetres *= FalloffStartMultiplier;
            result.MagazineSize = System.Math.Max(1, result.MagazineSize + MagazineSizeDelta);
            result.AdsFovMultiplier *= AdsFovMultiplier;
            return result;
        }

        /// <summary>True when nothing about this attachment is worse than not having it.</summary>
        public bool IsStrictlyBetter()
        {
            bool anyBenefit =
                DamageMultiplier > 1f || RecoilMultiplier < 1f || HipSpreadMultiplier < 1f ||
                AdsSpreadMultiplier < 1f || AdsSpeedMultiplier > 1f || ReloadSpeedMultiplier > 1f ||
                MoveSpeedMultiplier > 1f || RangeMultiplier > 1f || FalloffStartMultiplier > 1f ||
                MagazineSizeDelta > 0 || SuppressesMuzzleFlash || HidesFromMinimap;

            bool anyCost =
                DamageMultiplier < 1f || RecoilMultiplier > 1f || HipSpreadMultiplier > 1f ||
                AdsSpreadMultiplier > 1f || AdsSpeedMultiplier < 1f || ReloadSpeedMultiplier < 1f ||
                MoveSpeedMultiplier < 1f || RangeMultiplier < 1f || FalloffStartMultiplier < 1f ||
                MagazineSizeDelta < 0;

            return anyBenefit && !anyCost;
        }

        public void Validate(System.Collections.Generic.List<string> problems)
        {
            if (Id.IsEmpty) problems.Add("attachment has no Id");
            string name = Id.ToString();
            if (string.IsNullOrEmpty(DisplayNameKey)) problems.Add($"{name}: DisplayNameKey is empty");
            if (IsStrictlyBetter())
                problems.Add($"{name}: is strictly better than no attachment — every player " +
                             "will equip it, so it is a buff to the base weapon, not a choice");
        }
    }
}
