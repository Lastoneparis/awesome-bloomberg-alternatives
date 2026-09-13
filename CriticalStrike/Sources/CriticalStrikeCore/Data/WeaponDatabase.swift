import Foundation

/// The shipping weapon roster. Balance philosophy:
///  - Rifles are the baseline: 4-5 shots to kill unarmored, 1 headshot at close range.
///  - SMGs win the first 12m, lose past 25m.
///  - Snipers one-shot the chest but punish movement hard.
///  - Nothing kills faster than 0.30s time-to-kill inside 10m except a headshot.
public enum WeaponDatabase {
    public static let all: [WeaponData] = [
        // ───────────────────────── Assault Rifles ─────────────────────────
        WeaponData(
            id: "ar_vanguard", name: "Vanguard-15", weaponClass: .assaultRifle, fireMode: .auto,
            ammoType: .heavy, rarity: .common,
            baseDamage: 26, falloffStart: 30, falloffEnd: 70, falloffMinScale: 0.62,
            penetrationPower: 1.6, armorPenetration: 0.62, headshotMultiplier: 4.0,
            roundsPerMinute: 640, magazineSize: 30, reserveAmmo: 120,
            reloadTime: 2.1, emptyReloadTime: 2.75, range: 140,
            baseSpread: 0.021, adsSpread: 0.0016, spreadPerShot: 0.0042, maxSpread: 0.085,
            spreadRecovery: 0.16, recoilVertical: 0.0105, recoilHorizontal: 0.0038,
            sprayPattern: SprayPatterns.vanguard,
            adsTime: 0.22, adsZoom: 1.35, movementSpeedScale: 0.95, weight: 1.0,
            unlockLevel: 1, buyCost: 2700, storeCostCoins: 0, killReward: 300),

        WeaponData(
            id: "ar_falcon", name: "Falcon AR", weaponClass: .assaultRifle, fireMode: .auto,
            ammoType: .heavy, rarity: .uncommon,
            baseDamage: 23, falloffStart: 34, falloffEnd: 80, falloffMinScale: 0.68,
            penetrationPower: 1.5, armorPenetration: 0.58,
            roundsPerMinute: 730, magazineSize: 30, reserveAmmo: 150,
            reloadTime: 2.0, range: 150,
            baseSpread: 0.019, adsSpread: 0.0014, spreadPerShot: 0.0038, maxSpread: 0.08,
            spreadRecovery: 0.18, recoilVertical: 0.0092, recoilHorizontal: 0.0044,
            sprayPattern: SprayPatterns.falcon,
            adsTime: 0.21, movementSpeedScale: 0.96,
            unlockLevel: 6, buyCost: 3100, storeCostCoins: 14000),

        WeaponData(
            id: "ar_krait", name: "Krait-74", weaponClass: .assaultRifle, fireMode: .auto,
            ammoType: .heavy, rarity: .rare,
            baseDamage: 29, falloffStart: 28, falloffEnd: 65, falloffMinScale: 0.58,
            penetrationPower: 1.9, armorPenetration: 0.7,
            roundsPerMinute: 560, magazineSize: 30, reserveAmmo: 120,
            reloadTime: 2.35, emptyReloadTime: 3.0, range: 145,
            baseSpread: 0.024, adsSpread: 0.0018, spreadPerShot: 0.0055, maxSpread: 0.095,
            spreadRecovery: 0.15, recoilVertical: 0.0135, recoilHorizontal: 0.0035,
            sprayPattern: SprayPatterns.krait,
            adsTime: 0.25, movementSpeedScale: 0.93, weight: 1.15,
            unlockLevel: 14, buyCost: 3300, storeCostCoins: 22000, storeCostGems: 900),

        WeaponData(
            id: "ar_tempest", name: "Tempest Burst", weaponClass: .assaultRifle, fireMode: .burst,
            ammoType: .heavy, rarity: .rare,
            baseDamage: 32, falloffStart: 38, falloffEnd: 85, falloffMinScale: 0.7,
            penetrationPower: 1.7, armorPenetration: 0.65, headshotMultiplier: 3.6,
            roundsPerMinute: 900, burstCount: 3, burstDelay: 0.34, magazineSize: 27, reserveAmmo: 108,
            reloadTime: 2.2, range: 160,
            baseSpread: 0.02, adsSpread: 0.0009, spreadPerShot: 0.003, maxSpread: 0.07,
            spreadRecovery: 0.2, recoilVertical: 0.0125, recoilHorizontal: 0.002,
            sprayPattern: SprayPatterns.tempest,
            adsTime: 0.24, adsZoom: 1.5, movementSpeedScale: 0.94,
            unlockLevel: 22, buyCost: 3200, storeCostCoins: 26000),

        // ───────────────────────── SMGs ─────────────────────────
        WeaponData(
            id: "smg_wasp", name: "Wasp MP", weaponClass: .submachineGun, fireMode: .auto,
            ammoType: .light, rarity: .common,
            baseDamage: 20, falloffStart: 14, falloffEnd: 34, falloffMinScale: 0.42,
            penetrationPower: 0.9, armorPenetration: 0.45, headshotMultiplier: 3.4,
            roundsPerMinute: 900, magazineSize: 30, reserveAmmo: 150,
            reloadTime: 1.75, emptyReloadTime: 2.3, range: 90,
            baseSpread: 0.026, adsSpread: 0.004, spreadPerShot: 0.0042, maxSpread: 0.11,
            spreadRecovery: 0.22, moveSpreadPenalty: 0.008, recoilVertical: 0.0075, recoilHorizontal: 0.0052,
            sprayPattern: SprayPatterns.wasp,
            adsTime: 0.17, adsZoom: 1.2, movementSpeedScale: 1.04, adsMovementScale: 0.62, weight: 0.75,
            unlockLevel: 1, buyCost: 1900, killReward: 600),

        WeaponData(
            id: "smg_hornet", name: "Hornet-9", weaponClass: .submachineGun, fireMode: .auto,
            ammoType: .light, rarity: .uncommon,
            baseDamage: 18, falloffStart: 16, falloffEnd: 38, falloffMinScale: 0.45,
            penetrationPower: 0.8, armorPenetration: 0.4, headshotMultiplier: 3.2,
            roundsPerMinute: 1050, magazineSize: 35, reserveAmmo: 175,
            reloadTime: 1.85, range: 95,
            baseSpread: 0.028, adsSpread: 0.0045, spreadPerShot: 0.0038, maxSpread: 0.12,
            spreadRecovery: 0.24, moveSpreadPenalty: 0.007, recoilVertical: 0.0065, recoilHorizontal: 0.006,
            sprayPattern: SprayPatterns.hornet,
            adsTime: 0.16, adsZoom: 1.18, movementSpeedScale: 1.06, weight: 0.7,
            unlockLevel: 9, buyCost: 2100, storeCostCoins: 16000, killReward: 600),

        WeaponData(
            id: "smg_viper", name: "Viper PDW", weaponClass: .submachineGun, fireMode: .auto,
            ammoType: .light, rarity: .epic,
            baseDamage: 24, falloffStart: 12, falloffEnd: 30, falloffMinScale: 0.38,
            penetrationPower: 1.0, armorPenetration: 0.55, headshotMultiplier: 3.5,
            roundsPerMinute: 820, magazineSize: 25, reserveAmmo: 125,
            reloadTime: 1.9, range: 85,
            baseSpread: 0.024, adsSpread: 0.0035, spreadPerShot: 0.005, maxSpread: 0.1,
            spreadRecovery: 0.2, moveSpreadPenalty: 0.0075, recoilVertical: 0.0088, recoilHorizontal: 0.0048,
            sprayPattern: SprayPatterns.viper,
            adsTime: 0.18, movementSpeedScale: 1.03, weight: 0.8,
            unlockLevel: 28, buyCost: 2400, storeCostGems: 1600, killReward: 600),

        // ───────────────────────── Snipers ─────────────────────────
        WeaponData(
            id: "snp_longbow", name: "Longbow .338", weaponClass: .sniperRifle, fireMode: .bolt,
            ammoType: .sniper, rarity: .rare,
            baseDamage: 118, falloffStart: 120, falloffEnd: 240, falloffMinScale: 0.85,
            penetrationPower: 3.2, penetrationDamageScale: 0.78, armorPenetration: 0.9, headshotMultiplier: 2.6,
            roundsPerMinute: 45, magazineSize: 5, reserveAmmo: 25,
            reloadTime: 3.4, emptyReloadTime: 3.9, drawTime: 0.9, holsterTime: 0.5, range: 300,
            baseSpread: 0.075, adsSpread: 0.0, spreadPerShot: 0.02, maxSpread: 0.14,
            spreadRecovery: 0.1, moveSpreadPenalty: 0.05, crouchSpreadBonus: 0.55,
            recoilVertical: 0.05, recoilHorizontal: 0.006, recoilRecoverySpeed: 4,
            adsTime: 0.52, adsZoom: 4.0, scopeLevels: [4.0, 8.0],
            movementSpeedScale: 0.86, adsMovementScale: 0.32, weight: 1.6,
            tracerColorHex: 0xFFF3C4, muzzleFlashScale: 1.6, crosshairKind: .sniper,
            unlockLevel: 12, buyCost: 4750, storeCostCoins: 30000, killReward: 100),

        WeaponData(
            id: "snp_specter", name: "Specter SR", weaponClass: .sniperRifle, fireMode: .semi,
            ammoType: .sniper, rarity: .legendary,
            baseDamage: 82, falloffStart: 100, falloffEnd: 220, falloffMinScale: 0.8,
            penetrationPower: 2.6, penetrationDamageScale: 0.7, armorPenetration: 0.8, headshotMultiplier: 2.2,
            roundsPerMinute: 130, magazineSize: 10, reserveAmmo: 40,
            reloadTime: 2.9, drawTime: 0.8, range: 280,
            baseSpread: 0.06, adsSpread: 0.0006, spreadPerShot: 0.014, maxSpread: 0.13,
            spreadRecovery: 0.12, moveSpreadPenalty: 0.04,
            recoilVertical: 0.032, recoilHorizontal: 0.005, recoilRecoverySpeed: 5,
            adsTime: 0.42, adsZoom: 3.0, scopeLevels: [3.0, 6.0],
            movementSpeedScale: 0.89, adsMovementScale: 0.38, weight: 1.4,
            crosshairKind: .sniper,
            unlockLevel: 34, buyCost: 5000, storeCostGems: 2600, killReward: 150),

        WeaponData(
            id: "mrk_ranger", name: "Ranger DMR", weaponClass: .marksman, fireMode: .semi,
            ammoType: .heavy, rarity: .uncommon,
            baseDamage: 52, falloffStart: 60, falloffEnd: 140, falloffMinScale: 0.72,
            penetrationPower: 2.2, armorPenetration: 0.72, headshotMultiplier: 2.9,
            roundsPerMinute: 260, magazineSize: 20, reserveAmmo: 80,
            reloadTime: 2.3, range: 220,
            baseSpread: 0.03, adsSpread: 0.0008, spreadPerShot: 0.009, maxSpread: 0.1,
            spreadRecovery: 0.16, recoilVertical: 0.021, recoilHorizontal: 0.004,
            adsTime: 0.3, adsZoom: 2.2, scopeLevels: [2.2],
            movementSpeedScale: 0.92, weight: 1.2,
            unlockLevel: 18, buyCost: 3400, storeCostCoins: 24000, killReward: 300),

        // ───────────────────────── Shotguns ─────────────────────────
        WeaponData(
            id: "sg_breaker", name: "Breaker 12", weaponClass: .shotgun, fireMode: .pump,
            ammoType: .shell, rarity: .common,
            baseDamage: 17, falloffStart: 6, falloffEnd: 22, falloffMinScale: 0.2,
            penetrationPower: 0.4, penetrationDamageScale: 0.35, armorPenetration: 0.35, headshotMultiplier: 2.0,
            roundsPerMinute: 70, pelletsPerShot: 9, magazineSize: 7, reserveAmmo: 28,
            reloadTime: 0.55, emptyReloadTime: 0.55, shellByShellReload: true, range: 40,
            baseSpread: 0.055, adsSpread: 0.035, spreadPerShot: 0.006, maxSpread: 0.09,
            spreadRecovery: 0.25, recoilVertical: 0.042, recoilHorizontal: 0.008,
            adsTime: 0.26, adsZoom: 1.1, movementSpeedScale: 0.94, weight: 1.25,
            muzzleFlashScale: 1.8, crosshairKind: .shotgun,
            unlockLevel: 4, buyCost: 2000, killReward: 900),

        WeaponData(
            id: "sg_havoc", name: "Havoc Auto", weaponClass: .shotgun, fireMode: .auto,
            ammoType: .shell, rarity: .epic,
            baseDamage: 11, falloffStart: 5, falloffEnd: 18, falloffMinScale: 0.18,
            penetrationPower: 0.3, armorPenetration: 0.3, headshotMultiplier: 1.8,
            roundsPerMinute: 240, pelletsPerShot: 8, magazineSize: 8, reserveAmmo: 32,
            reloadTime: 3.0, emptyReloadTime: 3.4, range: 35,
            baseSpread: 0.07, adsSpread: 0.05, spreadPerShot: 0.01, maxSpread: 0.13,
            spreadRecovery: 0.28, recoilVertical: 0.03, recoilHorizontal: 0.012,
            adsTime: 0.28, adsZoom: 1.1, movementSpeedScale: 0.92, weight: 1.4,
            crosshairKind: .shotgun,
            unlockLevel: 26, buyCost: 2900, storeCostGems: 1800, killReward: 900),

        // ───────────────────────── LMGs ─────────────────────────
        WeaponData(
            id: "lmg_bulwark", name: "Bulwark M249", weaponClass: .lightMachineGun, fireMode: .auto,
            ammoType: .heavy, rarity: .rare,
            baseDamage: 27, falloffStart: 40, falloffEnd: 95, falloffMinScale: 0.65,
            penetrationPower: 2.4, penetrationDamageScale: 0.72, armorPenetration: 0.72,
            roundsPerMinute: 700, magazineSize: 100, reserveAmmo: 200,
            reloadTime: 5.2, emptyReloadTime: 6.0, drawTime: 1.1, holsterTime: 0.7, range: 170,
            baseSpread: 0.04, adsSpread: 0.0035, spreadPerShot: 0.005, maxSpread: 0.12,
            spreadRecovery: 0.12, moveSpreadPenalty: 0.03, crouchSpreadBonus: 0.45,
            recoilVertical: 0.012, recoilHorizontal: 0.006, recoilRecoverySpeed: 5.5,
            sprayPattern: SprayPatterns.bulwark,
            adsTime: 0.42, movementSpeedScale: 0.82, adsMovementScale: 0.34, weight: 1.9,
            unlockLevel: 20, buyCost: 5200, storeCostCoins: 28000, killReward: 300),

        // ───────────────────────── Pistols ─────────────────────────
        WeaponData(
            id: "pst_sidearm", name: "P-90 Sidearm", weaponClass: .pistol, fireMode: .semi,
            ammoType: .light, rarity: .common,
            baseDamage: 26, falloffStart: 18, falloffEnd: 42, falloffMinScale: 0.5,
            penetrationPower: 0.8, armorPenetration: 0.45, headshotMultiplier: 3.8,
            roundsPerMinute: 400, magazineSize: 15, reserveAmmo: 60,
            reloadTime: 1.6, emptyReloadTime: 2.1, drawTime: 0.35, holsterTime: 0.25, range: 80,
            baseSpread: 0.02, adsSpread: 0.0028, spreadPerShot: 0.007, maxSpread: 0.09,
            spreadRecovery: 0.25, recoilVertical: 0.013, recoilHorizontal: 0.004,
            adsTime: 0.16, adsZoom: 1.2, movementSpeedScale: 1.08, weight: 0.5,
            unlockLevel: 1, buyCost: 0, killReward: 300),

        WeaponData(
            id: "pst_magnum", name: "Magnum .50", weaponClass: .pistol, fireMode: .semi,
            ammoType: .magnum, rarity: .epic,
            baseDamage: 58, falloffStart: 22, falloffEnd: 55, falloffMinScale: 0.6,
            penetrationPower: 1.8, armorPenetration: 0.78, headshotMultiplier: 2.6,
            roundsPerMinute: 170, magazineSize: 7, reserveAmmo: 28,
            reloadTime: 2.0, emptyReloadTime: 2.5, drawTime: 0.45, range: 110,
            baseSpread: 0.026, adsSpread: 0.002, spreadPerShot: 0.02, maxSpread: 0.12,
            spreadRecovery: 0.18, recoilVertical: 0.042, recoilHorizontal: 0.009, recoilRecoverySpeed: 5,
            adsTime: 0.2, adsZoom: 1.3, movementSpeedScale: 1.02, weight: 0.8,
            muzzleFlashScale: 1.5,
            unlockLevel: 16, buyCost: 900, storeCostGems: 1200, killReward: 300),

        WeaponData(
            id: "pst_tacmachine", name: "Tac Machine Pistol", weaponClass: .pistol, fireMode: .auto,
            ammoType: .light, rarity: .uncommon,
            baseDamage: 16, falloffStart: 12, falloffEnd: 28, falloffMinScale: 0.4,
            penetrationPower: 0.6, armorPenetration: 0.35, headshotMultiplier: 3.0,
            roundsPerMinute: 1100, magazineSize: 20, reserveAmmo: 80,
            reloadTime: 1.7, drawTime: 0.32, range: 70,
            baseSpread: 0.03, adsSpread: 0.006, spreadPerShot: 0.005, maxSpread: 0.13,
            spreadRecovery: 0.26, recoilVertical: 0.007, recoilHorizontal: 0.007,
            adsTime: 0.15, adsZoom: 1.15, movementSpeedScale: 1.07, weight: 0.55,
            unlockLevel: 11, buyCost: 600, storeCostCoins: 9000, killReward: 600),

        // ───────────────────────── Melee ─────────────────────────
        WeaponData(
            id: "mel_combatknife", name: "Combat Knife", weaponClass: .melee, fireMode: .single,
            ammoType: .none, rarity: .common,
            baseDamage: 55, falloffStart: 2.2, falloffEnd: 2.6, falloffMinScale: 0.0,
            penetrationPower: 0, penetrationDamageScale: 0, armorPenetration: 1.0, headshotMultiplier: 1.6,
            roundsPerMinute: 90, magazineSize: 0, reserveAmmo: 0,
            reloadTime: 0, drawTime: 0.25, holsterTime: 0.2, range: 2.4,
            baseSpread: 0, adsSpread: 0, spreadPerShot: 0, maxSpread: 0,
            recoilVertical: 0, recoilHorizontal: 0,
            adsTime: 0.1, adsZoom: 1.0, movementSpeedScale: 1.15, weight: 0.3,
            crosshairKind: .dot,
            unlockLevel: 1, buyCost: 0, killReward: 1500),

        WeaponData(
            id: "mel_karambit", name: "Karambit", weaponClass: .melee, fireMode: .single,
            ammoType: .none, rarity: .legendary,
            baseDamage: 62, falloffStart: 2.4, falloffEnd: 2.8, falloffMinScale: 0.0,
            penetrationPower: 0, penetrationDamageScale: 0, armorPenetration: 1.0, headshotMultiplier: 1.8,
            roundsPerMinute: 105, magazineSize: 0, reserveAmmo: 0,
            reloadTime: 0, drawTime: 0.22, holsterTime: 0.18, range: 2.6,
            baseSpread: 0, adsSpread: 0, spreadPerShot: 0, maxSpread: 0,
            recoilVertical: 0, recoilHorizontal: 0,
            adsTime: 0.1, adsZoom: 1.0, movementSpeedScale: 1.18, weight: 0.25,
            crosshairKind: .dot,
            unlockLevel: 40, buyCost: 0, storeCostGems: 3200, killReward: 1500)
    ]

    private static let index: [WeaponID: WeaponData] = {
        var m = [WeaponID: WeaponData]()
        for w in all { m[w.id] = w }
        return m
    }()

    public static func weapon(_ id: WeaponID) -> WeaponData? { index[id] }

    /// Never-nil accessor for code paths that cannot recover (falls back to the starter pistol).
    public static func weaponOrDefault(_ id: WeaponID) -> WeaponData {
        index[id] ?? index["pst_sidearm"] ?? all[0]
    }

    public static func weapons(of kind: WeaponClass) -> [WeaponData] {
        all.filter { $0.weaponClass == kind }
    }

    public static func weapons(forSlot slot: LoadoutSlot) -> [WeaponData] {
        all.filter { $0.weaponClass.slot == slot }
    }

    public static func unlocked(atLevel level: Int) -> [WeaponData] {
        all.filter { $0.unlockLevel <= level }
    }

    public static func unlocks(atLevel level: Int) -> [WeaponData] {
        all.filter { $0.unlockLevel == level }
    }

    public static let defaultPrimary: WeaponID = "ar_vanguard"
    public static let defaultSecondary: WeaponID = "pst_sidearm"
    public static let defaultMelee: WeaponID = "mel_combatknife"
}

/// Spray patterns are hand-authored so that they are *learnable*: the first shots go
/// straight up, then the pattern breaks left/right consistently. Values are radians.
public enum SprayPatterns {
    public static let vanguard: [SprayPoint] = [
        SprayPoint(0.000, 0.000), SprayPoint(0.010, 0.001), SprayPoint(0.020, -0.002),
        SprayPoint(0.029, -0.004), SprayPoint(0.037, -0.002), SprayPoint(0.044, 0.003),
        SprayPoint(0.050, 0.009), SprayPoint(0.054, 0.016), SprayPoint(0.057, 0.021),
        SprayPoint(0.059, 0.018), SprayPoint(0.060, 0.010), SprayPoint(0.061, -0.001),
        SprayPoint(0.062, -0.012), SprayPoint(0.062, -0.020), SprayPoint(0.063, -0.024),
        SprayPoint(0.063, -0.019), SprayPoint(0.064, -0.010), SprayPoint(0.064, 0.002),
        SprayPoint(0.065, 0.013), SprayPoint(0.065, 0.021), SprayPoint(0.066, 0.024),
        SprayPoint(0.066, 0.018), SprayPoint(0.067, 0.008), SprayPoint(0.067, -0.004),
        SprayPoint(0.068, -0.015), SprayPoint(0.068, -0.022), SprayPoint(0.069, -0.025),
        SprayPoint(0.069, -0.017), SprayPoint(0.070, -0.006), SprayPoint(0.070, 0.006)
    ]

    public static let falcon: [SprayPoint] = [
        SprayPoint(0.000, 0.000), SprayPoint(0.009, -0.001), SprayPoint(0.017, -0.003),
        SprayPoint(0.025, -0.006), SprayPoint(0.032, -0.004), SprayPoint(0.038, 0.002),
        SprayPoint(0.043, 0.010), SprayPoint(0.047, 0.018), SprayPoint(0.050, 0.024),
        SprayPoint(0.052, 0.022), SprayPoint(0.054, 0.014), SprayPoint(0.055, 0.004),
        SprayPoint(0.056, -0.008), SprayPoint(0.057, -0.018), SprayPoint(0.058, -0.026),
        SprayPoint(0.058, -0.024), SprayPoint(0.059, -0.015), SprayPoint(0.059, -0.004),
        SprayPoint(0.060, 0.008), SprayPoint(0.060, 0.018), SprayPoint(0.061, 0.026),
        SprayPoint(0.061, 0.023), SprayPoint(0.062, 0.014), SprayPoint(0.062, 0.003),
        SprayPoint(0.063, -0.009), SprayPoint(0.063, -0.019), SprayPoint(0.064, -0.027),
        SprayPoint(0.064, -0.022), SprayPoint(0.065, -0.011), SprayPoint(0.065, 0.001)
    ]

    public static let krait: [SprayPoint] = [
        SprayPoint(0.000, 0.000), SprayPoint(0.013, 0.002), SprayPoint(0.026, 0.005),
        SprayPoint(0.038, 0.003), SprayPoint(0.048, -0.004), SprayPoint(0.057, -0.012),
        SprayPoint(0.064, -0.020), SprayPoint(0.069, -0.026), SprayPoint(0.073, -0.022),
        SprayPoint(0.076, -0.012), SprayPoint(0.078, 0.000), SprayPoint(0.080, 0.013),
        SprayPoint(0.081, 0.023), SprayPoint(0.082, 0.029), SprayPoint(0.083, 0.024),
        SprayPoint(0.084, 0.014), SprayPoint(0.085, 0.001), SprayPoint(0.085, -0.012),
        SprayPoint(0.086, -0.023), SprayPoint(0.086, -0.030), SprayPoint(0.087, -0.026),
        SprayPoint(0.087, -0.015), SprayPoint(0.088, -0.002), SprayPoint(0.088, 0.011),
        SprayPoint(0.089, 0.022), SprayPoint(0.089, 0.030), SprayPoint(0.090, 0.027),
        SprayPoint(0.090, 0.016), SprayPoint(0.091, 0.003), SprayPoint(0.091, -0.010)
    ]

    public static let tempest: [SprayPoint] = [
        SprayPoint(0.000, 0.000), SprayPoint(0.014, 0.002), SprayPoint(0.027, 0.004),
        SprayPoint(0.004, 0.000), SprayPoint(0.017, -0.002), SprayPoint(0.030, -0.005),
        SprayPoint(0.006, 0.001), SprayPoint(0.019, 0.004), SprayPoint(0.032, 0.007)
    ]

    public static let wasp: [SprayPoint] = [
        SprayPoint(0.000, 0.000), SprayPoint(0.007, 0.002), SprayPoint(0.014, 0.005),
        SprayPoint(0.020, 0.002), SprayPoint(0.026, -0.004), SprayPoint(0.031, -0.010),
        SprayPoint(0.035, -0.016), SprayPoint(0.038, -0.012), SprayPoint(0.041, -0.004),
        SprayPoint(0.043, 0.005), SprayPoint(0.045, 0.013), SprayPoint(0.046, 0.019),
        SprayPoint(0.047, 0.014), SprayPoint(0.048, 0.006), SprayPoint(0.049, -0.003),
        SprayPoint(0.050, -0.012), SprayPoint(0.051, -0.018), SprayPoint(0.051, -0.014),
        SprayPoint(0.052, -0.005), SprayPoint(0.052, 0.004), SprayPoint(0.053, 0.013),
        SprayPoint(0.053, 0.019), SprayPoint(0.054, 0.015), SprayPoint(0.054, 0.006),
        SprayPoint(0.055, -0.003), SprayPoint(0.055, -0.012), SprayPoint(0.056, -0.019),
        SprayPoint(0.056, -0.013), SprayPoint(0.057, -0.004), SprayPoint(0.057, 0.005)
    ]

    public static let hornet: [SprayPoint] = wasp.map { SprayPoint($0.up * 0.86, $0.side * 1.15) }
    public static let viper: [SprayPoint] = wasp.map { SprayPoint($0.up * 1.15, $0.side * 0.9) }
    public static let bulwark: [SprayPoint] = vanguard.map { SprayPoint($0.up * 1.05, $0.side * 1.3) }
        + vanguard.map { SprayPoint(0.07 + $0.up * 0.2, $0.side * 1.6) }
}
