using System;

namespace Salvo.Sim
{
    public enum WeaponClass : byte
    {
        Pistol, SubmachineGun, AssaultRifle, Shotgun, SniperRifle,
        LightMachineGun, Marksman, Melee, Thrown, Special
    }

    public enum FireMode : byte { Semi, Automatic, Burst, Bolt, Pump }

    public enum AttachmentSlot : byte { Optic, Barrel, Magazine, Grip, Stock, Laser }

    /// <summary>
    /// Everything the simulation needs to know about a weapon.
    /// </summary>
    /// <remarks>
    /// A plain class, not a ScriptableObject: the dedicated server has no Unity in it. The
    /// Unity layer wraps this in a ScriptableObject so designers author it in the Inspector,
    /// and the server loads the identical shape from JSON. One schema, two loaders.
    ///
    /// Nothing here is a behaviour. Adding a weapon is adding one of these; there is no
    /// weapon-specific code anywhere in the simulation.
    /// </remarks>
    [Serializable]
    public class WeaponDefinition
    {
        public ContentId Id;
        public string DisplayNameKey = "";      // localisation key, never a literal (§22)
        public WeaponClass Class = WeaponClass.AssaultRifle;
        public FireMode FireMode = FireMode.Automatic;

        /// <summary>Which world this belongs to. A bolt-action does not appear in a Mars
        /// match unless a designer says it does.</summary>
        public ContentId WorldId;

        // ── Damage ──────────────────────────────────────────────────────────────────
        public float BaseDamage = 25f;
        public float HeadshotMultiplier = 3.5f;
        /// <summary>Damage is full up to this range, then falls off linearly to
        /// <see cref="FalloffEndMetres"/>, where it is <see cref="FalloffFloor"/> of base.</summary>
        public float FalloffStartMetres = 25f;
        public float FalloffEndMetres = 60f;
        public float FalloffFloor = 0.55f;
        /// <summary>0–1. The fraction of damage that ignores armour.</summary>
        public float ArmourPiercing = 0.35f;

        // ── Fire ────────────────────────────────────────────────────────────────────
        public float RoundsPerMinute = 600f;
        public int BurstCount = 1;
        public float BurstDelaySeconds = 0.3f;
        public int PelletsPerShot = 1;
        public int MagazineSize = 30;
        public int ReserveAmmo = 120;
        public float ReloadSeconds = 2.2f;
        /// <summary>Reloading from empty also cycles the action, so it takes longer.</summary>
        public float EmptyReloadSeconds = 2.9f;
        public bool ReloadsOneRoundAtATime = false;
        public float DrawSeconds = 0.5f;
        public float HolsterSeconds = 0.35f;
        /// <summary>0 means hitscan. Anything above makes it a travelling projectile.</summary>
        public float MuzzleVelocity = 0f;
        public float MaxRangeMetres = 120f;

        // ── Accuracy and recoil ─────────────────────────────────────────────────────
        public float HipSpreadRadians = 0.022f;
        public float AdsSpreadRadians = 0.002f;
        public float SpreadPerShot = 0.004f;
        public float MaxSpreadRadians = 0.09f;
        public float SpreadRecoveryPerSecond = 0.14f;
        /// <summary>
        /// Seconds after the last shot before spread starts recovering.
        /// </summary>
        /// <remarks>
        /// Without a delay the model cannot express what a spray actually does. Recovery has to
        /// be fast enough that a player who stops shooting is accurate again within about half a
        /// second, but a rate that fast is also faster than any automatic weapon accumulates
        /// spread — so with continuous recovery the spread would sit at its floor throughout a
        /// magazine and spray control would not exist. Gating recovery behind a delay longer
        /// than the weapon's own cycle time lets both be true at once.
        /// </remarks>
        public float SpreadRecoveryDelaySeconds = 0.22f;
        public float MovingSpreadPenalty = 0.018f;
        public float AirborneSpreadPenalty = 0.07f;
        public float CrouchSpreadMultiplier = 0.7f;
        public float RecoilVerticalRadians = 0.011f;
        public float RecoilHorizontalRadians = 0.004f;
        public float RecoilRecoveryPerSecond = 7f;
        /// <summary>A learnable spray shape. Empty means pure randomness, which is not
        /// learnable and therefore not competitive.</summary>
        public SprayPoint[] SprayPattern = Array.Empty<SprayPoint>();

        // ── Handling ────────────────────────────────────────────────────────────────
        public float AdsSeconds = 0.25f;
        public float AdsFovMultiplier = 0.75f;
        public float MoveSpeedMultiplier = 1f;
        public float AdsMoveSpeedMultiplier = 0.5f;
        /// <summary>Affects sway and swap feel. Heavier is slower, never more damaging.</summary>
        public float Weight = 1f;

        // ── Presentation keys (resolved by the Unity layer, unused by the simulation) ─
        public ContentId ModelKey;
        public ContentId FireSoundKey;
        public ContentId ReloadSoundKey;
        public AttachmentSlot[] SupportedAttachments =
            { AttachmentSlot.Optic, AttachmentSlot.Barrel, AttachmentSlot.Magazine,
              AttachmentSlot.Grip, AttachmentSlot.Stock, AttachmentSlot.Laser };

        public float SecondsBetweenShots =>
            RoundsPerMinute <= 0f ? 0.1f : 60f / RoundsPerMinute;

        public bool IsHitscan => MuzzleVelocity <= 0f;

        /// <summary>A copy, for attachments to modify. Catalog definitions are shared by
        /// every match on a server, so nothing may mutate one in place.</summary>
        public WeaponDefinition Clone() => (WeaponDefinition)MemberwiseClone();

        /// <summary>Damage at a distance, before hitbox and armour are applied.</summary>
        public float DamageAtRange(float metres)
        {
            if (metres <= FalloffStartMetres) return BaseDamage;
            if (metres >= FalloffEndMetres) return BaseDamage * FalloffFloor;
            float t = SalvoMath.InverseLerp(FalloffStartMetres, FalloffEndMetres, metres);
            return BaseDamage * SalvoMath.Lerp(1f, FalloffFloor, t);
        }

        /// <summary>
        /// Reports any way this definition is internally inconsistent. Content is authored
        /// by hand, so it is wrong sometimes; the validator turns "the shotgun feels odd"
        /// into a build error naming the field.
        /// </summary>
        public void Validate(System.Collections.Generic.List<string> problems)
        {
            if (Id.IsEmpty) problems.Add("weapon has no Id");
            string name = Id.ToString();
            if (BaseDamage <= 0f) problems.Add($"{name}: BaseDamage must be positive");
            if (RoundsPerMinute <= 0f && Class != WeaponClass.Melee)
                problems.Add($"{name}: RoundsPerMinute must be positive");
            if (MagazineSize <= 0 && Class != WeaponClass.Melee)
                problems.Add($"{name}: MagazineSize must be positive");
            if (FalloffEndMetres <= FalloffStartMetres)
                problems.Add($"{name}: FalloffEndMetres must exceed FalloffStartMetres");
            if (FalloffFloor < 0f || FalloffFloor > 1f)
                problems.Add($"{name}: FalloffFloor must be within 0..1");
            if (AdsSpreadRadians > HipSpreadRadians)
                problems.Add($"{name}: aiming is less accurate than hip fire");
            if (MaxSpreadRadians < HipSpreadRadians)
                problems.Add($"{name}: MaxSpreadRadians is below the hip-fire spread");
            if (HeadshotMultiplier < 1f)
                problems.Add($"{name}: HeadshotMultiplier below 1 punishes precision");
            if (ArmourPiercing < 0f || ArmourPiercing > 1f)
                problems.Add($"{name}: ArmourPiercing must be within 0..1");
            if (string.IsNullOrEmpty(DisplayNameKey))
                problems.Add($"{name}: DisplayNameKey is empty — UI would show a raw id");
            if (SpreadRecoveryDelaySeconds <= SecondsBetweenShots
                && Class != WeaponClass.Melee && FireMode == FireMode.Automatic)
                problems.Add($"{name}: SpreadRecoveryDelaySeconds ({SpreadRecoveryDelaySeconds:F3}s) "
                             + $"is not longer than the time between shots ({SecondsBetweenShots:F3}s), "
                             + "so spread would recover between rounds and the spray would never climb");
            if (!IsHitscan)
                problems.Add($"{name}: MuzzleVelocity is set, but Ballistics has no projectile "
                             + "path yet and would fire it as hitscan. Ship it as hitscan or "
                             + "wait for projectiles.");
        }
    }

    /// <summary>One step of a spray pattern, in radians, applied in sequence.</summary>
    [Serializable]
    public struct SprayPoint
    {
        public float Vertical;
        public float Horizontal;
        public SprayPoint(float vertical, float horizontal)
        {
            Vertical = vertical;
            Horizontal = horizontal;
        }
    }
}
