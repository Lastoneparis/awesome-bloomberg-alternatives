import Foundation

/// An App Store product. `productID` matches the identifier configured in App Store
/// Connect; the app layer resolves the localized price through StoreKit at runtime, and
/// the values here are only used for layout and sorting before that resolves.
public struct IAPProduct: Identifiable, Codable, Sendable {
    public enum Category: String, Codable, Sendable {
        case currency, bundle, subscription, removeAds, battlePass, starterPack
    }

    public var id: ProductID
    public var productID: String
    public var name: String
    public var subtitle: String
    public var category: Category
    public var gems: Int
    public var coins: Int
    public var bonusPercent: Int
    public var grantsCosmetics: [SkinID]
    public var grantsCharacters: [CharacterID]
    public var grantsBattlePassPremium: Bool
    public var isConsumable: Bool
    public var isSubscription: Bool
    public var subscriptionPeriodDays: Int
    public var displayPriceUSD: Double
    public var bestValue: Bool
    public var limitedTime: Bool
    public var purchaseLimit: Int      // 0 = unlimited
    public var sortOrder: Int

    public init(id: ProductID, productID: String, name: String, subtitle: String = "",
                category: Category, gems: Int = 0, coins: Int = 0, bonusPercent: Int = 0,
                grantsCosmetics: [SkinID] = [], grantsCharacters: [CharacterID] = [],
                grantsBattlePassPremium: Bool = false, isConsumable: Bool = true,
                isSubscription: Bool = false, subscriptionPeriodDays: Int = 0,
                displayPriceUSD: Double, bestValue: Bool = false, limitedTime: Bool = false,
                purchaseLimit: Int = 0, sortOrder: Int = 0) {
        self.id = id; self.productID = productID; self.name = name; self.subtitle = subtitle
        self.category = category; self.gems = gems; self.coins = coins
        self.bonusPercent = bonusPercent; self.grantsCosmetics = grantsCosmetics
        self.grantsCharacters = grantsCharacters
        self.grantsBattlePassPremium = grantsBattlePassPremium
        self.isConsumable = isConsumable; self.isSubscription = isSubscription
        self.subscriptionPeriodDays = subscriptionPeriodDays
        self.displayPriceUSD = displayPriceUSD; self.bestValue = bestValue
        self.limitedTime = limitedTime; self.purchaseLimit = purchaseLimit
        self.sortOrder = sortOrder
    }

    public var gemsPerDollar: Double {
        displayPriceUSD > 0 ? Double(gems) / displayPriceUSD : 0
    }
}

public enum StoreCatalog {
    public static let bundleIdentifier = "game.criticalstrike.ios"

    public static let products: [IAPProduct] = [
        // ── Gem packs (consumable) ──
        IAPProduct(id: "iap_gems_tiny", productID: "\(bundleIdentifier).gems.300",
                   name: "Handful of Gems", subtitle: "300 Gems",
                   category: .currency, gems: 300, displayPriceUSD: 1.99, sortOrder: 10),
        IAPProduct(id: "iap_gems_small", productID: "\(bundleIdentifier).gems.800",
                   name: "Pouch of Gems", subtitle: "800 Gems +60 bonus",
                   category: .currency, gems: 860, bonusPercent: 8,
                   displayPriceUSD: 4.99, sortOrder: 20),
        IAPProduct(id: "iap_gems_medium", productID: "\(bundleIdentifier).gems.1800",
                   name: "Crate of Gems", subtitle: "1,800 Gems +250 bonus",
                   category: .currency, gems: 2050, bonusPercent: 14,
                   displayPriceUSD: 9.99, sortOrder: 30),
        IAPProduct(id: "iap_gems_large", productID: "\(bundleIdentifier).gems.4000",
                   name: "Case of Gems", subtitle: "4,000 Gems +800 bonus",
                   category: .currency, gems: 4800, bonusPercent: 20,
                   displayPriceUSD: 19.99, bestValue: true, sortOrder: 40),
        IAPProduct(id: "iap_gems_huge", productID: "\(bundleIdentifier).gems.10000",
                   name: "Vault of Gems", subtitle: "10,000 Gems +3,000 bonus",
                   category: .currency, gems: 13000, bonusPercent: 30,
                   displayPriceUSD: 49.99, sortOrder: 50),

        // ── Bundles ──
        IAPProduct(id: "iap_starter", productID: "\(bundleIdentifier).pack.starter",
                   name: "Starter Pack", subtitle: "800 Gems, 20,000 Credits, Urban Fracture skin",
                   category: .starterPack, gems: 800, coins: 20000,
                   grantsCosmetics: ["skin_vanguard_urban"],
                   isConsumable: false, displayPriceUSD: 4.99,
                   bestValue: true, limitedTime: true, purchaseLimit: 1, sortOrder: 5),
        IAPProduct(id: "iap_reaper_bundle", productID: "\(bundleIdentifier).pack.reaper",
                   name: "Reaper Operator Bundle", subtitle: "Reaper, Void skin, 1,200 Gems",
                   category: .bundle, gems: 1200,
                   grantsCosmetics: ["skin_chr_reaper_void"], grantsCharacters: ["chr_reaper"],
                   isConsumable: false, displayPriceUSD: 14.99, sortOrder: 60),
        IAPProduct(id: "iap_dragonlord", productID: "\(bundleIdentifier).pack.dragonlord",
                   name: "Dragonlord Collection", subtitle: "Legendary rifle skin + charm + spray",
                   category: .bundle, coins: 5000,
                   grantsCosmetics: ["skin_vanguard_dragonlord", "charm_skull", "spray_headshot"],
                   isConsumable: false, displayPriceUSD: 19.99, limitedTime: true, sortOrder: 70),

        // ── Battle pass ──
        IAPProduct(id: "iap_battlepass", productID: "\(bundleIdentifier).battlepass.season",
                   name: "Season Pass", subtitle: "Unlock the premium reward track",
                   category: .battlePass, grantsBattlePassPremium: true,
                   isConsumable: true, displayPriceUSD: 9.99, sortOrder: 1),
        IAPProduct(id: "iap_battlepass_plus", productID: "\(bundleIdentifier).battlepass.bundle",
                   name: "Season Pass + 25 Tiers", subtitle: "Skip straight to the good stuff",
                   category: .battlePass, gems: 300, grantsBattlePassPremium: true,
                   isConsumable: true, displayPriceUSD: 24.99, sortOrder: 2),

        // ── Non-consumable ──
        IAPProduct(id: "iap_removeads", productID: "\(bundleIdentifier).removeads",
                   name: "Remove Ads", subtitle: "No interstitials, keep the reward videos",
                   category: .removeAds, isConsumable: false,
                   displayPriceUSD: 3.99, purchaseLimit: 1, sortOrder: 3),

        // ── Subscription ──
        IAPProduct(id: "iap_vip", productID: "\(bundleIdentifier).sub.vip.monthly",
                   name: "VIP Membership", subtitle: "+25% XP and credits, 150 Gems daily, no ads",
                   category: .subscription, gems: 0, isConsumable: false,
                   isSubscription: true, subscriptionPeriodDays: 30,
                   displayPriceUSD: 7.99, sortOrder: 4)
    ]

    private static let index: [ProductID: IAPProduct] = {
        var m = [ProductID: IAPProduct](); for p in products { m[p.id] = p }; return m
    }()

    public static func product(_ id: ProductID) -> IAPProduct? { index[id] }
    public static func product(storeKitID: String) -> IAPProduct? {
        products.first { $0.productID == storeKitID }
    }
    public static func products(in category: IAPProduct.Category) -> [IAPProduct] {
        products.filter { $0.category == category }.sorted { $0.sortOrder < $1.sortOrder }
    }
    public static var allStoreKitIdentifiers: [String] { products.map(\.productID) }
    public static var subscriptionIdentifiers: [String] {
        products.filter(\.isSubscription).map(\.productID)
    }
    public static var nonConsumableIdentifiers: [String] {
        products.filter { !$0.isConsumable && !$0.isSubscription }.map(\.productID)
    }

    /// VIP benefits, applied wherever rewards are calculated.
    public static let vipXPMultiplier: Float = 1.25
    public static let vipCoinMultiplier: Float = 1.25
    public static let vipDailyGems = 150
}

/// The in-game shop (soft/hard currency, not App Store). Rotates daily on a seed derived
/// from the date so every player sees the same offers without a server round trip.
public struct ShopRotation: Sendable {
    public struct Offer: Identifiable, Sendable {
        public var id: SkinID { item }
        public var item: SkinID
        public var priceCoins: Int
        public var priceGems: Int
        public var discountPercent: Int
        public var featured: Bool
    }

    public var dayIndex: Int
    public var offers: [Offer]
    public var featured: [Offer]
    public var expiresIn: TimeInterval

    public static func current(date: Date = Date()) -> ShopRotation {
        let day = Int(date.timeIntervalSince1970 / 86400)
        var rng = DeterministicRandom(seed: UInt64(day) &* 0x9E3779B97F4A7C15)
        let pool = CosmeticDatabase.all.filter { !$0.crateOnly }
        let shuffled = rng.shuffled(pool)

        func makeOffer(_ cosmetic: CosmeticData, featured: Bool) -> Offer {
            let discount = rng.chance(0.35) ? [10, 20, 25, 30][rng.int(in: 0...3)] : 0
            let coins = cosmetic.storeCostCoins * (100 - discount) / 100
            let gems = cosmetic.storeCostGems * (100 - discount) / 100
            return Offer(item: cosmetic.id, priceCoins: coins, priceGems: gems,
                         discountPercent: discount, featured: featured)
        }

        let featuredItems = shuffled.prefix(2).map { makeOffer($0, featured: true) }
        let dailyItems = shuffled.dropFirst(2).prefix(6).map { makeOffer($0, featured: false) }

        let secondsIntoDay = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400)
        return ShopRotation(dayIndex: day, offers: Array(dailyItems),
                            featured: Array(featuredItems), expiresIn: 86400 - secondsIntoDay)
    }
}
