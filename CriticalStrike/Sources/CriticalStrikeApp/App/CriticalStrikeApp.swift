import SwiftUI
import CriticalStrikeCore

@main
struct CriticalStrikeApp: App {
    @StateObject private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Landscape-only, full-screen: configured in Info.plist, but the renderer also
        // needs to know before the first frame.
        Log.minimumLevel = .info
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
                .onAppear { app.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: app.didBecomeActive()
            case .inactive: app.willResignActive()
            case .background: app.didEnterBackground()
            @unknown default: break
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            switch app.route {
            case .splash:
                SplashView()
            case .mainMenu:
                MainMenuView()
            case .play:
                PlayView()
            case .lobby:
                LobbyView()
            case .matchmaking:
                MatchmakingView()
            case .loading:
                LoadingView(progress: app.loadingProgress, mapID: app.pendingMapID)
            case .inMatch:
                GameView()
            case .results:
                MatchResultsView()
            case .loadout:
                LoadoutView()
            case .armory:
                ArmoryView()
            case .store:
                StoreView()
            case .battlePass:
                BattlePassView()
            case .missions:
                MissionsView()
            case .profile:
                ProfileView()
            case .leaderboard:
                LeaderboardView()
            case .settings:
                SettingsView()
            case .hudEditor:
                HUDLayoutEditorView()
            }

            if app.showCrateOpening, let rewards = app.pendingCrateRewards {
                CrateOpeningView(rewards: rewards) { app.dismissCrateOpening() }
                    .transition(.opacity)
            }

            if let toast = app.toast {
                VStack {
                    ToastView(toast: toast)
                        .padding(.top, 24)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: app.route)
        .animation(.spring(response: 0.3), value: app.toast?.id)
    }
}
