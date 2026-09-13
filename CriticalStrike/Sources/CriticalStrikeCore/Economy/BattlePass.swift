import Foundation

public enum RewardKind: Codable, Sendable, Equatable {
    case currency(CurrencyKind, Int)
    case cosmetic(SkinID)
    case character(CharacterID)
    case weapon(WeaponID)
    case attachment(AttachmentID)
    case crate(ContentID)
    case xpBoost(hours: Int, multiplier: Float)

    public var displayName: String {
        switch self {
        case let .currency(kind, amount): return "\(amount) \(kind.displayName)"
        case let .cosmetic(id): return CosmeticDatabase.cosmetic(id)?.name ?? id.value
        case let .character(id): return CharacterDatabase.character(id)?.name ?? id.value
        case let .weapon(id): return WeaponDatabase.weapon(id)?.name ?? id.value
        case let .attachment(id): return AttachmentDatabase.attachment(id)?.name ?? id.value
        case let .crate(id): return LootCrateDatabase.crate(id)?.name ?? id.value
        case let .xpBoost(hours, multiplier): return "\(Int(multiplier))x XP for \(hours)h"
        }
    }

    public var rarity: Rarity {
        switch self {
        case let .cosmetic(id): return CosmeticDatabase.cosmetic(id)?.rarity ?? .common
        case let .character(id): return CharacterDatabase.character(id)?.rarity ?? .common
        case let .weapon(id): return WeaponDatabase.weapon(id)?.rarity ?? .common
        case .crate: return .rare
        default: return .common
        }
    }
}

public struct BattlePassTier: Identifiable, Codable, Sendable {
    public var id: Int { tier }
    public var tier: Int
    public var xpRequired: Int
    public var freeReward: RewardKind?
    public var premiumReward: RewardKind?

    public init(tier: Int, xpRequired: Int, freeReward: RewardKind?, premiumReward: RewardKind?) {
        self.tier = tier; self.xpRequired = xpRequired
        self.freeReward = freeReward; self.premiumReward = premiumReward
    }
}

public struct BattlePassSeason: Codable, Sendable {
    public var seasonID: Int
    public var name: String
    public var theme: String
    public var startDate: Date
    public var endDate: Date
    public var tiers: [BattlePassTier]
    public var xpPerTier: Int
    public var premiumProductID: ProductID

    public var totalTiers: Int { tiers.count }

    public func isActive(on date: Date = Date()) -> Bool {
        date >= startDate && date <= endDate
    }

    public func daysRemaining(from date: Date = Date()) -> Int {
        max(0, Int(endDate.timeIntervalSince(date) / 86400))
    }
}

public struct BattlePassProgress: Codable, Equatable, Sendable {
    public var seasonID: Int
    public var xp: Int
    public var isPremium: Bool
    public var claimedFreeTiers: Set<Int>
    public var claimedPremiumTiers: Set<Int>

    public init(seasonID: Int, xp: Int = 0, isPremium: Bool = false,
                claimedFreeTiers: Set<Int> = [], claimedPremiumTiers: Set<Int> = []) {
        self.seasonID = seasonID; self.xp = xp; self.isPremium = isPremium
        self.claimedFreeTiers = claimedFreeTiers; self.claimedPremiumTiers = claimedPremiumTiers
    }

    public func currentTier(in season: BattlePassSeason) -> Int {
        min(season.totalTiers, xp / max(1, season.xpPerTier) + 1)
    }

    public func progressWithinTier(in season: BattlePassSeason) -> Float {
        let within = xp % max(1, season.xpPerTier)
        return Float(within) / Float(max(1, season.xpPerTier))
    }

    public func unclaimedRewards(in season: BattlePassSeason) -> [(tier: Int, reward: RewardKind, premium: Bool)] {
        let tier = currentTier(in: season)
        var out: [(Int, RewardKind, Bool)] = []
        for t in season.tiers where t.tier <= tier {
            if let free = t.freeReward, !claimedFreeTiers.contains(t.tier) {
                out.append((t.tier, free, false))
            }
            if isPremium, let premium = t.premiumReward, !claimedPremiumTiers.contains(t.tier) {
                out.append((t.tier, premium, true))
            }
        }
        return out.map { (tier: $0.0, reward: $0.1, premium: $0.2) }
    }
}

public enum BattlePassDatabase {
    /// Season 1. 100 tiers, 1,200 XP each — about 45 hours of play for a free player,
    /// which is the standard season length for a 10-week season.
    public static let season1: BattlePassSeason = {
        var tiers: [BattlePassTier] = []
        let cosmetics = CosmeticDatabase.all.filter { $0.seasonID == 1 || $0.rarity >= .rare }

        for tier in 1...100 {
            var free: RewardKind?
            var premium: RewardKind?

            // Free track: currency every few tiers plus a handful of real items.
            switch tier % 10 {
            case 0: free = .currency(.gems, 50)
            case 5: free = .currency(.coins, 2500)
            case 3: free = .currency(.tokens, 100)
            case 7 where tier > 20: free = .crate("crate_supply")
            default: free = tier % 2 == 0 ? .currency(.coins, 800) : nil
            }

            // Premium track: something every tier, big items on the tens.
            if tier % 10 == 0 {
                let index = (tier / 10 - 1) % max(1, cosmetics.count)
                premium = .cosmetic(cosmetics[index].id)
            } else if tier % 5 == 0 {
                premium = .crate("crate_elite")
            } else if tier % 3 == 0 {
                premium = .currency(.gems, 40)
            } else {
                premium = .currency(.coins, 1500)
            }

            // Signature rewards.
            if tier == 25 { premium = .weapon("smg_viper") }
            if tier == 50 { premium = .character("chr_mirage") }
            if tier == 75 { premium = .cosmetic("skin_vanguard_dragonlord") }
            if tier == 100 {
                premium = .character("chr_nocturne")
                free = .cosmetic("banner_season1")
            }

            tiers.append(BattlePassTier(tier: tier, xpRequired: tier * 1200,
                                        freeReward: free, premiumReward: premium))
        }

        let start = Date(timeIntervalSince1970: 1_767_225_600)   // 1 Jan 2026
        return BattlePassSeason(seasonID: 1, name: "Season 1: Blacksite",
                                theme: "blacksite", startDate: start,
                                endDate: start.addingTimeInterval(70 * 86400),
                                tiers: tiers, xpPerTier: 1200,
                                premiumProductID: "iap_battlepass")
    }()

    public static var currentSeason: BattlePassSeason { season1 }
}
