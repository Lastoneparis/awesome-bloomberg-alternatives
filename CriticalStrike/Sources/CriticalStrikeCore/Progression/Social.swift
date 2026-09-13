import Foundation

/// A clan. Clans are cosmetic and social: a tag beside your name, a shared weekly
/// leaderboard, and a bonus that is small enough that nobody is ever forced to join one.
public struct Clan: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var tag: String            // 2-4 characters, shown beside the player's name
    public var motto: String
    public var level: Int
    public var weeklyXP: Int
    public var memberIDs: [String]
    public var leaderID: String
    public var isOpen: Bool           // open clans can be joined without an invite
    public var minimumLevel: Int
    public var createdAt: Date
    public var bannerID: SkinID?

    public static let maximumMembers = 30
    public static let creationCostCoins = 25_000

    public init(id: String = UUID().uuidString, name: String, tag: String, motto: String = "",
                level: Int = 1, weeklyXP: Int = 0, memberIDs: [String] = [],
                leaderID: String, isOpen: Bool = true, minimumLevel: Int = 1,
                createdAt: Date = Date(), bannerID: SkinID? = nil) {
        self.id = id
        self.name = name
        self.tag = Clan.normalize(tag: tag)
        self.motto = motto
        self.level = level
        self.weeklyXP = weeklyXP
        self.memberIDs = memberIDs
        self.leaderID = leaderID
        self.isOpen = isOpen
        self.minimumLevel = minimumLevel
        self.createdAt = createdAt
        self.bannerID = bannerID
    }

    public var isFull: Bool { memberIDs.count >= Clan.maximumMembers }
    public var memberCount: Int { memberIDs.count }

    /// Clan level comes from the members' combined weekly XP, so an active small clan can
    /// out-level a large dormant one.
    public var xpToNextLevel: Int { level * 50_000 }
    public var levelProgress: Float {
        MathUtil.clamp(Float(weeklyXP) / Float(max(1, xpToNextLevel)), 0, 1)
    }

    /// The perk clans give: a small XP bonus that tops out at 5%.
    public var xpBonus: Float { 1 + min(Float(level), 5) * 0.01 }

    public static func normalize(tag: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let filtered = tag.uppercased().unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(filtered.prefix(4)))
    }

    public static func isValid(name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 3 && trimmed.count <= 24
    }

    public static func isValid(tag: String) -> Bool {
        let normalized = normalize(tag: tag)
        return normalized.count >= 2 && normalized.count <= 4
    }
}

/// A friend entry. Friend codes are short, unambiguous and shareable out of band, so
/// adding someone never requires an account system or a platform friends list.
public struct Friend: Codable, Equatable, Identifiable, Sendable {
    public var id: String             // the friend code
    public var displayName: String
    public var level: Int
    public var lastSeen: Date
    public var isOnline: Bool
    public var favouriteMode: GameModeKind?

    public init(id: String, displayName: String, level: Int, lastSeen: Date = Date(),
                isOnline: Bool = false, favouriteMode: GameModeKind? = nil) {
        self.id = id
        self.displayName = displayName
        self.level = level
        self.lastSeen = lastSeen
        self.isOnline = isOnline
        self.favouriteMode = favouriteMode
    }

    public var lastSeenDescription: String {
        if isOnline { return "Online" }
        let elapsed = Date().timeIntervalSince(lastSeen)
        if elapsed < 3600 { return "\(max(1, Int(elapsed / 60)))m ago" }
        if elapsed < 86_400 { return "\(Int(elapsed / 3600))h ago" }
        return "\(Int(elapsed / 86_400))d ago"
    }
}

public enum FriendCode {
    /// Deterministic, human-readable code derived from the account id. Unambiguous
    /// alphabet: no O/0 or I/1, because these get read aloud and typed in by hand.
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    public static func make(from accountID: String) -> String {
        var hash = UInt64(2166136261)
        for byte in accountID.utf8 {
            hash = (hash ^ UInt64(byte)) &* 16777619
        }
        var characters: [Character] = []
        for index in 0..<8 {
            if index == 4 { characters.append("-") }
            characters.append(alphabet[Int(hash % UInt64(alphabet.count))])
            hash /= UInt64(alphabet.count)
            if hash == 0 { hash = 2166136261 }
        }
        return String(characters)
    }

    public static func isValid(_ code: String) -> Bool {
        let stripped = code.uppercased().replacingOccurrences(of: "-", with: "")
        guard stripped.count == 8 else { return false }
        return stripped.allSatisfy { alphabet.contains($0) }
    }

    public static func normalize(_ code: String) -> String {
        let stripped = code.uppercased().replacingOccurrences(of: "-", with: "")
        guard stripped.count == 8 else { return stripped }
        let index = stripped.index(stripped.startIndex, offsetBy: 4)
        return "\(stripped[..<index])-\(stripped[index...])"
    }
}
