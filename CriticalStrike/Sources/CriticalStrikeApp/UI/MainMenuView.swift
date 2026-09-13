import SwiftUI
import CriticalStrikeCore

struct SplashView: View {
    @State private var glow = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 10) {
                Text("CRITICAL")
                    .font(Theme.display(46))
                    .foregroundStyle(Theme.textPrimary)
                Text("STRIKE")
                    .font(Theme.display(46))
                    .foregroundStyle(Theme.accent)
                    .shadow(color: Theme.accent.opacity(glow ? 0.8 : 0.2), radius: glow ? 22 : 6)
                ProgressView()
                    .tint(Theme.accent)
                    .padding(.top, 18)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}

struct MainMenuView: View {
    @EnvironmentObject private var app: AppState

    private var profile: PlayerProfile { app.profile }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 14) {
                sidebar
                    .frame(width: max(220, geometry.size.width * 0.26))
                mainPanel
            }
            .padding(16)
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                app.go(to: .profile)
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Theme.accentGradient).frame(width: 44, height: 44)
                        Text(String(profile.displayName.prefix(1)).uppercased())
                            .font(Theme.display(19))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName)
                            .font(Theme.title(15))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Text(profile.rank.displayName)
                                .font(Theme.caption(10))
                                .foregroundStyle(Color(hex: profile.rank.colorHex))
                            if profile.isPremium {
                                Text("VIP")
                                    .font(Theme.caption(9))
                                    .foregroundStyle(Theme.warning)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Theme.warning.opacity(0.15)))
                            }
                        }
                    }
                    Spacer()
                }
            }

            LevelProgressBar(profile: profile)

            Divider().overlay(Theme.stroke)

            menuButton("Loadout", icon: "person.crop.rectangle.stack.fill", route: .loadout)
            menuButton("Store", icon: "bag.fill", route: .store, highlight: true)
            menuButton("Battle Pass", icon: "rosette", route: .battlePass,
                       badge: unclaimedPassCount)
            menuButton("Missions", icon: "checklist", route: .missions,
                       badge: app.missionTracker.claimable().count)
            menuButton("Leaderboards", icon: "trophy.fill", route: .leaderboard)
            menuButton("Social", icon: "person.3.fill", route: .social)
            menuButton("Settings", icon: "gearshape.fill", route: .settings)

            Spacer()

            CurrencyBar(wallet: profile.wallet) { app.go(to: .store) }
        }
        .padding(14)
        .panel()
    }

    private var unclaimedPassCount: Int {
        profile.battlePass.unclaimedRewards(in: BattlePassDatabase.currentSeason).count
    }

    private func menuButton(_ title: String, icon: String, route: AppRoute,
                            highlight: Bool = false, badge: Int = 0) -> some View {
        Button {
            app.go(to: route)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(highlight ? Theme.accent : Theme.textSecondary)
                    .frame(width: 20)
                Text(title)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(Theme.caption(10))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.danger))
                }
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
    }

    // MARK: Main panel

    private var mainPanel: some View {
        VStack(spacing: 12) {
            // Featured banner: the current season.
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Theme.accent.opacity(0.55), Theme.surface],
                               startPoint: .topTrailing, endPoint: .bottomLeading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(BattlePassDatabase.currentSeason.name.uppercased())
                        .font(Theme.display(24))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(BattlePassDatabase.currentSeason.daysRemaining()) days remaining")
                        .font(Theme.caption(11))
                        .foregroundStyle(Theme.textSecondary)
                    Button("View Battle Pass") { app.go(to: .battlePass) }
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(.top, 4)
                }
                .padding(16)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))

            HStack(spacing: 10) {
                quickStat("K/D", String(format: "%.2f", profile.stats.kdRatio))
                quickStat("Wins", "\(profile.stats.matchesWon)")
                quickStat("Accuracy", String(format: "%.0f%%", profile.stats.accuracy * 100))
                quickStat("Hours", String(format: "%.1f", profile.stats.hoursPlayed))
            }

            Spacer()

            Button {
                app.go(to: .play)
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("PLAY")
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            HStack(spacing: 10) {
                Button("Quick Match") {
                    app.startMatch(mode: app.selectedMode, mapID: nil, offline: true)
                }
                .buttonStyle(SecondaryButtonStyle(wide: true))
                Button("Training") {
                    app.startMatch(mode: .training, mapID: "map_vault", offline: true)
                }
                .buttonStyle(SecondaryButtonStyle(wide: true))
            }
        }
        .padding(14)
        .panel()
    }

    private func quickStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.mono(17))
                .foregroundStyle(Theme.textPrimary)
            Text(label.uppercased())
                .font(Theme.caption(9))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall).fill(Theme.surfaceElevated))
    }
}

struct PlayView: View {
    @EnvironmentObject private var app: AppState
    @State private var selectedMap: MapID?

    var body: some View {
        VStack(spacing: 12) {
            ScreenHeader(title: "Play", subtitle: "Choose a mode", onBack: { app.goBack() },
                         trailing: AnyView(CurrencyBar(wallet: app.profile.wallet)))

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                    ForEach(GameModeDatabase.all.filter { $0.kind != .training }) { mode in
                        modeCard(mode)
                    }
                }
            }

            if let map = selectedMap {
                HStack {
                    Text("Map: \(MapDatabase.mapOrDefault(map).name)")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button("Random") { selectedMap = nil }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }

            mapPicker

            Button("FIND MATCH") {
                app.selectedMode = app.selectedMode
                app.beginMatchmaking(mode: app.selectedMode)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(16)
    }

    private func modeCard(_ mode: GameModeData) -> some View {
        let locked = mode.unlockLevel > app.profile.level
        let selected = app.selectedMode == mode.kind
        return Button {
            guard !locked else {
                app.showToast("Unlocks at level \(mode.unlockLevel)", style: .warning)
                return
            }
            app.selectedMode = mode.kind
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(mode.kind.shortName)
                        .font(Theme.display(17))
                        .foregroundStyle(selected ? Theme.accent : Theme.textPrimary)
                    Spacer()
                    Text("\(mode.teamSize)v\(mode.teamSize)")
                        .font(Theme.caption(10))
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(mode.name)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textPrimary)
                Text(mode.summary)
                    .font(Theme.caption(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if mode.xpMultiplier > 1 {
                    Text("\(String(format: "%.2f", mode.xpMultiplier))x XP")
                        .font(Theme.caption(9))
                        .foregroundStyle(Theme.warning)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                .fill(selected ? Theme.accent.opacity(0.14) : Theme.surfaceElevated))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                .strokeBorder(selected ? Theme.accent : Theme.stroke, lineWidth: selected ? 2 : 1))
            .overlay {
                if locked { LockedOverlay(requirement: "Level \(mode.unlockLevel)") }
            }
        }
    }

    private var mapPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MapDatabase.maps(for: app.selectedMode)) { map in
                    Button {
                        selectedMap = selectedMap == map.id ? nil : map.id
                        app.selectedMapID = map.id
                    } label: {
                        VStack(spacing: 3) {
                            MapPreviewImage(map: map, size: CGSize(width: 110, height: 56))
                                .frame(width: 110, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(alignment: .bottomLeading) {
                                    Text(map.name)
                                        .font(Theme.caption(10))
                                        .foregroundStyle(Theme.textPrimary)
                                        .padding(4)
                                        .shadow(color: .black, radius: 2)
                                }
                            Text(map.summary)
                                .font(Theme.caption(8))
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                                .frame(width: 110)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(selectedMap == map.id ? Theme.accent : .clear, lineWidth: 2))
                    }
                }
            }
        }
    }
}

/// Renders a map's top-down preview, cached so scrolling does not re-render it.
struct MapPreviewImage: View {
    let map: MapData
    let size: CGSize

    var body: some View {
        Group {
            if let image = MapPreviewCache.shared.preview(for: map, size: size) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Theme.surfaceElevated)
            }
        }
    }
}

struct LoadingView: View {
    let progress: Double
    let mapID: MapID

    var body: some View {
        let map = MapDatabase.mapOrDefault(mapID)
        ZStack {
            Theme.background.ignoresSafeArea()
            // The loading screen shows the actual layout, generated from the level data.
            MapPreviewImage(map: map, size: CGSize(width: 900, height: 500))
                .ignoresSafeArea()
                .opacity(0.28)
                .blur(radius: 1.5)
            VStack(spacing: 14) {
                Spacer()
                Text(map.name.uppercased())
                    .font(Theme.display(32))
                    .foregroundStyle(Theme.textPrimary)
                Text(map.summary)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    Text(tip)
                        .font(Theme.caption(11))
                        .foregroundStyle(Theme.textTertiary)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surfaceElevated).frame(height: 6)
                        GeometryReader { geometry in
                            Capsule().fill(Theme.accentGradient)
                                .frame(width: geometry.size.width * progress)
                        }
                        .frame(height: 6)
                    }
                    .frame(height: 6)
                }
                .frame(maxWidth: 520)
                .padding(.bottom, 30)
            }
            .padding(24)
        }
    }

    private var tip: String {
        LoadingTips.all[abs(mapID.value.hashValue) % LoadingTips.all.count]
    }
}

enum LoadingTips {
    static let all = [
        "Crouching tightens your spray. Standing still tightens it further.",
        "The first three shots of any rifle go almost straight up — pull down and they land.",
        "Sprinting is loud. Walk into a site and you will hear them before they hear you.",
        "Smoke blocks bots and players alike. It also blocks your own vision.",
        "Armour only covers the torso and head. Leg shots go straight through.",
        "Bullets penetrate wood and glass. They do not penetrate metal.",
        "Suppressors keep you off the enemy minimap at the cost of range.",
        "Flashbangs blind less when you are facing away from them.",
        "A headshot with any rifle kills at close range. Aim high.",
        "Reload between fights, not during them."
    ]
}
