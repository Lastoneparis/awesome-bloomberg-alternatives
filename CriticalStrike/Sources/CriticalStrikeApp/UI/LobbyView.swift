import SwiftUI
import CriticalStrikeCore

struct MatchmakingView: View {
    @EnvironmentObject private var app: AppState
    @State private var elapsed: Float = 0
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                ZStack {
                    Circle()
                        .strokeBorder(Theme.stroke, lineWidth: 3)
                        .frame(width: 118, height: 118)
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 118, height: 118)
                        .rotationEffect(.degrees(Double(elapsed) * 180))
                    VStack(spacing: 1) {
                        Text(String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60))
                            .font(Theme.mono(20))
                            .foregroundStyle(Theme.textPrimary)
                        Text("SEARCHING")
                            .font(Theme.caption(9))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                Text(GameModeDatabase.mode(app.selectedMode).name)
                    .font(Theme.title(19))
                    .foregroundStyle(Theme.textPrimary)
                Text(statusText)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                Button("Cancel") { app.cancelMatchmaking() }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.bottom, 24)
            }
        }
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
    }

    private var statusText: String {
        switch app.matchmakingState {
        case let .searching(_, estimated):
            return "Estimated wait \(Int(estimated))s • \(app.profile.settings.preferredRegion.displayName)"
        case .found:
            return "Match found — connecting"
        case let .failed(reason):
            return reason
        default:
            return "Preparing"
        }
    }

    private func startTimer() {
        elapsed = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            Task { @MainActor in
                elapsed += 0.2
                app.tickMatchmaking(dt: 0.2)
            }
        }
    }
}

struct LobbyView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(spacing: 12) {
            ScreenHeader(title: "Lobby",
                         subtitle: "Invite code \(app.lobby.inviteCode)",
                         onBack: { app.goBack() })

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 8) {
                    Text("SQUAD")
                        .font(Theme.caption(10))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(app.lobby.members) { member in
                        HStack(spacing: 9) {
                            Circle().fill(Theme.accentGradient).frame(width: 30, height: 30)
                                .overlay(Text(String(member.displayName.prefix(1)))
                                    .font(Theme.caption(12)).foregroundStyle(.white))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(member.displayName)
                                    .font(Theme.body(13))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Level \(member.level)")
                                    .font(Theme.caption(9))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            Spacer()
                            if member.isLeader {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.warning)
                            }
                            Image(systemName: member.isReady ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(member.isReady ? Theme.success : Theme.textTertiary)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surfaceElevated))
                    }
                    if app.lobby.members.count < app.lobby.maxSize {
                        Button {
                            app.showToast("Invite link copied", style: .success)
                        } label: {
                            HStack {
                                Image(systemName: "plus")
                                Text("Invite")
                            }
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                        }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 10) {
                    Text("MATCH SETTINGS")
                        .font(Theme.caption(10))
                        .foregroundStyle(Theme.textTertiary)

                    settingRow("Mode", GameModeDatabase.mode(app.lobby.mode).name)
                    settingRow("Map", MapDatabase.mapOrDefault(app.lobby.mapID).name)
                    settingRow("Region", app.lobby.region.displayName)
                    settingRow("Bots", app.lobby.fillWithBots
                               ? app.lobby.botDifficulty.displayName : "Off")

                    Toggle("Fill with bots", isOn: Binding(
                        get: { app.lobby.fillWithBots },
                        set: { app.lobby.fillWithBots = $0 }))
                        .font(Theme.body(13))
                        .tint(Theme.accent)

                    Spacer()

                    Button("START MATCH") {
                        app.startMatch(mode: app.lobby.mode, mapID: app.lobby.mapID, offline: true)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .panel()
            }
        }
        .padding(16)
    }

    private func settingRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.body(13))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

struct MatchResultsView: View {
    @EnvironmentObject private var app: AppState
    @State private var revealedXP = false

    var body: some View {
        VStack(spacing: 12) {
            if let result = app.lastResult {
                Text(result.localPlayerWon ? "VICTORY" : (result.winner == .none ? "MATCH OVER" : "DEFEAT"))
                    .font(Theme.display(36))
                    .foregroundStyle(result.localPlayerWon ? Theme.success : Theme.danger)

                Text("\(GameModeDatabase.mode(result.mode).name) • \(MapDatabase.mapOrDefault(result.map).name)")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)

                if let rewards = app.matchRewards {
                    rewardsPanel(rewards)
                }

                ScrollView {
                    ScoreboardTable(rows: result.scoreboard, team: .none,
                                    localPlayer: app.session?.localPlayerID ?? .none,
                                    colorBlind: app.profile.settings.colorBlindMode)
                }
                .frame(maxHeight: 200)

                HStack(spacing: 10) {
                    Button("Play Again") {
                        app.startMatch(mode: result.mode, mapID: nil, offline: true)
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("Main Menu") { app.go(to: .mainMenu) }
                        .buttonStyle(SecondaryButtonStyle(wide: true))
                }
            } else {
                EmptyStateView(icon: "questionmark.circle",
                               title: "No results",
                               message: "This match did not finish.")
                Button("Main Menu") { app.go(to: .mainMenu) }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(16)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.3)) { revealedXP = true }
        }
    }

    private func rewardsPanel(_ rewards: MatchRewards) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 18) {
                rewardStat("XP", "+\(rewards.xp)", Theme.accentSecondary)
                rewardStat("Credits", "+\(rewards.coins)", Theme.warning)
                rewardStat("Pass XP", "+\(rewards.battlePassXP)", Theme.rarity(.epic))
            }
            LevelProgressBar(profile: app.profile)
                .opacity(revealedXP ? 1 : 0.3)

            if !rewards.levelsGained.isEmpty {
                Text("LEVEL UP → \(rewards.levelsGained.last ?? 0)")
                    .font(Theme.title(15))
                    .foregroundStyle(Theme.warning)
            }
            if !rewards.newAttachments.isEmpty {
                Text("New attachments: " + rewards.newAttachments.map(\.name).joined(separator: ", "))
                    .font(Theme.caption(11))
                    .foregroundStyle(Theme.success)
            }
            if app.profile.entitlements.showsAds {
                Button {
                    app.watchRewardedAd(reason: "doubleMatchRewards") {
                        app.update { profile in
                            profile.wallet.credit(rewards.coins, .coins)
                            profile.awardXP(rewards.xp)
                        }
                        app.showToast("Rewards doubled", style: .reward)
                    }
                } label: {
                    HStack {
                        Image(systemName: "play.rectangle.fill")
                        Text("Watch an ad to double rewards")
                    }
                }
                .buttonStyle(SecondaryButtonStyle(wide: true))
            }
        }
        .padding(12)
        .panel()
    }

    private func rewardStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.mono(19)).foregroundStyle(color)
            Text(label.uppercased()).font(Theme.caption(9)).foregroundStyle(Theme.textTertiary)
        }
    }
}
