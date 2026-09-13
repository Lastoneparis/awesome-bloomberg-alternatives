import Foundation

/// A loot crate. Odds are published (App Store guideline 3.1.1 requires it) and are
/// implemented exactly as published — the weights below are the odds shown in the UI,
/// with a pity timer that only ever improves them.
public struct LootCrate: Identifiable, Codable, Sendable {
    public var id: ContentID
    public var name: String
    public var description: String
    public var priceCoins: Int
    public var priceGems: Int
    public var itemCount: Int
    public var guaranteedMinimumRarity: Rarity
    public var pool: [SkinID]
    public var seasonID: Int?
    /// After this many opens without an epic-or-better, the next one is guaranteed.
    public var pityThreshold: Int

    public init(id: ContentID, name: String, description: String, priceCoins: Int = 0,
                priceGems: Int = 0, itemCount: Int = 1,
                guaranteedMinimumRarity: Rarity = .common, pool: [SkinID] = [],
                seasonID: Int? = nil, pityThreshold: Int = 20) {
        self.id = id; self.name = name; self.description = description
        self.priceCoins = priceCoins; self.priceGems = priceGems
        self.itemCount = itemCount; self.guaranteedMinimumRarity = guaranteedMinimumRarity
        self.pool = pool; self.seasonID = seasonID; self.pityThreshold = pityThreshold
    }

    /// Published odds for this crate, as percentages summing to 100.
    public func publishedOdds() -> [(rarity: Rarity, percent: Double)] {
        let rarities = Rarity.allCases.filter { $0 >= guaranteedMinimumRarity }
        let total = rarities.reduce(Double(0)) { $0 + Double($1.dropWeight) }
        return rarities.map { ($0, Double($0.dropWeight) / total * 100) }
    }
}

public struct CrateReward: Sendable {
    public var cosmetic: SkinID
    public var rarity: Rarity
    public var isDuplicate: Bool
    /// Duplicates convert to credits instead of clogging the inventory.
    public var compensationCoins: Int
}

public enum LootCrateDatabase {
    public static let all: [LootCrate] = [
        LootCrate(id: "crate_supply", name: "Supply Crate",
                  description: "Standard issue. Weapon skins, charms and sprays.",
                  priceCoins: 12000, itemCount: 1,
                  pool: CosmeticDatabase.all.filter { $0.rarity <= .epic }.map(\.id),
                  pityThreshold: 20),
        LootCrate(id: "crate_elite", name: "Elite Crate",
                  description: "Rare or better, guaranteed. Higher legendary odds.",
                  priceGems: 900, itemCount: 1, guaranteedMinimumRarity: .rare,
                  pool: CosmeticDatabase.all.filter { $0.rarity >= .rare }.map(\.id),
                  pityThreshold: 12),
        LootCrate(id: "crate_season1", name: "Season 1 Crate",
                  description: "This season's collection, including Dragonlord and Fade.",
                  priceGems: 1200, itemCount: 1, guaranteedMinimumRarity: .uncommon,
                  pool: CosmeticDatabase.crateContents(season: 1).map(\.id),
                  seasonID: 1, pityThreshold: 15)
    ]

    public static func crate(_ id: ContentID) -> LootCrate? { all.first { $0.id == id } }
}

/// Opens crates. Kept in the core (not the UI) so the odds are testable and identical on
/// every platform, and so a server can validate a client-reported opening.
public final class LootBoxService {
    public private(set) var pityCounters: [ContentID: Int] = [:]
    private var rng: DeterministicRandom

    public init(seed: UInt64 = UInt64(Date().timeIntervalSince1970)) {
        rng = DeterministicRandom(seed: seed)
    }

    public func restore(pity: [ContentID: Int]) { pityCounters = pity }

    public func open(_ crate: LootCrate, owned: Set<SkinID>) -> [CrateReward] {
        var rewards: [CrateReward] = []
        for _ in 0..<max(1, crate.itemCount) {
            let pity = pityCounters[crate.id, default: 0]
            let forceHighRarity = pity >= crate.pityThreshold
            let rarity = rollRarity(crate: crate, forceHighRarity: forceHighRarity)

            if rarity >= .epic {
                pityCounters[crate.id] = 0
            } else {
                pityCounters[crate.id] = pity + 1
            }

            let candidates = crate.pool.compactMap { CosmeticDatabase.cosmetic($0) }
                .filter { $0.rarity == rarity }
            let fallback = crate.pool.compactMap { CosmeticDatabase.cosmetic($0) }
            let chosen = rng.pick(candidates.isEmpty ? fallback : candidates)
            guard let item = chosen else { continue }
            let duplicate = owned.contains(item.id)
            rewards.append(CrateReward(cosmetic: item.id, rarity: item.rarity,
                                       isDuplicate: duplicate,
                                       compensationCoins: duplicate ? item.rarity.dismantleValue : 0))
        }
        return rewards
    }

    private func rollRarity(crate: LootCrate, forceHighRarity: Bool) -> Rarity {
        let available = Rarity.allCases.filter {
            $0 >= crate.guaranteedMinimumRarity && (!forceHighRarity || $0 >= .epic)
        }
        guard !available.isEmpty else { return crate.guaranteedMinimumRarity }
        let total = available.reduce(Float(0)) { $0 + $1.dropWeight }
        var roll = rng.unit() * total
        for rarity in available {
            roll -= rarity.dropWeight
            if roll <= 0 { return rarity }
        }
        return available.last ?? .common
    }

    /// How many opens until the pity guarantee fires — shown in the UI so the system is honest.
    public func opensUntilGuarantee(_ crate: LootCrate) -> Int {
        max(0, crate.pityThreshold - pityCounters[crate.id, default: 0])
    }
}
