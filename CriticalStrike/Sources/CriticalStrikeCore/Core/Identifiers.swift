import Foundation

/// Network-friendly entity handle. 16 bits is plenty for 32 players + projectiles + pickups,
/// and keeps snapshot packets small.
public struct EntityID: Codable, Hashable, Comparable, Sendable, RawRepresentable {
    public var rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public init(_ v: Int) { self.rawValue = UInt16(truncatingIfNeeded: v) }
    public static let invalid = EntityID(rawValue: 0)
    public var isValid: Bool { rawValue != 0 }
    public static func < (a: EntityID, b: EntityID) -> Bool { a.rawValue < b.rawValue }
}

public struct PlayerID: Codable, Hashable, Comparable, Sendable {
    public var rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public init(_ v: Int) { self.rawValue = UInt8(truncatingIfNeeded: v) }
    public static let none = PlayerID(rawValue: 255)
    public var isValid: Bool { rawValue != 255 }
    public var entity: EntityID { EntityID(rawValue: UInt16(rawValue) + 1) }
    public static func < (a: PlayerID, b: PlayerID) -> Bool { a.rawValue < b.rawValue }
}

/// Stable string keys for content. Content is data-driven so a live-ops build can ship
/// new weapons/maps/skins without a client update.
public struct ContentID: Codable, Hashable, ExpressibleByStringLiteral, Sendable, CustomStringConvertible {
    public let value: String
    public init(_ value: String) { self.value = value }
    public init(stringLiteral value: String) { self.value = value }
    public var description: String { value }

    public init(from decoder: Decoder) throws {
        value = try decoder.singleValueContainer().decode(String.self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

public typealias WeaponID = ContentID
public typealias MapID = ContentID
public typealias SkinID = ContentID
public typealias AttachmentID = ContentID
public typealias CharacterID = ContentID
public typealias MissionID = ContentID
public typealias ProductID = ContentID

public enum Team: UInt8, Codable, CaseIterable, Sendable {
    case none = 0
    case strike = 1     // attackers / "Strike Force"
    case shield = 2     // defenders / "Shield Corps"

    public var opponent: Team {
        switch self {
        case .strike: return .shield
        case .shield: return .strike
        case .none: return .none
        }
    }

    public var displayName: String {
        switch self {
        case .strike: return "Strike Force"
        case .shield: return "Shield Corps"
        case .none: return "Spectators"
        }
    }

    /// Hex tint used by HUD, minimap and scoreboard.
    public var colorHex: UInt32 {
        switch self {
        case .strike: return 0xFF6B35
        case .shield: return 0x2EC4F1
        case .none: return 0x9AA0A6
        }
    }
}
