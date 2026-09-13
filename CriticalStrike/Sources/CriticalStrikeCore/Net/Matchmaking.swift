import Foundation

public enum Region: String, Codable, CaseIterable, Sendable {
    case auto, naEast, naWest, europe, asia, southAmerica, oceania, middleEast

    public var displayName: String {
        switch self {
        case .auto: return "Automatic"
        case .naEast: return "US East"
        case .naWest: return "US West"
        case .europe: return "Europe"
        case .asia: return "Asia"
        case .southAmerica: return "South America"
        case .oceania: return "Oceania"
        case .middleEast: return "Middle East"
        }
    }

    public var host: String {
        switch self {
        case .auto: return "gs.criticalstrike.game"
        default: return "\(rawValue.lowercased()).gs.criticalstrike.game"
        }
    }
}

public enum MatchmakingState: Equatable, Sendable {
    case idle
    case searching(elapsed: Float, estimatedWait: Float)
    case found(serverEndpoint: String)
    case connecting
    case inMatch
    case failed(reason: String)

    public var isSearching: Bool {
        if case .searching = self { return true }
        return false
    }
}

public struct MatchmakingTicket: Codable, Sendable {
    public var id: UUID
    public var mode: GameModeKind
    public var region: Region
    public var partyMembers: [String]
    public var skillRating: Int
    public var createdAt: Date
    public var allowBots: Bool
    public var preferredMaps: [MapID]

    public init(mode: GameModeKind, region: Region, partyMembers: [String] = [],
                skillRating: Int = 1000, allowBots: Bool = true, preferredMaps: [MapID] = []) {
        self.id = UUID()
        self.mode = mode; self.region = region; self.partyMembers = partyMembers
        self.skillRating = skillRating; self.createdAt = Date()
        self.allowBots = allowBots; self.preferredMaps = preferredMaps
    }

    /// Skill window widens the longer someone waits, so nobody queues forever.
    public func skillWindow(afterSeconds seconds: Float) -> ClosedRange<Int> {
        let widening = Int(seconds * 12)
        let span = min(150 + widening, 1200)
        return (skillRating - span)...(skillRating + span)
    }
}

public struct LobbyMember: Identifiable, Codable, Sendable {
    public var id: String
    public var displayName: String
    public var level: Int
    public var isReady: Bool
    public var isLeader: Bool
    public var team: Team
    public var avatarID: String

    public init(id: String, displayName: String, level: Int, isReady: Bool = false,
                isLeader: Bool = false, team: Team = .none, avatarID: String = "avatar_default") {
        self.id = id; self.displayName = displayName; self.level = level
        self.isReady = isReady; self.isLeader = isLeader; self.team = team; self.avatarID = avatarID
    }
}

public struct Lobby: Codable, Sendable {
    public var id: String
    public var mode: GameModeKind
    public var mapID: MapID
    public var region: Region
    public var members: [LobbyMember]
    public var isPrivate: Bool
    public var inviteCode: String
    public var maxSize: Int
    public var botDifficulty: BotDifficulty
    public var fillWithBots: Bool

    public init(id: String = UUID().uuidString, mode: GameModeKind = .teamDeathmatch,
                mapID: MapID = "map_sandstorm", region: Region = .auto,
                members: [LobbyMember] = [], isPrivate: Bool = false,
                inviteCode: String = Lobby.makeInviteCode(), maxSize: Int = 10,
                botDifficulty: BotDifficulty = .regular, fillWithBots: Bool = true) {
        self.id = id; self.mode = mode; self.mapID = mapID; self.region = region
        self.members = members; self.isPrivate = isPrivate; self.inviteCode = inviteCode
        self.maxSize = maxSize; self.botDifficulty = botDifficulty; self.fillWithBots = fillWithBots
    }

    public var isFull: Bool { members.count >= maxSize }
    public var everyoneReady: Bool { members.allSatisfy(\.isReady) }
    public var leader: LobbyMember? { members.first(where: \.isLeader) }

    public static func makeInviteCode() -> String {
        // Unambiguous alphabet: no O/0 or I/1.
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
    }

    public mutating func balanceTeams() {
        guard mode.isTeamBased else { return }
        let sorted = members.sorted { $0.level > $1.level }
        // Snake draft keeps the two sides close in average level.
        for (index, member) in sorted.enumerated() {
            if let position = members.firstIndex(where: { $0.id == member.id }) {
                members[position].team = (index % 4 == 0 || index % 4 == 3) ? .strike : .shield
            }
        }
    }
}

/// Drives matchmaking state. The actual HTTP/WebSocket calls live in the app layer; this
/// object owns the timing, backoff and the decision to fall back to a bot match.
public final class Matchmaker {
    public private(set) var state: MatchmakingState = .idle
    public var onStateChanged: ((MatchmakingState) -> Void)?
    /// After this long without a real match, start one against bots instead of making
    /// the player stare at a spinner.
    public var botFallbackAfter: Float = 25

    private var ticket: MatchmakingTicket?
    private var elapsed: Float = 0
    private var attempt = 0

    public init() {}

    public func start(_ ticket: MatchmakingTicket) {
        self.ticket = ticket
        elapsed = 0
        attempt = 0
        setState(.searching(elapsed: 0, estimatedWait: estimatedWait(for: ticket)))
    }

    public func cancel() {
        ticket = nil
        setState(.idle)
    }

    public func update(deltaTime: Float) {
        guard case .searching = state, let ticket else { return }
        elapsed += deltaTime
        setState(.searching(elapsed: elapsed, estimatedWait: estimatedWait(for: ticket)))
        if elapsed >= botFallbackAfter && ticket.allowBots {
            setState(.found(serverEndpoint: "local"))
        }
    }

    public func serverFound(endpoint: String) {
        setState(.found(serverEndpoint: endpoint))
    }

    public func fail(_ reason: String) {
        attempt += 1
        setState(.failed(reason: reason))
    }

    /// Exponential backoff for reconnect attempts, capped at 30s.
    public var retryDelay: Float {
        min(30, pow(2, Float(attempt)))
    }

    private func estimatedWait(for ticket: MatchmakingTicket) -> Float {
        // Popular modes fill faster; this is a UI estimate only.
        switch ticket.mode {
        case .teamDeathmatch, .freeForAll: return 12
        case .bombDefusal, .domination: return 20
        default: return 35
        }
    }

    private func setState(_ new: MatchmakingState) {
        state = new
        onStateChanged?(new)
    }
}
