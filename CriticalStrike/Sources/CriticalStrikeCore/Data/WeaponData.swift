import Foundation

public enum WeaponClass: String, Codable, CaseIterable, Sendable {
    case assaultRifle, submachineGun, sniperRifle, shotgun, lightMachineGun, marksman, pistol, melee, grenade, special

    public var displayName: String {
        switch self {
        case .assaultRifle: return "Assault Rifle"
        case .submachineGun: return "SMG"
        case .sniperRifle: return "Sniper"
        case .shotgun: return "Shotgun"
        case .lightMachineGun: return "LMG"
        case .marksman: return "Marksman"
        case .pistol: return "Pistol"
        case .melee: return "Melee"
        case .grenade: return "Grenade"
        case .special: return "Special"
        }
    }

    public var slot: LoadoutSlot {
        switch self {
        case .pistol: return .secondary
        case .melee: return .melee
        case .grenade: return .lethal
        default: return .primary
        }
    }
}

public enum LoadoutSlot: UInt8, Codable, CaseIterable, Sendable {
    case primary = 0, secondary, melee, lethal, tactical

    public var displayName: String {
        switch self {
        case .primary: return "Primary"
        case .secondary: return "Secondary"
        case .melee: return "Melee"
        case .lethal: return "Lethal"
        case .tactical: return "Tactical"
        }
    }
}

public enum FireMode: String, Codable, CaseIterable, Sendable {
    case auto, semi, burst, bolt, pump, single

    public var isAutomatic: Bool { self == .auto }
    public var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .semi: return "Semi"
        case .burst: return "Burst"
        case .bolt: return "Bolt"
        case .pump: return "Pump"
        case .single: return "Single"
        }
    }
}

public enum AmmoType: String, Codable, CaseIterable, Sendable {
    case light, heavy, magnum, shell, sniper, rocket, none
}

/// Rarity drives drop odds, card color and dismantle value.
public enum Rarity: Int, Codable, CaseIterable, Comparable, Sendable {
    case common = 0, uncommon, rare, epic, legendary, mythic

    public static func < (a: Rarity, b: Rarity) -> Bool { a.rawValue < b.rawValue }

    public var displayName: String {
        ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"][rawValue]
    }
    public var colorHex: UInt32 {
        [0x9AA0A6, 0x4CAF50, 0x2196F3, 0x9C27B0, 0xFFB300, 0xFF3D71][rawValue]
    }
    /// Published crate odds (see Docs/MONETIZATION.md — required by App Store guideline 3.1.1).
    public var dropWeight: Float {
        [1000, 520, 240, 80, 18, 3][rawValue]
    }
    public var dismantleValue: Int {
        [10, 30, 90, 260, 800, 2400][rawValue]
    }
}

/// Fully data-driven weapon definition. Balance lives here and nowhere else.
public struct WeaponData: Codable, Identifiable, Sendable {
    public var id: WeaponID
    public var name: String
    public var weaponClass: WeaponClass
    public var fireMode: FireMode
    public var ammoType: AmmoType
    public var rarity: Rarity

    // MARK: Damage
    /// Damage at point blank, before hitbox multiplier and armor.
    public var baseDamage: Float
    /// Damage is `baseDamage` up to `falloffStart`, then lerps to `baseDamage * falloffMinScale` at `falloffEnd`.
    public var falloffStart: Float
    public var falloffEnd: Float
    public var falloffMinScale: Float
    /// How much wall material this round chews through (see `SurfaceKind.penetrationCost`).
    public var penetrationPower: Float
    /// Damage kept after passing through one surface.
    public var penetrationDamageScale: Float
    public var armorPenetration: Float      // 0...1, fraction of damage that ignores armor
    public var headshotMultiplier: Float

    // MARK: Fire
    public var roundsPerMinute: Float
    public var burstCount: Int
    public var burstDelay: Float
    public var pelletsPerShot: Int          // shotguns
    public var magazineSize: Int
    public var reserveAmmo: Int
    public var reloadTime: Float
    public var emptyReloadTime: Float       // includes bolt/charging handle
    /// Shotguns and some LMGs reload one shell at a time.
    public var shellByShellReload: Bool
    public var drawTime: Float
    public var holsterTime: Float
    public var range: Float
    public var muzzleVelocity: Float        // 0 => hitscan

    // MARK: Accuracy / recoil
    public var baseSpread: Float            // radians, hip fire standing still
    public var adsSpread: Float
    public var spreadPerShot: Float
    public var maxSpread: Float
    public var spreadRecovery: Float        // radians per second
    public var moveSpreadPenalty: Float
    public var jumpSpreadPenalty: Float
    public var crouchSpreadBonus: Float     // multiplier < 1
    public var recoilVertical: Float        // radians per shot
    public var recoilHorizontal: Float
    public var recoilRecoverySpeed: Float
    /// Learnable spray pattern (normalized offsets, applied in sequence). Empty => pure random.
    public var sprayPattern: [SprayPoint]

    // MARK: Handling
    public var adsTime: Float
    public var adsZoom: Float               // FOV multiplier while aiming
    public var scopeLevels: [Float]         // sniper variable zoom, empty for iron sights
    public var movementSpeedScale: Float    // while holding this weapon
    public var adsMovementScale: Float
    public var weight: Float                // affects sway and swap feel

    // MARK: Presentation
    public var modelName: String
    public var fireSound: String
    public var reloadSound: String
    public var tracerColorHex: UInt32
    public var muzzleFlashScale: Float
    public var shellEjectDelay: Float
    public var crosshairKind: CrosshairKind
    public var supportedAttachments: [AttachmentSlot]

    // MARK: Economy / unlock
    public var unlockLevel: Int
    public var buyCost: Int                 // in-match buy menu (bomb defusal)
    public var storeCostCoins: Int          // soft currency
    public var storeCostGems: Int           // hard currency, 0 => not sold for gems
    public var killReward: Int

    public init(id: WeaponID, name: String, weaponClass: WeaponClass, fireMode: FireMode, ammoType: AmmoType,
                rarity: Rarity = .common, baseDamage: Float, falloffStart: Float, falloffEnd: Float,
                falloffMinScale: Float = 0.55, penetrationPower: Float = 1, penetrationDamageScale: Float = 0.6,
                armorPenetration: Float = 0.5, headshotMultiplier: Float = 4,
                roundsPerMinute: Float, burstCount: Int = 1, burstDelay: Float = 0.32, pelletsPerShot: Int = 1,
                magazineSize: Int, reserveAmmo: Int, reloadTime: Float, emptyReloadTime: Float? = nil,
                shellByShellReload: Bool = false, drawTime: Float = 0.55, holsterTime: Float = 0.35,
                range: Float = 120, muzzleVelocity: Float = 0,
                baseSpread: Float = 0.02, adsSpread: Float = 0.002, spreadPerShot: Float = 0.004,
                maxSpread: Float = 0.09, spreadRecovery: Float = 0.14, moveSpreadPenalty: Float = 0.018,
                jumpSpreadPenalty: Float = 0.07, crouchSpreadBonus: Float = 0.7,
                recoilVertical: Float = 0.011, recoilHorizontal: Float = 0.004, recoilRecoverySpeed: Float = 7,
                sprayPattern: [SprayPoint] = [], adsTime: Float = 0.25, adsZoom: Float = 1.35,
                scopeLevels: [Float] = [], movementSpeedScale: Float = 1, adsMovementScale: Float = 0.5,
                weight: Float = 1, modelName: String = "", fireSound: String = "", reloadSound: String = "",
                tracerColorHex: UInt32 = 0xFFD27F, muzzleFlashScale: Float = 1, shellEjectDelay: Float = 0.03,
                crosshairKind: CrosshairKind = .cross, supportedAttachments: [AttachmentSlot] = AttachmentSlot.allCases,
                unlockLevel: Int = 1, buyCost: Int = 2500, storeCostCoins: Int = 0, storeCostGems: Int = 0,
                killReward: Int = 300) {
        self.id = id; self.name = name; self.weaponClass = weaponClass; self.fireMode = fireMode
        self.ammoType = ammoType; self.rarity = rarity
        self.baseDamage = baseDamage; self.falloffStart = falloffStart; self.falloffEnd = falloffEnd
        self.falloffMinScale = falloffMinScale; self.penetrationPower = penetrationPower
        self.penetrationDamageScale = penetrationDamageScale; self.armorPenetration = armorPenetration
        self.headshotMultiplier = headshotMultiplier
        self.roundsPerMinute = roundsPerMinute; self.burstCount = burstCount; self.burstDelay = burstDelay
        self.pelletsPerShot = pelletsPerShot; self.magazineSize = magazineSize; self.reserveAmmo = reserveAmmo
        self.reloadTime = reloadTime; self.emptyReloadTime = emptyReloadTime ?? (reloadTime + 0.6)
        self.shellByShellReload = shellByShellReload; self.drawTime = drawTime; self.holsterTime = holsterTime
        self.range = range; self.muzzleVelocity = muzzleVelocity
        self.baseSpread = baseSpread; self.adsSpread = adsSpread; self.spreadPerShot = spreadPerShot
        self.maxSpread = maxSpread; self.spreadRecovery = spreadRecovery; self.moveSpreadPenalty = moveSpreadPenalty
        self.jumpSpreadPenalty = jumpSpreadPenalty; self.crouchSpreadBonus = crouchSpreadBonus
        self.recoilVertical = recoilVertical; self.recoilHorizontal = recoilHorizontal
        self.recoilRecoverySpeed = recoilRecoverySpeed; self.sprayPattern = sprayPattern
        self.adsTime = adsTime; self.adsZoom = adsZoom; self.scopeLevels = scopeLevels
        self.movementSpeedScale = movementSpeedScale; self.adsMovementScale = adsMovementScale; self.weight = weight
        self.modelName = modelName.isEmpty ? id.value : modelName
        self.fireSound = fireSound.isEmpty ? "sfx_\(id.value)_fire" : fireSound
        self.reloadSound = reloadSound.isEmpty ? "sfx_\(id.value)_reload" : reloadSound
        self.tracerColorHex = tracerColorHex; self.muzzleFlashScale = muzzleFlashScale
        self.shellEjectDelay = shellEjectDelay; self.crosshairKind = crosshairKind
        self.supportedAttachments = supportedAttachments
        self.unlockLevel = unlockLevel; self.buyCost = buyCost; self.storeCostCoins = storeCostCoins
        self.storeCostGems = storeCostGems; self.killReward = killReward
    }

    /// Seconds between shots.
    public var fireInterval: Float { 60.0 / max(roundsPerMinute, 1) }

    /// Theoretical damage per second against an unarmored chest.
    public var damagePerSecond: Float {
        let perShot = baseDamage * Float(pelletsPerShot)
        switch fireMode {
        case .burst:
            let burstTime = Float(burstCount - 1) * fireInterval + burstDelay
            return perShot * Float(burstCount) / max(burstTime, 0.01)
        default:
            return perShot / max(fireInterval, 0.01)
        }
    }

    /// Shots needed to kill a target with the given health/armor at point blank.
    public func shotsToKill(health: Float = 100, armor: Float = 0, headshot: Bool = false) -> Int {
        let dmg = DamageModel.resolve(base: baseDamage * Float(pelletsPerShot),
                                      distance: 0,
                                      weapon: self,
                                      hitbox: headshot ? .head : .chest,
                                      armor: armor,
                                      penetratedSurfaces: 0).total
        return dmg > 0 ? Int(ceil(health / dmg)) : 999
    }

    /// 0...100 bars for the loadout UI.
    public var statBars: WeaponStatBars {
        WeaponStatBars(
            damage: MathUtil.clamp(baseDamage * Float(pelletsPerShot) / 1.2, 0, 100),
            fireRate: MathUtil.clamp(roundsPerMinute / 12, 0, 100),
            range: MathUtil.clamp(falloffEnd / 1.2, 0, 100),
            accuracy: MathUtil.clamp(100 - baseSpread * 900, 0, 100),
            mobility: MathUtil.clamp(movementSpeedScale * 85, 0, 100),
            control: MathUtil.clamp(100 - recoilVertical * 3200, 0, 100)
        )
    }
}

public struct WeaponStatBars: Sendable {
    public let damage, fireRate, range, accuracy, mobility, control: Float

    /// Identifiable rather than a tuple so the loadout UI can drive a `ForEach` directly.
    public var stats: [WeaponStat] {
        [WeaponStat(name: "Damage", value: damage),
         WeaponStat(name: "Fire Rate", value: fireRate),
         WeaponStat(name: "Range", value: range),
         WeaponStat(name: "Accuracy", value: accuracy),
         WeaponStat(name: "Mobility", value: mobility),
         WeaponStat(name: "Control", value: control)]
    }

    public func value(named name: String) -> Float {
        stats.first { $0.name == name }?.value ?? 0
    }
}

public struct WeaponStat: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let value: Float
}

/// One entry of a learnable spray pattern, in radians relative to the aim point.
public struct SprayPoint: Codable, Sendable {
    public var up: Float
    public var side: Float
    public init(_ up: Float, _ side: Float) { self.up = up; self.side = side }
}

public enum CrosshairKind: String, Codable, CaseIterable, Sendable {
    case cross, dot, circle, shotgun, sniper, none
}
