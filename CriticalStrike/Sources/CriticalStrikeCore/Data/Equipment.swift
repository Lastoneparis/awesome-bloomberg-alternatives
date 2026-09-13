import Foundation

public enum GrenadeKind: UInt8, Codable, CaseIterable, Sendable {
    case frag = 0, flash, smoke, molotov, decoy, stun, impact

    public var displayName: String {
        switch self {
        case .frag: return "Frag Grenade"
        case .flash: return "Flashbang"
        case .smoke: return "Smoke Grenade"
        case .molotov: return "Molotov"
        case .decoy: return "Decoy"
        case .stun: return "Stun Grenade"
        case .impact: return "Impact Grenade"
        }
    }

    public var slot: LoadoutSlot {
        switch self {
        case .frag, .molotov, .impact: return .lethal
        case .flash, .smoke, .decoy, .stun: return .tactical
        }
    }

    public var iconName: String { "icon_nade_\(String(describing: self))" }
}

public struct GrenadeData: Codable, Identifiable, Sendable {
    public var id: ContentID
    public var kind: GrenadeKind
    public var name: String
    public var fuseTime: Float          // seconds after throw (0 => on impact)
    public var detonateOnImpact: Bool
    public var damage: Float
    public var innerRadius: Float       // full damage inside this radius
    public var outerRadius: Float       // zero damage outside
    public var effectRadius: Float      // flash/smoke/fire area
    public var effectDuration: Float
    public var throwSpeed: Float
    public var lobSpeed: Float          // underhand / short toss
    public var bounciness: Float
    public var friction: Float
    public var maxCarried: Int
    public var buyCost: Int
    public var unlockLevel: Int
    public var selfDamageScale: Float
    public var teamDamageScale: Float
    public var shakesScreen: Bool
    public var blocksVision: Bool

    public init(id: ContentID, kind: GrenadeKind, name: String? = nil, fuseTime: Float,
                detonateOnImpact: Bool = false, damage: Float = 0, innerRadius: Float = 0,
                outerRadius: Float = 0, effectRadius: Float = 0, effectDuration: Float = 0,
                throwSpeed: Float = 18, lobSpeed: Float = 9, bounciness: Float = 0.35,
                friction: Float = 0.55, maxCarried: Int = 1, buyCost: Int = 300,
                unlockLevel: Int = 1, selfDamageScale: Float = 0.65, teamDamageScale: Float = 0.4,
                shakesScreen: Bool = true, blocksVision: Bool = false) {
        self.id = id; self.kind = kind; self.name = name ?? kind.displayName
        self.fuseTime = fuseTime; self.detonateOnImpact = detonateOnImpact
        self.damage = damage; self.innerRadius = innerRadius; self.outerRadius = outerRadius
        self.effectRadius = effectRadius; self.effectDuration = effectDuration
        self.throwSpeed = throwSpeed; self.lobSpeed = lobSpeed; self.bounciness = bounciness
        self.friction = friction; self.maxCarried = maxCarried; self.buyCost = buyCost
        self.unlockLevel = unlockLevel; self.selfDamageScale = selfDamageScale
        self.teamDamageScale = teamDamageScale; self.shakesScreen = shakesScreen
        self.blocksVision = blocksVision
    }
}

public enum GrenadeDatabase {
    public static let all: [GrenadeData] = [
        GrenadeData(id: "nade_frag", kind: .frag, fuseTime: 2.6, damage: 105,
                    innerRadius: 2.2, outerRadius: 8.5, maxCarried: 1, buyCost: 300, unlockLevel: 1),
        GrenadeData(id: "nade_impact", kind: .impact, fuseTime: 4.0, detonateOnImpact: true, damage: 88,
                    innerRadius: 1.8, outerRadius: 6.0, throwSpeed: 24, bounciness: 0.0,
                    maxCarried: 2, buyCost: 300, unlockLevel: 24),
        GrenadeData(id: "nade_flash", kind: .flash, fuseTime: 1.65, damage: 3,
                    innerRadius: 0.8, outerRadius: 2.0, effectRadius: 16, effectDuration: 3.2,
                    maxCarried: 2, buyCost: 200, unlockLevel: 3, shakesScreen: false),
        GrenadeData(id: "nade_stun", kind: .stun, fuseTime: 1.4, damage: 8,
                    innerRadius: 1.0, outerRadius: 4.0, effectRadius: 9, effectDuration: 2.4,
                    maxCarried: 2, buyCost: 200, unlockLevel: 13),
        GrenadeData(id: "nade_smoke", kind: .smoke, fuseTime: 1.9, damage: 0,
                    effectRadius: 5.5, effectDuration: 18, bounciness: 0.2, friction: 0.75,
                    maxCarried: 1, buyCost: 250, unlockLevel: 5, shakesScreen: false, blocksVision: true),
        GrenadeData(id: "nade_molotov", kind: .molotov, fuseTime: 2.2, detonateOnImpact: true, damage: 12,
                    innerRadius: 0.5, outerRadius: 1.0, effectRadius: 4.2, effectDuration: 9,
                    bounciness: 0.0, maxCarried: 1, buyCost: 400, unlockLevel: 8,
                    selfDamageScale: 1.0, teamDamageScale: 0.8, shakesScreen: false),
        GrenadeData(id: "nade_decoy", kind: .decoy, fuseTime: 1.5, damage: 0,
                    effectRadius: 22, effectDuration: 14, maxCarried: 1, buyCost: 150,
                    unlockLevel: 19, shakesScreen: false)
    ]

    private static let index: [ContentID: GrenadeData] = {
        var m = [ContentID: GrenadeData](); for g in all { m[g.id] = g }; return m
    }()

    public static func grenade(_ id: ContentID) -> GrenadeData? { index[id] }
    public static func grenade(kind: GrenadeKind) -> GrenadeData {
        all.first { $0.kind == kind } ?? all[0]
    }
    public static func grenades(forSlot slot: LoadoutSlot) -> [GrenadeData] {
        all.filter { $0.kind.slot == slot }
    }
    public static let defaultLethal: ContentID = "nade_frag"
    public static let defaultTactical: ContentID = "nade_flash"
}

/// Passive perks. Capped at three so builds stay readable.
public struct PerkData: Codable, Identifiable, Sendable {
    public var id: ContentID
    public var name: String
    public var description: String
    public var tier: Int
    public var unlockLevel: Int
    public var storeCostCoins: Int

    public var moveSpeedScale: Float = 1
    public var healthBonus: Float = 0
    public var armorBonus: Float = 0
    public var reloadScale: Float = 1
    public var adsTimeScale: Float = 1
    public var explosiveResistance: Float = 0   // 0...1
    public var flashResistance: Float = 0
    public var footstepVolumeScale: Float = 1
    public var extraMagazines: Int = 0
    public var extraGrenades: Int = 0
    public var regenDelayScale: Float = 1
    public var fallDamageScale: Float = 1
    public var revealsOnKill: Bool = false
    public var silentOnMinimap: Bool = false

    public init(id: ContentID, name: String, description: String, tier: Int, unlockLevel: Int,
                storeCostCoins: Int = 0, moveSpeedScale: Float = 1, healthBonus: Float = 0,
                armorBonus: Float = 0, reloadScale: Float = 1, adsTimeScale: Float = 1,
                explosiveResistance: Float = 0, flashResistance: Float = 0,
                footstepVolumeScale: Float = 1, extraMagazines: Int = 0, extraGrenades: Int = 0,
                regenDelayScale: Float = 1, fallDamageScale: Float = 1,
                revealsOnKill: Bool = false, silentOnMinimap: Bool = false) {
        self.id = id; self.name = name; self.description = description; self.tier = tier
        self.unlockLevel = unlockLevel; self.storeCostCoins = storeCostCoins
        self.moveSpeedScale = moveSpeedScale; self.healthBonus = healthBonus; self.armorBonus = armorBonus
        self.reloadScale = reloadScale; self.adsTimeScale = adsTimeScale
        self.explosiveResistance = explosiveResistance; self.flashResistance = flashResistance
        self.footstepVolumeScale = footstepVolumeScale; self.extraMagazines = extraMagazines
        self.extraGrenades = extraGrenades; self.regenDelayScale = regenDelayScale
        self.fallDamageScale = fallDamageScale; self.revealsOnKill = revealsOnKill
        self.silentOnMinimap = silentOnMinimap
    }
}

public enum PerkDatabase {
    public static let all: [PerkData] = [
        PerkData(id: "perk_lightfoot", name: "Light Foot",
                 description: "Move 7% faster and make almost no noise.", tier: 1, unlockLevel: 2,
                 storeCostCoins: 5000, moveSpeedScale: 1.07, footstepVolumeScale: 0.35),
        PerkData(id: "perk_ghost", name: "Ghost",
                 description: "You never appear on the enemy minimap.", tier: 1, unlockLevel: 15,
                 storeCostCoins: 12000, silentOnMinimap: true),
        PerkData(id: "perk_juggernaut", name: "Juggernaut",
                 description: "+25 armor, but 6% slower.", tier: 1, unlockLevel: 10,
                 storeCostCoins: 9000, moveSpeedScale: 0.94, armorBonus: 25),
        PerkData(id: "perk_scavenger", name: "Scavenger",
                 description: "Start with an extra magazine and pick up ammo from kills.", tier: 2,
                 unlockLevel: 5, storeCostCoins: 6000, extraMagazines: 2),
        PerkData(id: "perk_demolition", name: "Demolition",
                 description: "One extra grenade and 40% explosive resistance.", tier: 2,
                 unlockLevel: 17, storeCostCoins: 11000, explosiveResistance: 0.4, extraGrenades: 1),
        PerkData(id: "perk_resilience", name: "Resilience",
                 description: "Flashbangs blind you for 60% less time.", tier: 2, unlockLevel: 7,
                 storeCostCoins: 7000, flashResistance: 0.6, fallDamageScale: 0.5),
        PerkData(id: "perk_quickhands", name: "Quick Hands",
                 description: "Reload 20% faster and aim 12% faster.", tier: 3, unlockLevel: 4,
                 storeCostCoins: 5500, reloadScale: 0.8, adsTimeScale: 0.88),
        PerkData(id: "perk_regen", name: "Fast Recovery",
                 description: "Health regeneration starts twice as soon.", tier: 3, unlockLevel: 12,
                 storeCostCoins: 8000, regenDelayScale: 0.5),
        PerkData(id: "perk_hunter", name: "Hunter",
                 description: "Killing an enemy reveals nearby enemies for 3 seconds.", tier: 3,
                 unlockLevel: 21, storeCostCoins: 13000, revealsOnKill: true)
    ]

    private static let index: [ContentID: PerkData] = {
        var m = [ContentID: PerkData](); for p in all { m[p.id] = p }; return m
    }()

    public static func perk(_ id: ContentID) -> PerkData? { index[id] }
    public static func perks(tier: Int) -> [PerkData] { all.filter { $0.tier == tier } }
}

public enum PickupKind: UInt8, Codable, CaseIterable, Sendable {
    case ammo = 0, health, armor, weapon, bomb, defuseKit, powerupDamage, powerupSpeed, powerupShield

    public var displayName: String {
        switch self {
        case .ammo: return "Ammo"
        case .health: return "Medkit"
        case .armor: return "Armor Plate"
        case .weapon: return "Weapon"
        case .bomb: return "Bomb"
        case .defuseKit: return "Defuse Kit"
        case .powerupDamage: return "Double Damage"
        case .powerupSpeed: return "Adrenaline"
        case .powerupShield: return "Overshield"
        }
    }

    public var respawnTime: Float {
        switch self {
        case .health, .armor: return 25
        case .ammo: return 15
        case .powerupDamage, .powerupSpeed, .powerupShield: return 60
        default: return 0
        }
    }

    public var powerupDuration: Float {
        switch self {
        case .powerupDamage: return 15
        case .powerupSpeed: return 12
        case .powerupShield: return 20
        default: return 0
        }
    }
}
