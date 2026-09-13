import Foundation

/// Everything persisted about a player. Versioned so a shipped save can be migrated
/// rather than thrown away when the schema changes.
public struct PlayerProfile: Codable, Equatable, Sendable {
    public static let currentVersion = 3

    public var version: Int
    public var accountID: String
    public var displayName: String
    public var createdAt: Date
    public var lastPlayedAt: Date

    public var totalXP: Int
    public var prestige: Int
    public var competitiveRating: Int
    public var wallet: Wallet
    public var unlocks: UnlockState
    public var stats: PlayerStats

    public var loadouts: [Loadout]
    public var selectedLoadoutIndex: Int
    public var equippedBanner: SkinID?
    public var equippedTitle: SkinID?
    public var equippedEmote: SkinID?
    public var equippedSpray: SkinID?

    public var battlePass: BattlePassProgress
    public var missionProgress: [MissionID: MissionProgress]
    public var missionsAssignedAt: Date
    public var lootPity: [ContentID: Int]

    public var entitlements: Entitlements
    public var settings: GameSettings
    public var friendCodes: [String]
    public var clanTag: String?
    public var hasSeenTutorial: Bool
    public var dailyRewardStreak: Int
    public var lastDailyRewardAt: Date?

    public init(accountID: String = UUID().uuidString, displayName: String = "Operator") {
        version = PlayerProfile.currentVersion
        self.accountID = accountID
        self.displayName = displayName
        createdAt = Date()
        lastPlayedAt = Date()
        totalXP = 0
        prestige = 0
        competitiveRating = 1000
        wallet = Wallet(coins: 5000, gems: 0, tokens: 0)
        unlocks = UnlockState()
        stats = PlayerStats()
        loadouts = Loadout.defaultSet()
        selectedLoadoutIndex = 0
        battlePass = BattlePassProgress(seasonID: BattlePassDatabase.currentSeason.seasonID)
        missionProgress = [:]
        missionsAssignedAt = .distantPast
        lootPity = [:]
        entitlements = Entitlements()
        settings = GameSettings()
        friendCodes = []
        hasSeenTutorial = false
        dailyRewardStreak = 0
    }

    // MARK: Derived

    public var level: Int { XPCurve.level(forTotalXP: totalXP) }
    public var levelProgress: (level: Int, current: Int, required: Int, fraction: Float) {
        XPCurve.progress(totalXP: totalXP)
    }
    public var rank: CompetitiveRank { CompetitiveRank.rank(forRating: competitiveRating) }
    public var rankDivision: Int { CompetitiveRank.division(forRating: competitiveRating) }
    public var isPremium: Bool { entitlements.hasActiveVIP }
    public var selectedLoadout: Loadout {
        loadouts.indices.contains(selectedLoadoutIndex)
            ? loadouts[selectedLoadoutIndex] : Loadout.starter()
    }

    /// The loadout the simulation should actually use, with anything unowned stripped out.
    public var validatedLoadout: Loadout {
        selectedLoadout.validated(against: unlocks, level: level)
    }

    // MARK: Mutations

    /// Awards XP and returns every level gained, so the results screen can play them out.
    @discardableResult
    public mutating func awardXP(_ amount: Int) -> [Int] {
        guard amount > 0 else { return [] }
        let before = level
        totalXP += amount
        let after = level
        guard after > before else { return [] }
        let gained = Array((before + 1)...after)
        for newLevel in gained {
            unlocks.applyLevelUnlocks(upTo: newLevel)
            // Every level pays out, so levelling always feels like it gave you something.
            wallet.credit(500 + newLevel * 25, .coins)
            if newLevel % 5 == 0 { wallet.credit(50, .gems) }
        }
        return gained
    }

    public mutating func awardBattlePassXP(_ amount: Int) {
        guard amount > 0 else { return }
        let season = BattlePassDatabase.currentSeason
        if battlePass.seasonID != season.seasonID {
            battlePass = BattlePassProgress(seasonID: season.seasonID)
        }
        let cap = season.xpPerTier * season.totalTiers
        battlePass.xp = min(cap, battlePass.xp + amount)
    }

    /// Prestige resets the level but keeps unlocks, stats and everything bought.
    @discardableResult
    public mutating func prestigeIfPossible() -> Bool {
        guard level >= XPCurve.maxLevel else { return false }
        prestige += 1
        totalXP = 0
        wallet.credit(5000, .coins)
        wallet.credit(200, .gems)
        return true
    }

    public mutating func grant(_ reward: RewardKind) {
        switch reward {
        case let .currency(kind, amount):
            wallet.credit(amount, kind)
        case let .cosmetic(id):
            unlocks.unlockCosmetic(id)
        case let .character(id):
            unlocks.unlockCharacter(id)
        case let .weapon(id):
            unlocks.unlockWeapon(id)
        case let .attachment(id):
            for weapon in WeaponDatabase.all { unlocks.unlockAttachment(id, on: weapon.id) }
        case .crate:
            // Crates are granted as an inventory entry; opening happens in the store flow.
            entitlements.pendingCrates.append(reward.displayName)
        case let .xpBoost(hours, multiplier):
            entitlements.activateXPBoost(hours: hours, multiplier: multiplier)
        }
    }

    /// Applies everything earned in one match in a single place, so the results screen,
    /// the offline path and the online path can never disagree.
    @discardableResult
    public mutating func applyMatchResults(result: PlayerResult, mode: GameModeData,
                                           won: Bool, durationSeconds: Float,
                                           shotsFired: Int, shotsHit: Int,
                                           killsByWeapon: [WeaponID: Int]) -> MatchRewards {
        let premium = isPremium
        let xp = MatchPayout.xp(result: result, mode: mode, won: won, isPremium: premium,
                                hasDoubleXP: entitlements.hasActiveXPBoost)
        let coins = MatchPayout.coins(result: result, mode: mode, won: won, isPremium: premium,
                                      hasDoubleCoins: entitlements.hasActiveXPBoost)
        let passXP = MatchPayout.battlePassXP(matchDurationSeconds: durationSeconds,
                                              won: won, isPremium: premium)

        let levelsGained = awardXP(xp)
        wallet.credit(coins, .coins)
        awardBattlePassXP(passXP)
        stats.record(result: result, mode: mode.kind, won: won, durationSeconds: durationSeconds,
                     shotsFired: shotsFired, shotsHit: shotsHit)

        var newAttachments: [AttachmentData] = []
        for (weapon, kills) in killsByWeapon {
            newAttachments.append(contentsOf: unlocks.recordKills(kills, with: weapon))
            stats.killsByWeapon[weapon.value, default: 0] += kills
        }
        lastPlayedAt = Date()

        return MatchRewards(xp: xp, coins: coins, battlePassXP: passXP,
                            levelsGained: levelsGained, newAttachments: newAttachments)
    }

    /// Migrates an older save forward. Called by the save store after decoding.
    public mutating func migrate() {
        if version < 2 {
            // v2 introduced the battle pass.
            battlePass = BattlePassProgress(seasonID: BattlePassDatabase.currentSeason.seasonID)
        }
        if version < 3 {
            // v3 added per-weapon attachment progression.
            unlocks.applyLevelUnlocks(upTo: level)
        }
        version = PlayerProfile.currentVersion
    }
}

public struct MatchRewards: Sendable {
    public var xp: Int
    public var coins: Int
    public var battlePassXP: Int
    public var levelsGained: [Int]
    public var newAttachments: [AttachmentData]

    public var hasSomethingToCelebrate: Bool {
        !levelsGained.isEmpty || !newAttachments.isEmpty
    }
}

/// Purchases and subscriptions. Kept separate from the wallet because these are validated
/// against StoreKit, not earned in game.
public struct Entitlements: Codable, Equatable, Sendable {
    public var ownedProductIDs: Set<String>
    public var vipExpiresAt: Date?
    public var adsRemoved: Bool
    public var xpBoostExpiresAt: Date?
    public var xpBoostMultiplier: Float
    public var pendingCrates: [String]
    public var lifetimeSpendUSD: Double

    public init() {
        ownedProductIDs = []
        adsRemoved = false
        xpBoostMultiplier = 1
        pendingCrates = []
        lifetimeSpendUSD = 0
    }

    public var hasActiveVIP: Bool {
        guard let expiry = vipExpiresAt else { return false }
        return expiry > Date()
    }

    public var hasActiveXPBoost: Bool {
        guard let expiry = xpBoostExpiresAt else { return false }
        return expiry > Date()
    }

    public var showsAds: Bool { !adsRemoved && !hasActiveVIP }

    public mutating func activateXPBoost(hours: Int, multiplier: Float) {
        let base = max(Date(), xpBoostExpiresAt ?? Date())
        xpBoostExpiresAt = base.addingTimeInterval(TimeInterval(hours * 3600))
        xpBoostMultiplier = max(xpBoostMultiplier, multiplier)
    }

    public mutating func activateVIP(days: Int) {
        let base = max(Date(), vipExpiresAt ?? Date())
        vipExpiresAt = base.addingTimeInterval(TimeInterval(days * 86400))
    }

    public func owns(_ productID: String) -> Bool { ownedProductIDs.contains(productID) }
}
