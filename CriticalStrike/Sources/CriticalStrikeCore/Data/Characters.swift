import Foundation

/// Operators are cosmetic-plus-flavour: they carry a tiny passive so collecting them matters,
/// but the passives are deliberately small (<=4%) so the game never becomes pay-to-win.
public struct CharacterData: Codable, Identifiable, Sendable {
    public var id: CharacterID
    public var name: String
    public var callsign: String
    public var team: Team          // .none => usable by both sides
    public var rarity: Rarity
    public var bio: String
    public var modelName: String
    public var voicePack: String
    public var unlockLevel: Int
    public var storeCostCoins: Int
    public var storeCostGems: Int

    // Micro-passives
    public var moveSpeedScale: Float
    public var healthBonus: Float
    public var reloadScale: Float
    public var hitboxScale: Float   // cosmetic body size, kept at 1.0 for fairness

    public init(id: CharacterID, name: String, callsign: String, team: Team, rarity: Rarity,
                bio: String, modelName: String = "", voicePack: String = "vo_default",
                unlockLevel: Int = 1, storeCostCoins: Int = 0, storeCostGems: Int = 0,
                moveSpeedScale: Float = 1, healthBonus: Float = 0, reloadScale: Float = 1,
                hitboxScale: Float = 1) {
        self.id = id; self.name = name; self.callsign = callsign; self.team = team
        self.rarity = rarity; self.bio = bio
        self.modelName = modelName.isEmpty ? "chr_\(id.value)" : modelName
        self.voicePack = voicePack; self.unlockLevel = unlockLevel
        self.storeCostCoins = storeCostCoins; self.storeCostGems = storeCostGems
        self.moveSpeedScale = moveSpeedScale; self.healthBonus = healthBonus
        self.reloadScale = reloadScale; self.hitboxScale = hitboxScale
    }
}

public enum CharacterDatabase {
    public static let all: [CharacterData] = [
        CharacterData(id: "chr_recruit_strike", name: "Recruit", callsign: "ROOKIE", team: .strike,
                      rarity: .common, bio: "Standard issue Strike Force operator.",
                      voicePack: "vo_strike_male_a", unlockLevel: 1),
        CharacterData(id: "chr_recruit_shield", name: "Recruit", callsign: "ROOKIE", team: .shield,
                      rarity: .common, bio: "Standard issue Shield Corps operator.",
                      voicePack: "vo_shield_male_a", unlockLevel: 1),
        CharacterData(id: "chr_vector", name: "Vector", callsign: "VCTR", team: .strike, rarity: .rare,
                      bio: "Ex-recon. Moves before anyone hears her.",
                      voicePack: "vo_strike_female_a", unlockLevel: 8, storeCostCoins: 18000,
                      moveSpeedScale: 1.03),
        CharacterData(id: "chr_anvil", name: "Anvil", callsign: "ANVL", team: .shield, rarity: .rare,
                      bio: "Breacher. Walks through doors that were not there before.",
                      voicePack: "vo_shield_male_b", unlockLevel: 8, storeCostCoins: 18000,
                      healthBonus: 5),
        CharacterData(id: "chr_mirage", name: "Mirage", callsign: "MRGE", team: .none, rarity: .epic,
                      bio: "Nobody has ever confirmed which side she actually works for.",
                      voicePack: "vo_neutral_female_a", unlockLevel: 20, storeCostGems: 2400,
                      moveSpeedScale: 1.02, reloadScale: 0.96),
        CharacterData(id: "chr_reaper", name: "Reaper", callsign: "RPR", team: .strike, rarity: .legendary,
                      bio: "Counted in confirmed kills, not in years of service.",
                      voicePack: "vo_strike_male_c", unlockLevel: 35, storeCostGems: 3600,
                      moveSpeedScale: 1.02, healthBonus: 5),
        CharacterData(id: "chr_sentinel", name: "Sentinel", callsign: "SNTL", team: .shield,
                      rarity: .legendary, bio: "Has held the same corridor for eleven years.",
                      voicePack: "vo_shield_female_b", unlockLevel: 35, storeCostGems: 3600,
                      healthBonus: 8, reloadScale: 0.97),
        CharacterData(id: "chr_nocturne", name: "Nocturne", callsign: "NOCT", team: .none, rarity: .mythic,
                      bio: "Season 1 apex reward. Only awarded, never sold.",
                      voicePack: "vo_neutral_male_b", unlockLevel: 50,
                      moveSpeedScale: 1.03, healthBonus: 5, reloadScale: 0.95)
    ]

    private static let index: [CharacterID: CharacterData] = {
        var m = [CharacterID: CharacterData](); for c in all { m[c.id] = c }; return m
    }()

    public static func character(_ id: CharacterID) -> CharacterData? { index[id] }
    public static func characters(for team: Team) -> [CharacterData] {
        all.filter { $0.team == team || $0.team == .none }
    }
    public static func defaultCharacter(for team: Team) -> CharacterData {
        characters(for: team).first ?? all[0]
    }
}

// MARK: - Cosmetics

public enum CosmeticKind: String, Codable, CaseIterable, Sendable {
    case weaponSkin, characterSkin, charm, sticker, sprayTag, emote, banner, title, killEffect, tracerColor

    public var displayName: String {
        switch self {
        case .weaponSkin: return "Weapon Skin"
        case .characterSkin: return "Operator Skin"
        case .charm: return "Charm"
        case .sticker: return "Sticker"
        case .sprayTag: return "Spray"
        case .emote: return "Emote"
        case .banner: return "Banner"
        case .title: return "Title"
        case .killEffect: return "Kill Effect"
        case .tracerColor: return "Tracer"
        }
    }
}

public struct CosmeticData: Codable, Identifiable, Sendable {
    public var id: SkinID
    public var name: String
    public var kind: CosmeticKind
    public var rarity: Rarity
    public var appliesTo: ContentID?      // weapon or character id; nil => universal
    public var materialName: String
    public var tintHex: UInt32
    public var hasAnimatedShader: Bool
    public var storeCostCoins: Int
    public var storeCostGems: Int
    public var crateOnly: Bool
    public var seasonID: Int?
    public var statTrakEnabled: Bool      // tracks kills on the item

    public init(id: SkinID, name: String, kind: CosmeticKind, rarity: Rarity,
                appliesTo: ContentID? = nil, materialName: String = "", tintHex: UInt32 = 0xFFFFFF,
                hasAnimatedShader: Bool = false, storeCostCoins: Int = 0, storeCostGems: Int = 0,
                crateOnly: Bool = false, seasonID: Int? = nil, statTrakEnabled: Bool = false) {
        self.id = id; self.name = name; self.kind = kind; self.rarity = rarity
        self.appliesTo = appliesTo
        self.materialName = materialName.isEmpty ? "mat_\(id.value)" : materialName
        self.tintHex = tintHex; self.hasAnimatedShader = hasAnimatedShader
        self.storeCostCoins = storeCostCoins; self.storeCostGems = storeCostGems
        self.crateOnly = crateOnly; self.seasonID = seasonID; self.statTrakEnabled = statTrakEnabled
    }
}

public enum CosmeticDatabase {
    public static let all: [CosmeticData] = [
        // Weapon skins — Vanguard
        CosmeticData(id: "skin_vanguard_urban", name: "Urban Fracture", kind: .weaponSkin, rarity: .uncommon,
                     appliesTo: "ar_vanguard", tintHex: 0x6E7B8B, storeCostCoins: 9000),
        CosmeticData(id: "skin_vanguard_crimson", name: "Crimson Vow", kind: .weaponSkin, rarity: .rare,
                     appliesTo: "ar_vanguard", tintHex: 0xB4232B, storeCostCoins: 22000, statTrakEnabled: true),
        CosmeticData(id: "skin_vanguard_hydra", name: "Hydra", kind: .weaponSkin, rarity: .epic,
                     appliesTo: "ar_vanguard", tintHex: 0x1FA97A, hasAnimatedShader: true,
                     storeCostGems: 1600, statTrakEnabled: true),
        CosmeticData(id: "skin_vanguard_dragonlord", name: "Dragonlord", kind: .weaponSkin, rarity: .legendary,
                     appliesTo: "ar_vanguard", tintHex: 0xFFB300, hasAnimatedShader: true,
                     crateOnly: true, seasonID: 1, statTrakEnabled: true),
        // Weapon skins — other guns
        CosmeticData(id: "skin_wasp_neon", name: "Neon Sting", kind: .weaponSkin, rarity: .rare,
                     appliesTo: "smg_wasp", tintHex: 0x28E0FF, hasAnimatedShader: true, storeCostCoins: 20000),
        CosmeticData(id: "skin_longbow_phantom", name: "Phantom Glass", kind: .weaponSkin, rarity: .epic,
                     appliesTo: "snp_longbow", tintHex: 0x8E7BFF, storeCostGems: 1900, statTrakEnabled: true),
        CosmeticData(id: "skin_magnum_gold", name: "Gilded Hand", kind: .weaponSkin, rarity: .legendary,
                     appliesTo: "pst_magnum", tintHex: 0xFFD54F, storeCostGems: 2800, statTrakEnabled: true),
        CosmeticData(id: "skin_karambit_fade", name: "Fade", kind: .weaponSkin, rarity: .mythic,
                     appliesTo: "mel_karambit", tintHex: 0xFF6FD8, hasAnimatedShader: true,
                     crateOnly: true, seasonID: 1, statTrakEnabled: true),
        // Operator skins
        CosmeticData(id: "skin_chr_vector_arctic", name: "Vector — Arctic", kind: .characterSkin,
                     rarity: .rare, appliesTo: "chr_vector", tintHex: 0xE8F1F8, storeCostCoins: 24000),
        CosmeticData(id: "skin_chr_reaper_void", name: "Reaper — Void", kind: .characterSkin,
                     rarity: .legendary, appliesTo: "chr_reaper", tintHex: 0x2B0B45,
                     hasAnimatedShader: true, storeCostGems: 3200),
        // Universal
        CosmeticData(id: "charm_luckycoin", name: "Lucky Coin", kind: .charm, rarity: .uncommon,
                     storeCostCoins: 4000),
        CosmeticData(id: "charm_skull", name: "Tiny Skull", kind: .charm, rarity: .rare,
                     storeCostCoins: 8000),
        CosmeticData(id: "spray_gg", name: "GG", kind: .sprayTag, rarity: .common, storeCostCoins: 1500),
        CosmeticData(id: "spray_headshot", name: "Headshot Only", kind: .sprayTag, rarity: .rare,
                     storeCostCoins: 6000),
        CosmeticData(id: "emote_dance", name: "Victory Dance", kind: .emote, rarity: .epic,
                     storeCostGems: 900),
        CosmeticData(id: "banner_season1", name: "Season 1 Banner", kind: .banner, rarity: .rare,
                     seasonID: 1),
        CosmeticData(id: "title_untouchable", name: "Untouchable", kind: .title, rarity: .epic),
        CosmeticData(id: "killfx_ash", name: "Ash Dissolve", kind: .killEffect, rarity: .legendary,
                     hasAnimatedShader: true, storeCostGems: 2200),
        CosmeticData(id: "tracer_plasma", name: "Plasma Tracer", kind: .tracerColor, rarity: .epic,
                     tintHex: 0x49F2FF, storeCostGems: 1100)
    ]

    private static let index: [SkinID: CosmeticData] = {
        var m = [SkinID: CosmeticData](); for c in all { m[c.id] = c }; return m
    }()

    public static func cosmetic(_ id: SkinID) -> CosmeticData? { index[id] }
    public static func cosmetics(of kind: CosmeticKind) -> [CosmeticData] { all.filter { $0.kind == kind } }
    public static func skins(forWeapon id: WeaponID) -> [CosmeticData] {
        all.filter { $0.kind == .weaponSkin && $0.appliesTo == id }
    }
    public static func skins(forCharacter id: CharacterID) -> [CosmeticData] {
        all.filter { $0.kind == .characterSkin && $0.appliesTo == id }
    }
    public static func crateContents(season: Int) -> [CosmeticData] {
        all.filter { $0.seasonID == season || $0.crateOnly }
    }
}
