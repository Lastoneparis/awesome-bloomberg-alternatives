import Foundation

/// Player level curve. Levels 1-55 are the main climb; after that the player prestiges.
/// The curve is quadratic with a soft cap so late levels take about 25 minutes each
/// rather than spiralling into grind territory.
public enum XPCurve {
    public static let maxLevel = 55

    public static func xpRequired(forLevel level: Int) -> Int {
        guard level > 1 else { return 0 }
        let l = Float(min(level, maxLevel))
        return Int(900 * l + 65 * l * l)
    }

    public static func totalXP(forLevel level: Int) -> Int {
        (1...max(1, min(level, maxLevel))).reduce(0) { $0 + xpRequired(forLevel: $1) }
    }

    public static func level(forTotalXP xp: Int) -> Int {
        var level = 1
        var remaining = xp
        while level < maxLevel {
            let needed = xpRequired(forLevel: level + 1)
            if remaining < needed { break }
            remaining -= needed
            level += 1
        }
        return level
    }

    public static func progress(totalXP: Int) -> (level: Int, current: Int, required: Int, fraction: Float) {
        let level = self.level(forTotalXP: totalXP)
        let consumed = totalXP(forLevel: level)
        let required = level >= maxLevel ? 0 : xpRequired(forLevel: level + 1)
        let current = totalXP - consumed
        let fraction = required > 0 ? MathUtil.clamp(Float(current) / Float(required), 0, 1) : 1
        return (level, current, required, fraction)
    }
}

/// Competitive rank, separate from the cosmetic player level.
public enum CompetitiveRank: Int, Codable, CaseIterable, Comparable, Sendable {
    case bronze = 0, silver, gold, platinum, diamond, master, legend

    public static func < (a: CompetitiveRank, b: CompetitiveRank) -> Bool { a.rawValue < b.rawValue }

    public var displayName: String {
        ["Bronze", "Silver", "Gold", "Platinum", "Diamond", "Master", "Legend"][rawValue]
    }
    public var iconName: String { "icon_rank_\(rawValue)" }
    public var colorHex: UInt32 {
        [0xA9744F, 0xBFC6CC, 0xE0B341, 0x6FD6C8, 0x7FB2FF, 0xC77DFF, 0xFF5470][rawValue]
    }
    /// Minimum MMR to hold this rank.
    public var threshold: Int { [0, 1000, 1400, 1800, 2200, 2600, 3000][rawValue] }

    public static func rank(forRating rating: Int) -> CompetitiveRank {
        allCases.last { rating >= $0.threshold } ?? .bronze
    }

    /// Division within a rank (III → I), because a single band is too coarse.
    public static func division(forRating rating: Int) -> Int {
        let rank = self.rank(forRating: rating)
        guard let next = CompetitiveRank(rawValue: rank.rawValue + 1) else { return 1 }
        let span = next.threshold - rank.threshold
        guard span > 0 else { return 1 }
        let within = Float(rating - rank.threshold) / Float(span)
        return 3 - Int(within * 3)
    }
}

public enum RatingCalculator {
    /// Elo-style update with a performance term, so carrying a losing team still pays.
    public static func update(rating: Int, opponentRating: Int, won: Bool,
                              performanceScore: Float, kFactor: Int = 32) -> Int {
        let expected = 1.0 / (1.0 + pow(10, Float(opponentRating - rating) / 400))
        let actual: Float = won ? 1 : 0
        let base = Float(kFactor) * (actual - expected)
        // performanceScore is 0...1 where 0.5 is an average game.
        let performanceAdjustment = Float(kFactor) * 0.4 * (performanceScore - 0.5)
        return max(0, rating + Int((base + performanceAdjustment).rounded()))
    }

    /// Normalizes a scoreboard line into the 0...1 performance score above.
    public static func performanceScore(result: PlayerResult, teamAverageScore: Float) -> Float {
        guard teamAverageScore > 1 else { return 0.5 }
        return MathUtil.clamp(Float(result.score) / (teamAverageScore * 2), 0, 1)
    }
}

/// Everything a player has unlocked. Persisted with the profile and re-validated by the
/// server whenever a loadout is submitted.
public struct UnlockState: Codable, Equatable, Sendable {
    public var weapons: Set<String>
    public var attachments: [String: Set<String>]    // weaponID -> attachment ids
    public var perks: Set<String>
    public var characters: Set<String>
    public var cosmetics: Set<String>
    public var weaponKills: [String: Int]
    public var weaponLevels: [String: Int]

    public init() {
        weapons = [WeaponDatabase.defaultPrimary.value,
                   WeaponDatabase.defaultSecondary.value,
                   WeaponDatabase.defaultMelee.value,
                   "smg_wasp"]
        attachments = [:]
        perks = ["perk_lightfoot", "perk_scavenger", "perk_quickhands"]
        characters = ["chr_recruit_strike", "chr_recruit_shield"]
        cosmetics = []
        weaponKills = [:]
        weaponLevels = [:]
    }

    public func hasWeapon(_ id: WeaponID) -> Bool { weapons.contains(id.value) }
    public func hasPerk(_ id: ContentID) -> Bool { perks.contains(id.value) }
    public func hasCharacter(_ id: CharacterID) -> Bool { characters.contains(id.value) }
    public func hasCosmetic(_ id: SkinID) -> Bool { cosmetics.contains(id.value) }
    public func hasAttachment(_ id: AttachmentID, on weapon: WeaponID) -> Bool {
        attachments[weapon.value]?.contains(id.value) ?? false
    }

    public mutating func unlockWeapon(_ id: WeaponID) { weapons.insert(id.value) }
    public mutating func unlockPerk(_ id: ContentID) { perks.insert(id.value) }
    public mutating func unlockCharacter(_ id: CharacterID) { characters.insert(id.value) }
    public mutating func unlockCosmetic(_ id: SkinID) { cosmetics.insert(id.value) }
    public mutating func unlockAttachment(_ id: AttachmentID, on weapon: WeaponID) {
        attachments[weapon.value, default: []].insert(id.value)
    }

    /// Weapon progression: kills unlock that weapon's attachments. Returns anything newly
    /// unlocked so the UI can show a "new attachment" card.
    @discardableResult
    public mutating func recordKills(_ count: Int, with weapon: WeaponID) -> [AttachmentData] {
        guard count > 0 else { return [] }
        let total = (weaponKills[weapon.value] ?? 0) + count
        weaponKills[weapon.value] = total
        weaponLevels[weapon.value] = 1 + total / 25

        var unlocked: [AttachmentData] = []
        for attachment in AttachmentDatabase.all
        where attachment.unlockKills > 0 && total >= attachment.unlockKills {
            if !hasAttachment(attachment.id, on: weapon) {
                unlockAttachment(attachment.id, on: weapon)
                unlocked.append(attachment)
            }
        }
        return unlocked
    }

    public func kills(with weapon: WeaponID) -> Int { weaponKills[weapon.value] ?? 0 }
    public func weaponLevel(_ weapon: WeaponID) -> Int { weaponLevels[weapon.value] ?? 1 }

    /// Applies every level-gated unlock up to `level`, returning what was newly granted.
    @discardableResult
    public mutating func applyLevelUnlocks(upTo level: Int) -> [String] {
        var granted: [String] = []
        for weapon in WeaponDatabase.all where weapon.unlockLevel <= level && !hasWeapon(weapon.id) {
            unlockWeapon(weapon.id)
            granted.append(weapon.name)
        }
        for perk in PerkDatabase.all where perk.unlockLevel <= level && !hasPerk(perk.id) {
            unlockPerk(perk.id)
            granted.append(perk.name)
        }
        for character in CharacterDatabase.all
        where character.unlockLevel <= level && character.storeCostCoins == 0
                && character.storeCostGems == 0 && !hasCharacter(character.id) {
            unlockCharacter(character.id)
            granted.append(character.name)
        }
        return granted
    }
}

/// Lifetime statistics, shown on the profile screen and used by career missions.
public struct PlayerStats: Codable, Equatable, Sendable {
    public var matchesPlayed: Int = 0
    public var matchesWon: Int = 0
    public var kills: Int = 0
    public var deaths: Int = 0
    public var assists: Int = 0
    public var headshots: Int = 0
    public var damageDealt: Double = 0
    public var shotsFired: Int = 0
    public var shotsHit: Int = 0
    public var bestStreak: Int = 0
    public var bombsPlanted: Int = 0
    public var bombsDefused: Int = 0
    public var objectivesCaptured: Int = 0
    public var timePlayedSeconds: Double = 0
    public var mvpCount: Int = 0
    public var wallbangs: Int = 0
    public var grenadeKills: Int = 0
    public var meleeKills: Int = 0
    public var killsByWeapon: [String: Int] = [:]
    public var killsByMode: [String: Int] = [:]

    public init() {}

    public var kdRatio: Float { deaths == 0 ? Float(kills) : Float(kills) / Float(deaths) }
    public var winRate: Float {
        matchesPlayed == 0 ? 0 : Float(matchesWon) / Float(matchesPlayed)
    }
    public var accuracy: Float {
        shotsFired == 0 ? 0 : Float(shotsHit) / Float(shotsFired)
    }
    public var headshotRate: Float {
        kills == 0 ? 0 : Float(headshots) / Float(kills)
    }
    public var averageDamagePerMatch: Float {
        matchesPlayed == 0 ? 0 : Float(damageDealt) / Float(matchesPlayed)
    }
    public var hoursPlayed: Float { Float(timePlayedSeconds / 3600) }
    public var favouriteWeapon: WeaponID? {
        killsByWeapon.max { $0.value < $1.value }.map { WeaponID($0.key) }
    }

    public mutating func record(result: PlayerResult, mode: GameModeKind, won: Bool,
                                durationSeconds: Float, shotsFired: Int, shotsHit: Int) {
        matchesPlayed += 1
        if won { matchesWon += 1 }
        kills += result.kills
        deaths += result.deaths
        assists += result.assists
        headshots += result.headshots
        damageDealt += Double(result.damage)
        bestStreak = max(bestStreak, result.bestStreak)
        timePlayedSeconds += Double(durationSeconds)
        if result.mvp { mvpCount += 1 }
        self.shotsFired += shotsFired
        self.shotsHit += shotsHit
        killsByMode[mode.rawValue, default: 0] += result.kills
    }
}
