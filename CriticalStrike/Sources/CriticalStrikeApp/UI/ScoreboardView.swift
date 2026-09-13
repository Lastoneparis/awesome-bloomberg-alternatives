import SwiftUI
import CriticalStrikeCore

struct ScoreboardOverlay: View {
    @ObservedObject var session: GameSession
    @EnvironmentObject private var app: AppState

    private var colorBlind: ColorBlindMode { app.profile.settings.colorBlindMode }

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 10) {
                header
                if session.mode.kind.isTeamBased {
                    HStack(alignment: .top, spacing: 12) {
                        teamColumn(.strike)
                        teamColumn(.shield)
                    }
                } else {
                    ScoreboardTable(rows: session.scoreboard, team: .none,
                                    localPlayer: session.localPlayerID, colorBlind: colorBlind)
                }
            }
            .padding(16)
        }
        .transition(.opacity)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text(session.mode.name.uppercased())
                .font(Theme.title(16))
                .foregroundStyle(Theme.textSecondary)
            Text(session.map.name)
                .font(Theme.body(14))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "wifi")
                    .font(.system(size: 11, weight: .bold))
                Text(session.hud.connectionQuality.rawValue.capitalized)
                    .font(Theme.caption(11))
            }
            .foregroundStyle(Color(hex: session.hud.connectionQuality.colorHex))
        }
    }

    private func teamColumn(_ team: Team) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(team.displayName.uppercased())
                    .font(Theme.title(14))
                    .foregroundStyle(Color(hex: colorBlind.teamColor(team)))
                Spacer()
                Text("\(team == .strike ? session.hud.strikeScore : session.hud.shieldScore)")
                    .font(Theme.mono(20))
                    .foregroundStyle(Color(hex: colorBlind.teamColor(team)))
            }
            ScoreboardTable(rows: session.scoreboard.filter { $0.team == team },
                            team: team, localPlayer: session.localPlayerID, colorBlind: colorBlind)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ScoreboardTable: View {
    let rows: [PlayerResult]
    let team: Team
    let localPlayer: PlayerID
    let colorBlind: ColorBlindMode

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PLAYER").frame(maxWidth: .infinity, alignment: .leading)
                Text("K").frame(width: 30)
                Text("D").frame(width: 30)
                Text("A").frame(width: 30)
                Text("DMG").frame(width: 46)
                Text("SCORE").frame(width: 54)
            }
            .font(Theme.caption(9))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

            ForEach(rows) { row in
                HStack {
                    HStack(spacing: 5) {
                        if row.mvp {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.warning)
                        }
                        Text(row.name)
                            .lineLimit(1)
                        if row.isBot {
                            Text("BOT")
                                .font(Theme.caption(8))
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Theme.surfaceElevated))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(row.kills)").frame(width: 30)
                    Text("\(row.deaths)").frame(width: 30)
                    Text("\(row.assists)").frame(width: 30)
                    Text("\(Int(row.damage))").frame(width: 46)
                    Text("\(row.score)").frame(width: 54)
                }
                .font(Theme.body(13))
                .foregroundStyle(row.player == localPlayer ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(row.player == localPlayer
                            ? Color(hex: colorBlind.teamColor(row.team)).opacity(0.18)
                            : Color.clear)
            }
        }
        .panel()
    }
}

/// The buy menu for round-based modes. Grouped by class, with affordability and
/// time-to-kill shown so the choice is informed rather than memorised.
struct BuyMenuView: View {
    @ObservedObject var session: GameSession
    @State private var category: WeaponClass = .assaultRifle

    private var money: Int { session.hud.money }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { session.toggleBuyMenu() }

            VStack(spacing: 10) {
                HStack {
                    Text("BUY").font(Theme.title(18)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("$\(money)").font(Theme.mono(20)).foregroundStyle(Theme.warning)
                    Button {
                        session.toggleBuyMenu()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { option in
                            Button(option.displayName) { category = option }
                                .buttonStyle(SecondaryButtonStyle())
                                .opacity(category == option ? 1 : 0.55)
                        }
                    }
                }

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                        ForEach(WeaponDatabase.weapons(of: category)) { weapon in
                            buyCard(weapon)
                        }
                    }
                }
                .frame(maxHeight: 210)

                HStack(spacing: 8) {
                    equipmentButton("Armor", cost: 650) { session.buyArmor(helmet: false) }
                    equipmentButton("Armor + Helmet", cost: 1000) { session.buyArmor(helmet: true) }
                    ForEach(GrenadeDatabase.all.prefix(4)) { grenade in
                        equipmentButton(grenade.name, cost: grenade.buyCost) {
                            session.buy(grenade: grenade.id)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 680)
            .panel(elevated: true)
            .padding(.bottom, 20)
        }
    }

    private var categories: [WeaponClass] {
        [.assaultRifle, .submachineGun, .sniperRifle, .shotgun, .lightMachineGun, .pistol]
    }

    private func buyCard(_ weapon: WeaponData) -> some View {
        let affordable = money >= weapon.buyCost
        return Button {
            session.buy(weapon: weapon.id)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(weapon.name)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack {
                    Text("$\(weapon.buyCost)")
                        .font(Theme.mono(13))
                        .foregroundStyle(affordable ? Theme.success : Theme.danger)
                    Spacer()
                    Text(String(format: "%.2fs TTK", DamageModel.timeToKill(weapon: weapon)))
                        .font(Theme.caption(9))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surfaceElevated))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(affordable ? Theme.stroke : Theme.danger.opacity(0.4), lineWidth: 1))
        }
        .disabled(!affordable)
        .opacity(affordable ? 1 : 0.55)
    }

    private func equipmentButton(_ title: String, cost: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title).font(Theme.caption(10)).lineLimit(1)
                Text("$\(cost)").font(Theme.mono(11))
                    .foregroundStyle(money >= cost ? Theme.success : Theme.danger)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.surfaceElevated))
        }
        .foregroundStyle(Theme.textPrimary)
        .disabled(money < cost)
        .opacity(money >= cost ? 1 : 0.55)
    }
}
