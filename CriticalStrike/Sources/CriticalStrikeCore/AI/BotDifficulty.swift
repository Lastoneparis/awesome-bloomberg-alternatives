import Foundation

public enum BotDifficulty: String, Codable, CaseIterable, Sendable {
    case recruit, regular, hardened, veteran, elite

    public var displayName: String {
        switch self {
        case .recruit: return "Recruit"
        case .regular: return "Regular"
        case .hardened: return "Hardened"
        case .veteran: return "Veteran"
        case .elite: return "Elite"
        }
    }

    /// Bots are made harder by being *faster and more consistent*, never by being given
    /// extra damage or health — an unfair bot reads as a broken game.
    public var profile: BotProfile {
        switch self {
        case .recruit:
            return BotProfile(reactionTime: 0.62, aimErrorDegrees: 7.5, aimSpeed: 3.2,
                              trackingJitter: 2.6, fieldOfViewDegrees: 95, hearingRadius: 14,
                              burstDiscipline: 0.35, preferredRange: 14, accuracyOverDistance: 0.45,
                              memoryDuration: 2.5, grenadeChance: 0.05, strafeSkill: 0.2,
                              crouchSkill: 0.1, reloadDiscipline: 0.3, headshotPreference: 0.05,
                              peekPatience: 0.4, teamworkRadius: 8)
        case .regular:
            return BotProfile(reactionTime: 0.45, aimErrorDegrees: 5.0, aimSpeed: 5.0,
                              trackingJitter: 1.9, fieldOfViewDegrees: 105, hearingRadius: 18,
                              burstDiscipline: 0.5, preferredRange: 18, accuracyOverDistance: 0.6,
                              memoryDuration: 4, grenadeChance: 0.12, strafeSkill: 0.4,
                              crouchSkill: 0.25, reloadDiscipline: 0.5, headshotPreference: 0.15,
                              peekPatience: 0.6, teamworkRadius: 12)
        case .hardened:
            return BotProfile(reactionTime: 0.32, aimErrorDegrees: 3.2, aimSpeed: 7.5,
                              trackingJitter: 1.3, fieldOfViewDegrees: 115, hearingRadius: 22,
                              burstDiscipline: 0.68, preferredRange: 22, accuracyOverDistance: 0.72,
                              memoryDuration: 6, grenadeChance: 0.22, strafeSkill: 0.6,
                              crouchSkill: 0.45, reloadDiscipline: 0.7, headshotPreference: 0.3,
                              peekPatience: 0.75, teamworkRadius: 16)
        case .veteran:
            return BotProfile(reactionTime: 0.22, aimErrorDegrees: 2.0, aimSpeed: 10.0,
                              trackingJitter: 0.85, fieldOfViewDegrees: 125, hearingRadius: 26,
                              burstDiscipline: 0.82, preferredRange: 26, accuracyOverDistance: 0.84,
                              memoryDuration: 8, grenadeChance: 0.32, strafeSkill: 0.78,
                              crouchSkill: 0.6, reloadDiscipline: 0.85, headshotPreference: 0.45,
                              peekPatience: 0.85, teamworkRadius: 20)
        case .elite:
            return BotProfile(reactionTime: 0.14, aimErrorDegrees: 1.1, aimSpeed: 13.5,
                              trackingJitter: 0.45, fieldOfViewDegrees: 135, hearingRadius: 30,
                              burstDiscipline: 0.92, preferredRange: 30, accuracyOverDistance: 0.93,
                              memoryDuration: 11, grenadeChance: 0.42, strafeSkill: 0.92,
                              crouchSkill: 0.75, reloadDiscipline: 0.95, headshotPreference: 0.6,
                              peekPatience: 0.95, teamworkRadius: 24)
        }
    }

    public var suggestedForPlayerLevel: ClosedRange<Int> {
        switch self {
        case .recruit: return 1...5
        case .regular: return 6...15
        case .hardened: return 16...30
        case .veteran: return 31...45
        case .elite: return 46...999
        }
    }
}

public struct BotProfile: Sendable {
    /// Seconds between seeing a target and being allowed to shoot.
    public var reactionTime: Float
    /// Maximum angular error added to the aim point.
    public var aimErrorDegrees: Float
    /// How fast the bot slews onto target (radians/second scale).
    public var aimSpeed: Float
    /// Constant hand-shake, in degrees, so bots are never pixel-perfect.
    public var trackingJitter: Float
    public var fieldOfViewDegrees: Float
    public var hearingRadius: Float
    /// 0...1 — how well the bot times bursts for its weapon's recoil.
    public var burstDiscipline: Float
    /// Distance the bot tries to hold.
    public var preferredRange: Float
    /// 0...1 — how much of its accuracy the bot retains at long range.
    public var accuracyOverDistance: Float
    /// How long the bot remembers a target it lost sight of.
    public var memoryDuration: Float
    public var grenadeChance: Float
    public var strafeSkill: Float
    public var crouchSkill: Float
    public var reloadDiscipline: Float
    public var headshotPreference: Float
    /// 0...1 — willingness to hold an angle instead of pushing.
    public var peekPatience: Float
    public var teamworkRadius: Float

    public init(reactionTime: Float, aimErrorDegrees: Float, aimSpeed: Float, trackingJitter: Float,
                fieldOfViewDegrees: Float, hearingRadius: Float, burstDiscipline: Float,
                preferredRange: Float, accuracyOverDistance: Float, memoryDuration: Float,
                grenadeChance: Float, strafeSkill: Float, crouchSkill: Float,
                reloadDiscipline: Float, headshotPreference: Float, peekPatience: Float,
                teamworkRadius: Float) {
        self.reactionTime = reactionTime; self.aimErrorDegrees = aimErrorDegrees
        self.aimSpeed = aimSpeed; self.trackingJitter = trackingJitter
        self.fieldOfViewDegrees = fieldOfViewDegrees; self.hearingRadius = hearingRadius
        self.burstDiscipline = burstDiscipline; self.preferredRange = preferredRange
        self.accuracyOverDistance = accuracyOverDistance; self.memoryDuration = memoryDuration
        self.grenadeChance = grenadeChance; self.strafeSkill = strafeSkill
        self.crouchSkill = crouchSkill; self.reloadDiscipline = reloadDiscipline
        self.headshotPreference = headshotPreference; self.peekPatience = peekPatience
        self.teamworkRadius = teamworkRadius
    }
}

/// Bot names are drawn from a fixed pool so a match roster looks like a real lobby.
public enum BotNames {
    public static let pool: [String] = [
        "Ghost", "Rook", "Ember", "Static", "Vandal", "Cobra", "Juno", "Nomad",
        "Havoc", "Zero", "Frost", "Pike", "Drift", "Talon", "Mako", "Ronin",
        "Slate", "Prism", "Vector", "Blitz", "Kilo", "Sable", "Torque", "Wraith",
        "Nova", "Ash", "Cinder", "Hex", "Quill", "Riot", "Saint", "Tundra"
    ]

    public static func name(index: Int, difficulty: BotDifficulty) -> String {
        let base = pool[index % pool.count]
        let suffix = index >= pool.count ? "\(index / pool.count + 1)" : ""
        switch difficulty {
        case .elite: return "\(base)\(suffix)*"
        case .veteran: return "\(base)\(suffix)+"
        default: return "\(base)\(suffix)"
        }
    }
}
