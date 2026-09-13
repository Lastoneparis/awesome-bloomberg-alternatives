import Foundation

/// Every screen in the game. Kept as a flat enum rather than a NavigationStack because a
/// game's navigation is a state machine, not a document hierarchy.
enum AppRoute: Equatable, Hashable {
    case splash
    case mainMenu
    case play
    case lobby
    case matchmaking
    case loading
    case inMatch
    case results
    case loadout
    case armory
    case store
    case battlePass
    case missions
    case profile
    case leaderboard
    case social
    case settings
    case hudEditor

    /// Screens that should keep the menu music playing.
    var isMenu: Bool {
        switch self {
        case .inMatch, .loading: return false
        default: return true
        }
    }

    var title: String {
        switch self {
        case .splash: return ""
        case .mainMenu: return "Critical Strike"
        case .play: return "Play"
        case .lobby: return "Lobby"
        case .matchmaking: return "Finding Match"
        case .loading: return "Loading"
        case .inMatch: return ""
        case .results: return "Results"
        case .loadout: return "Loadout"
        case .armory: return "Armory"
        case .store: return "Store"
        case .battlePass: return "Battle Pass"
        case .missions: return "Missions"
        case .profile: return "Profile"
        case .leaderboard: return "Leaderboards"
        case .social: return "Social"
        case .settings: return "Settings"
        case .hudEditor: return "Customise HUD"
        }
    }
}

struct Toast: Identifiable, Equatable {
    enum Style { case info, success, warning, error, reward }
    let id = UUID()
    var message: String
    var style: Style = .info
    var icon: String?
}
