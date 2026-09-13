import Foundation

public enum CurrencyKind: String, Codable, CaseIterable, Sendable {
    /// Earned by playing. Buys weapons, attachments and most cosmetics.
    case coins
    /// Premium currency, bought with real money or earned slowly from the battle pass.
    case gems
    /// Battle-pass-only currency for the seasonal shop.
    case tokens

    public var displayName: String {
        switch self {
        case .coins: return "Credits"
        case .gems: return "Gems"
        case .tokens: return "Season Tokens"
        }
    }

    public var iconName: String { "icon_currency_\(rawValue)" }
    public var isPremium: Bool { self == .gems }
    public var colorHex: UInt32 {
        switch self {
        case .coins: return 0xFFC857
        case .gems: return 0x64D2FF
        case .tokens: return 0xC792EA
        }
    }
}

public struct Wallet: Codable, Equatable, Sendable {
    public private(set) var balances: [CurrencyKind: Int]

    public init(coins: Int = 0, gems: Int = 0, tokens: Int = 0) {
        balances = [.coins: coins, .gems: gems, .tokens: tokens]
    }

    public func balance(_ kind: CurrencyKind) -> Int { balances[kind] ?? 0 }
    public var coins: Int { balance(.coins) }
    public var gems: Int { balance(.gems) }
    public var tokens: Int { balance(.tokens) }

    public func canAfford(_ amount: Int, _ kind: CurrencyKind) -> Bool {
        amount <= 0 || balance(kind) >= amount
    }

    public mutating func credit(_ amount: Int, _ kind: CurrencyKind) {
        guard amount > 0 else { return }
        balances[kind, default: 0] += amount
    }

    /// Returns false and changes nothing when the player cannot afford it — every spend
    /// path goes through here so a balance can never go negative.
    @discardableResult
    public mutating func debit(_ amount: Int, _ kind: CurrencyKind) -> Bool {
        guard amount > 0 else { return true }
        guard canAfford(amount, kind) else { return false }
        balances[kind, default: 0] -= amount
        return true
    }
}

/// How much soft currency a match pays out. Tuned so an average 10-minute match pays
/// ~900 credits: a mid-tier weapon is roughly 15 matches of saving.
public enum MatchPayout {
    public static func coins(result: PlayerResult, mode: GameModeData, won: Bool,
                             isPremium: Bool, hasDoubleCoins: Bool) -> Int {
        var total = 120                                   // participation
        total += result.kills * 18
        total += result.assists * 8
        total += Int(result.damage / 40)
        total += result.headshots * 6
        total += result.bestStreak * 10
        if won { total += 200 }
        if result.mvp { total += 150 }
        total = Int(Float(total) * mode.xpMultiplier)
        if isPremium { total = Int(Float(total) * 1.25) }
        if hasDoubleCoins { total *= 2 }
        return max(60, total)
    }

    public static func xp(result: PlayerResult, mode: GameModeData, won: Bool,
                          isPremium: Bool, hasDoubleXP: Bool) -> Int {
        var total = result.xpEarned                       // in-match awards
        total += 250                                      // match completion
        if won { total += 400 }
        if result.mvp { total += 200 }
        total = Int(Float(total) * mode.xpMultiplier)
        if isPremium { total = Int(Float(total) * 1.25) }
        if hasDoubleXP { total *= 2 }
        return max(100, total)
    }

    /// Battle pass progress is deliberately time-based rather than kill-based so that
    /// support play and objective play advance it at the same rate.
    public static func battlePassXP(matchDurationSeconds: Float, won: Bool, isPremium: Bool) -> Int {
        var total = Int(matchDurationSeconds / 60 * 120)
        if won { total += 100 }
        if isPremium { total = Int(Float(total) * 1.25) }
        return max(50, total)
    }
}
