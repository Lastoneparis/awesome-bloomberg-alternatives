import SwiftUI
import CriticalStrikeCore

struct ProfileView: View {
    @EnvironmentObject private var app: AppState
    @State private var editingName = false
    @State private var nameDraft = ""

    private var profile: PlayerProfile { app.profile }
    private var stats: PlayerStats { profile.stats }

    var body: some View {
        VStack(spacing: 12) {
            ScreenHeader(title: "Profile", onBack: { app.goBack() },
                         trailing: AnyView(CurrencyBar(wallet: profile.wallet)))

            ScrollView {
                VStack(spacing: 12) {
                    identityCard
                    statsGrid
                    weaponBreakdown
                    if profile.level >= XPCurve.maxLevel {
                        prestigeCard
                    }
                }
            }
        }
        .padding(16)
        .alert("Change name", isPresented: $editingName) {
            TextField("Display name", text: $nameDraft)
            Button("Save") { app.setDisplayName(nameDraft) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var identityCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.accentGradient).frame(width: 74, height: 74)
                Text(String(profile.displayName.prefix(1)).uppercased())
                    .font(Theme.display(30))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(profile.displayName)
                        .font(Theme.display(22))
                        .foregroundStyle(Theme.textPrimary)
                    Button {
                        nameDraft = profile.displayName
                        editingName = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                HStack(spacing: 8) {
                    Text("\(profile.rank.displayName) \(romanNumeral(profile.rankDivision))")
                        .font(Theme.body(13))
                        .foregroundStyle(Color(hex: profile.rank.colorHex))
                    Text("\(profile.competitiveRating) MMR")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textTertiary)
                }
                LevelProgressBar(profile: profile)
            }
            Spacer()
        }
        .padding(14)
        .panel()
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
            statTile("Kills", "\(stats.kills)")
            statTile("Deaths", "\(stats.deaths)")
            statTile("K/D", String(format: "%.2f", stats.kdRatio))
            statTile("Assists", "\(stats.assists)")
            statTile("Matches", "\(stats.matchesPlayed)")
            statTile("Wins", "\(stats.matchesWon)")
            statTile("Win rate", String(format: "%.0f%%", stats.winRate * 100))
            statTile("Accuracy", String(format: "%.1f%%", stats.accuracy * 100))
            statTile("Headshot %", String(format: "%.1f%%", stats.headshotRate * 100))
            statTile("Best streak", "\(stats.bestStreak)")
            statTile("MVPs", "\(stats.mvpCount)")
            statTile("Hours", String(format: "%.1f", stats.hoursPlayed))
        }
    }

    private var weaponBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WEAPON PROGRESSION")
                .font(Theme.caption(10))
                .foregroundStyle(Theme.textTertiary)
            ForEach(topWeapons, id: \.0) { weaponID, kills in
                let weapon = WeaponDatabase.weaponOrDefault(weaponID)
                HStack {
                    Text(weapon.name).font(Theme.body(13)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("Lv \(profile.unlocks.weaponLevel(weaponID))")
                        .font(Theme.caption(10))
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(kills) kills")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 78, alignment: .trailing)
                }
            }
            if topWeapons.isEmpty {
                Text("Play a match to start tracking weapon progression.")
                    .font(Theme.caption(11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .panel()
    }

    private var topWeapons: [(WeaponID, Int)] {
        profile.unlocks.weaponKills
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map { (WeaponID($0.key), $0.value) }
    }

    private var prestigeCard: some View {
        VStack(spacing: 8) {
            Text("MAX LEVEL REACHED")
                .font(Theme.title(16))
                .foregroundStyle(Theme.warning)
            Text("Prestige resets your level but keeps every unlock, stat and purchase, and pays a bonus.")
                .font(Theme.caption(11))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Prestige") {
                app.update { profile in
                    _ = profile.prestigeIfPossible()
                }
                app.showToast("Prestige \(profile.prestige)", style: .reward)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(14)
        .panel(elevated: true)
    }

    private func statTile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.mono(17)).foregroundStyle(Theme.textPrimary)
            Text(label.uppercased()).font(Theme.caption(9)).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall).fill(Theme.surfaceElevated))
    }

    private func romanNumeral(_ value: Int) -> String {
        ["", "I", "II", "III"][max(0, min(3, value))]
    }
}

struct LeaderboardView: View {
    @EnvironmentObject private var app: AppState
    @State private var board: GameCenterService.Leaderboard = .totalKills
    @State private var entries: [LeaderboardEntry] = []
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 12) {
            ScreenHeader(title: "Leaderboards", onBack: { app.goBack() })

            Picker("", selection: $board) {
                ForEach(GameCenterService.Leaderboard.allCases, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)

            if !app.gameCenter.isAuthenticated {
                EmptyStateView(icon: "person.crop.circle.badge.exclamationmark",
                               title: "Game Center required",
                               message: "Sign in to Game Center in iOS Settings to see leaderboards.")
                Button("Open Game Center") { app.gameCenter.showDashboard() }
                    .buttonStyle(SecondaryButtonStyle())
            } else if isLoading {
                ProgressView().tint(Theme.accent)
                Spacer()
            } else if entries.isEmpty {
                EmptyStateView(icon: "trophy",
                               title: "No entries yet",
                               message: "Finish a match to appear on the board.")
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(entries) { entry in
                            HStack {
                                Text("#\(entry.rank)")
                                    .font(Theme.mono(13))
                                    .foregroundStyle(entry.rank <= 3 ? Theme.warning : Theme.textTertiary)
                                    .frame(width: 44, alignment: .leading)
                                Text(entry.name)
                                    .font(Theme.body(14))
                                    .foregroundStyle(entry.isLocalPlayer ? Theme.accent : Theme.textPrimary)
                                Spacer()
                                Text("\(entry.score)")
                                    .font(Theme.mono(14))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(entry.isLocalPlayer ? Theme.accent.opacity(0.14) : Theme.surfaceElevated))
                        }
                    }
                }
            }
        }
        .padding(16)
        .task(id: board) { await load() }
    }

    private func load() async {
        guard app.gameCenter.isAuthenticated else { return }
        isLoading = true
        entries = await app.gameCenter.loadLeaderboard(board)
        isLoading = false
    }
}
