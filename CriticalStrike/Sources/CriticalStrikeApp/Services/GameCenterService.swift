import Foundation
import GameKit
import UIKit
import CriticalStrikeCore

/// Game Center: authentication, leaderboards, achievements and (optionally) real-time
/// matchmaking. Everything degrades gracefully — a player who declines Game Center gets
/// the whole game, just without leaderboards.
@MainActor
final class GameCenterService: NSObject, ObservableObject {
    enum Leaderboard: String, CaseIterable {
        case totalKills = "game.criticalstrike.leaderboard.kills"
        case kdRatio = "game.criticalstrike.leaderboard.kd"
        case wins = "game.criticalstrike.leaderboard.wins"
        case level = "game.criticalstrike.leaderboard.level"
        case competitiveRating = "game.criticalstrike.leaderboard.rating"

        var displayName: String {
            switch self {
            case .totalKills: return "Total Kills"
            case .kdRatio: return "K/D Ratio"
            case .wins: return "Wins"
            case .level: return "Level"
            case .competitiveRating: return "Competitive Rating"
            }
        }
    }

    enum Achievement: String, CaseIterable {
        case firstBlood = "game.criticalstrike.achievement.firstblood"
        case hundredKills = "game.criticalstrike.achievement.kills100"
        case thousandKills = "game.criticalstrike.achievement.kills1000"
        case level25 = "game.criticalstrike.achievement.level25"
        case level55 = "game.criticalstrike.achievement.level55"
        case sharpshooter = "game.criticalstrike.achievement.sharpshooter"
        case bombExpert = "game.criticalstrike.achievement.bombexpert"
        case unstoppable = "game.criticalstrike.achievement.unstoppable"

        var title: String {
            switch self {
            case .firstBlood: return "First Blood"
            case .hundredKills: return "Getting Started"
            case .thousandKills: return "Thousand Yard Stare"
            case .level25: return "Halfway There"
            case .level55: return "Max Level"
            case .sharpshooter: return "Sharpshooter"
            case .bombExpert: return "Demolitions Expert"
            case .unstoppable: return "Unstoppable"
            }
        }
    }

    @Published private(set) var isAuthenticated = false
    @Published private(set) var playerDisplayName: String = ""
    @Published private(set) var playerID: String = ""

    private var reportedAchievements = Set<String>()

    func authenticate() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            GKLocalPlayer.local.authenticateHandler = { [weak self] _, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        Log.info("Game Center unavailable: \(error.localizedDescription)",
                                 category: "gamecenter")
                    }
                    self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                    self.playerDisplayName = GKLocalPlayer.local.displayName
                    self.playerID = GKLocalPlayer.local.gamePlayerID
                    if !resumed {
                        resumed = true
                        continuation.resume()
                    }
                }
            }
        }
    }

    func submit(score: Int, leaderboard: Leaderboard) {
        guard isAuthenticated else { return }
        Task {
            do {
                try await GKLeaderboard.submitScore(score, context: 0,
                                                    player: GKLocalPlayer.local,
                                                    leaderboardIDs: [leaderboard.rawValue])
            } catch {
                Log.warn("Leaderboard submit failed: \(error)", category: "gamecenter")
            }
        }
    }

    func loadLeaderboard(_ leaderboard: Leaderboard, count: Int = 25) async -> [LeaderboardEntry] {
        guard isAuthenticated else { return [] }
        do {
            let boards = try await GKLeaderboard.loadLeaderboards(IDs: [leaderboard.rawValue])
            guard let board = boards.first else { return [] }
            let (_, entries, _) = try await board.loadEntries(for: .global,
                                                              timeScope: .allTime,
                                                              range: NSRange(location: 1, length: count))
            return entries.map {
                LeaderboardEntry(rank: $0.rank, name: $0.player.displayName,
                                 score: $0.score, isLocalPlayer: $0.player == GKLocalPlayer.local)
            }
        } catch {
            Log.warn("Leaderboard load failed: \(error)", category: "gamecenter")
            return []
        }
    }

    func reportAchievements(stats: PlayerStats, level: Int) {
        guard isAuthenticated else { return }
        var achievements: [GKAchievement] = []

        func report(_ achievement: Achievement, percent: Double) {
            let clamped = min(100, max(0, percent))
            guard clamped > 0 else { return }
            // Avoid re-reporting completed achievements every match.
            if clamped >= 100 && reportedAchievements.contains(achievement.rawValue) { return }
            if clamped >= 100 { reportedAchievements.insert(achievement.rawValue) }
            let entry = GKAchievement(identifier: achievement.rawValue)
            entry.percentComplete = clamped
            entry.showsCompletionBanner = true
            achievements.append(entry)
        }

        report(.firstBlood, percent: stats.kills >= 1 ? 100 : 0)
        report(.hundredKills, percent: Double(stats.kills) / 100 * 100)
        report(.thousandKills, percent: Double(stats.kills) / 1000 * 100)
        report(.level25, percent: Double(level) / 25 * 100)
        report(.level55, percent: Double(level) / 55 * 100)
        report(.sharpshooter, percent: Double(stats.headshots) / 500 * 100)
        report(.bombExpert, percent: Double(stats.bombsPlanted + stats.bombsDefused) / 100 * 100)
        report(.unstoppable, percent: stats.bestStreak >= 10 ? 100 : Double(stats.bestStreak) / 10 * 100)

        guard !achievements.isEmpty else { return }
        Task {
            do {
                try await GKAchievement.report(achievements)
            } catch {
                Log.warn("Achievement report failed: \(error)", category: "gamecenter")
            }
        }
    }

    /// Presents the native Game Center dashboard.
    func showDashboard() {
        guard isAuthenticated else { return }
        let viewController = GKGameCenterViewController(state: .leaderboards)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        viewController.gameCenterDelegate = self
        root.present(viewController, animated: true)
    }
}

extension GameCenterService: GKGameCenterControllerDelegate {
    nonisolated func gameCenterViewControllerDidFinish(_ controller: GKGameCenterViewController) {
        Task { @MainActor in controller.dismiss(animated: true) }
    }
}

struct LeaderboardEntry: Identifiable {
    var id: Int { rank }
    var rank: Int
    var name: String
    var score: Int
    var isLocalPlayer: Bool
}
