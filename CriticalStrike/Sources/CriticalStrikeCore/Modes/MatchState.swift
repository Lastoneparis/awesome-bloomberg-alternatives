import Foundation

public enum MatchPhase: UInt8, Codable, Sendable {
    case warmup = 0, freezeTime, live, roundEnd, matchEnd, intermission

    public var isPlayable: Bool { self == .live || self == .warmup }
    public var allowsMovement: Bool { self != .freezeTime && self != .matchEnd }
    public var displayName: String {
        switch self {
        case .warmup: return "Warmup"
        case .freezeTime: return "Buy Phase"
        case .live: return "Live"
        case .roundEnd: return "Round Over"
        case .matchEnd: return "Match Over"
        case .intermission: return "Halftime"
        }
    }
}

public struct BombState: Codable, Sendable {
    public var carrier: PlayerID
    public var isPlanted: Bool
    public var isDefused: Bool
    public var hasExploded: Bool
    public var site: Int
    public var position: Vec3
    public var timer: Countdown
    public var defuser: PlayerID
    public var defuseTimer: Countdown
    public var planter: PlayerID

    public init() {
        carrier = .none; isPlanted = false; isDefused = false; hasExploded = false
        site = -1; position = .zero; timer = Countdown(); defuser = .none
        defuseTimer = Countdown(); planter = .none
    }

    public static let plantDuration: Float = 3.2
    public static let defuseDuration: Float = 10.0
    public static let defuseWithKitDuration: Float = 5.0
    public static let fuseDuration: Float = 40.0
    public static let explosionDamage: Float = 500
    public static let explosionInnerRadius: Float = 8
    public static let explosionOuterRadius: Float = 30
}

public struct CaptureState: Codable, Sendable {
    public var index: Int
    public var owner: Team
    public var progress: Float        // -1 (shield fully) ... +1 (strike fully)
    public var contested: Bool
    public var strikeCount: Int
    public var shieldCount: Int

    public init(index: Int) {
        self.index = index; owner = .none; progress = 0; contested = false
        strikeCount = 0; shieldCount = 0
    }
}

public struct MatchState: Sendable {
    public var mode: GameModeData
    public var mapID: MapID
    public var phase: MatchPhase
    public var phaseTimer: Countdown
    public var matchTimer: Countdown
    public var round: Int
    public var scores: [Team: Int]
    public var roundWins: [Team: Int]
    public var bomb: BombState
    public var captures: [CaptureState]
    public var activeHardpoint: Int
    public var hardpointRotationTimer: Countdown
    public var sidesSwapped: Bool
    public var overtimeRound: Int
    public var firstBloodTaken: Bool
    public var zombieWave: Int

    public init(mode: GameModeData, mapID: MapID) {
        self.mode = mode
        self.mapID = mapID
        self.phase = .warmup
        self.phaseTimer = Countdown()
        self.matchTimer = Countdown()
        self.round = 0
        self.scores = [.strike: 0, .shield: 0, .none: 0]
        self.roundWins = [.strike: 0, .shield: 0]
        self.bomb = BombState()
        self.captures = []
        self.activeHardpoint = 0
        self.hardpointRotationTimer = Countdown()
        self.sidesSwapped = false
        self.overtimeRound = 0
        self.firstBloodTaken = false
        self.zombieWave = 0
    }

    public func score(_ team: Team) -> Int { scores[team] ?? 0 }
    public mutating func addScore(_ team: Team, _ amount: Int) {
        scores[team, default: 0] += amount
    }
    public var leadingTeam: Team {
        score(.strike) == score(.shield) ? .none : (score(.strike) > score(.shield) ? .strike : .shield)
    }
    public var isTied: Bool { score(.strike) == score(.shield) }
    /// Round number at which teams swap sides in round-based modes.
    public var halftimeRound: Int { max(1, mode.roundsToWin) }
}

public struct PlayerResult: Codable, Identifiable, Sendable {
    public var id: PlayerID { player }
    public var player: PlayerID
    public var name: String
    public var team: Team
    public var isBot: Bool
    public var kills: Int
    public var deaths: Int
    public var assists: Int
    public var score: Int
    public var damage: Float
    public var headshots: Int
    public var bestStreak: Int
    public var xpEarned: Int
    public var accuracy: Float
    public var mvp: Bool

    public init(player: PlayerID, name: String, team: Team, isBot: Bool, kills: Int, deaths: Int,
                assists: Int, score: Int, damage: Float, headshots: Int, bestStreak: Int,
                xpEarned: Int = 0, accuracy: Float = 0, mvp: Bool = false) {
        self.player = player; self.name = name; self.team = team; self.isBot = isBot
        self.kills = kills; self.deaths = deaths; self.assists = assists; self.score = score
        self.damage = damage; self.headshots = headshots; self.bestStreak = bestStreak
        self.xpEarned = xpEarned; self.accuracy = accuracy; self.mvp = mvp
    }

    public var kdRatio: Float { deaths == 0 ? Float(kills) : Float(kills) / Float(deaths) }
}

public struct MatchResult: Sendable {
    public var mode: GameModeKind
    public var map: MapID
    public var winner: Team
    public var localPlayerWon: Bool
    public var strikeScore: Int
    public var shieldScore: Int
    public var durationSeconds: Float
    public var results: [PlayerResult]
    public var mvp: PlayerID

    public init(mode: GameModeKind, map: MapID, winner: Team, localPlayerWon: Bool,
                strikeScore: Int, shieldScore: Int, durationSeconds: Float,
                results: [PlayerResult], mvp: PlayerID) {
        self.mode = mode; self.map = map; self.winner = winner
        self.localPlayerWon = localPlayerWon; self.strikeScore = strikeScore
        self.shieldScore = shieldScore; self.durationSeconds = durationSeconds
        self.results = results; self.mvp = mvp
    }

    public var scoreboard: [PlayerResult] {
        results.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.kills != b.kills { return a.kills > b.kills }
            return a.deaths < b.deaths
        }
    }
}

/// Rolling killfeed entry.
public struct KillFeedEntry: Identifiable, Sendable {
    public let id = UUID()
    public var killerName: String
    public var victimName: String
    public var killerTeam: Team
    public var victimTeam: Team
    public var weapon: WeaponID
    public var headshot: Bool
    public var wallbang: Bool
    public var timestamp: Float

    public init(killerName: String, victimName: String, killerTeam: Team, victimTeam: Team,
                weapon: WeaponID, headshot: Bool, wallbang: Bool, timestamp: Float) {
        self.killerName = killerName; self.victimName = victimName
        self.killerTeam = killerTeam; self.victimTeam = victimTeam
        self.weapon = weapon; self.headshot = headshot; self.wallbang = wallbang
        self.timestamp = timestamp
    }
}
