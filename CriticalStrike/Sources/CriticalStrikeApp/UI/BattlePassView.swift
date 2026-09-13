import SwiftUI
import CriticalStrikeCore

struct BattlePassView: View {
    @EnvironmentObject private var app: AppState

    private var season: BattlePassSeason { BattlePassDatabase.currentSeason }
    private var progress: BattlePassProgress { app.profile.battlePass }

    var body: some View {
        VStack(spacing: 12) {
            ScreenHeader(title: season.name,
                         subtitle: "\(season.daysRemaining()) days remaining",
                         onBack: { app.goBack() },
                         trailing: AnyView(CurrencyBar(wallet: app.profile.wallet)))

            header

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(season.tiers) { tier in
                        tierColumn(tier)
                    }
                }
                .padding(.vertical, 4)
            }

            HStack(spacing: 10) {
                if !progress.isPremium {
                    Button("Unlock Season Pass") {
                        if let product = StoreCatalog.product(season.premiumProductID) {
                            app.purchase(product)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                Button("Claim All") { app.claimAllBattlePassRewards() }
                    .buttonStyle(SecondaryButtonStyle(wide: true))
            }
        }
        .padding(16)
    }

    private var header: some View {
        let tier = progress.currentTier(in: season)
        return VStack(spacing: 6) {
            HStack {
                Text("TIER \(tier)")
                    .font(Theme.display(22))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if progress.isPremium {
                    Text("PREMIUM")
                        .font(Theme.caption(10))
                        .foregroundStyle(Theme.warning)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.warning.opacity(0.18)))
                } else {
                    Text("FREE TRACK")
                        .font(Theme.caption(10))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text("\(progress.xp) XP")
                    .font(Theme.mono(13))
                    .foregroundStyle(Theme.textSecondary)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceElevated).frame(height: 8)
                GeometryReader { geometry in
                    Capsule().fill(Theme.accentGradient)
                        .frame(width: geometry.size.width * CGFloat(progress.progressWithinTier(in: season)))
                }
                .frame(height: 8)
            }
            .frame(height: 8)
        }
        .padding(12)
        .panel()
    }

    private func tierColumn(_ tier: BattlePassTier) -> some View {
        let currentTier = progress.currentTier(in: season)
        let reached = tier.tier <= currentTier
        return VStack(spacing: 6) {
            Text("\(tier.tier)")
                .font(Theme.mono(12))
                .foregroundStyle(reached ? Theme.accent : Theme.textTertiary)

            rewardCell(tier.premiumReward, tier: tier.tier, premium: true,
                       reached: reached, claimed: progress.claimedPremiumTiers.contains(tier.tier))
            rewardCell(tier.freeReward, tier: tier.tier, premium: false,
                       reached: reached, claimed: progress.claimedFreeTiers.contains(tier.tier))
        }
        .frame(width: 86)
    }

    private func rewardCell(_ reward: RewardKind?, tier: Int, premium: Bool,
                            reached: Bool, claimed: Bool) -> some View {
        Group {
            if let reward {
                Button {
                    app.claimBattlePassTier(tier, premium: premium)
                } label: {
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(premium ? Theme.rarityGradient(reward.rarity)
                                          : LinearGradient(colors: [Theme.surfaceElevated,
                                                                    Theme.surface],
                                                           startPoint: .top, endPoint: .bottom))
                            .frame(height: 62)
                            .overlay(
                                Image(systemName: claimed ? "checkmark" : rewardIcon(reward))
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(claimed ? Theme.success : .white.opacity(0.92)))
                            .overlay {
                                if !reached || (premium && !progress.isPremium) {
                                    LockedOverlay(requirement: premium && !progress.isPremium
                                                  ? "Premium" : "Tier \(tier)")
                                }
                            }
                        Text(reward.displayName)
                            .font(Theme.caption(8))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(height: 22)
                    }
                }
                .disabled(!reached || claimed || (premium && !progress.isPremium))
            } else {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(height: 62)
                    .overlay(Text("—").font(Theme.caption(10)).foregroundStyle(Theme.textTertiary))
                Spacer().frame(height: 22)
            }
        }
    }

    private func rewardIcon(_ reward: RewardKind) -> String {
        switch reward {
        case .currency: return "circle.hexagongrid.fill"
        case .cosmetic: return "paintbrush.fill"
        case .character: return "person.fill"
        case .weapon: return "scope"
        case .attachment: return "wrench.fill"
        case .crate: return "shippingbox.fill"
        case .xpBoost: return "bolt.fill"
        }
    }
}

struct MissionsView: View {
    @EnvironmentObject private var app: AppState
    @State private var scope: MissionScope = .daily

    var body: some View {
        VStack(spacing: 12) {
            ScreenHeader(title: "Missions", subtitle: "Resets daily at midnight",
                         onBack: { app.goBack() },
                         trailing: AnyView(CurrencyBar(wallet: app.profile.wallet)))

            Picker("", selection: $scope) {
                ForEach([MissionScope.daily, .weekly, .career], id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }
            .pickerStyle(.segmented)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(missions) { mission in
                        missionRow(mission)
                    }
                    if missions.isEmpty {
                        EmptyStateView(icon: "checklist",
                                       title: "No missions",
                                       message: "Check back after your next match.")
                    }
                }
            }
        }
        .padding(16)
    }

    private var missions: [Mission] {
        switch scope {
        case .daily:
            return MissionDatabase.dailyAssignment(for: Date(), level: app.profile.level)
        case .weekly:
            return MissionDatabase.weeklyAssignment(for: Date(), level: app.profile.level)
        default:
            return MissionDatabase.careerMissions
        }
    }

    private func missionRow(_ mission: Mission) -> some View {
        let state = app.missionTracker.progress[mission.id]
            ?? MissionProgress(missionID: mission.id)
        let target = mission.objective.target
        let complete = state.isComplete(target: target)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(mission.title)
                    .font(Theme.title(15))
                    .foregroundStyle(Theme.textPrimary)
                Text(mission.objective.description)
                    .font(Theme.caption(11))
                    .foregroundStyle(Theme.textSecondary)
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceElevated).frame(height: 5)
                    GeometryReader { geometry in
                        Capsule()
                            .fill(complete ? Theme.success : Theme.accent)
                            .frame(width: geometry.size.width * CGFloat(state.fraction(target: target)))
                    }
                    .frame(height: 5)
                }
                .frame(height: 5)
                Text("\(min(state.progress, target)) / \(target)")
                    .font(Theme.caption(9))
                    .foregroundStyle(Theme.textTertiary)
            }

            VStack(alignment: .trailing, spacing: 4) {
                Text("+\(mission.xpReward) XP")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.accentSecondary)
                if let (kind, amount) = mission.currencyReward {
                    Text("+\(amount) \(kind.displayName)")
                        .font(Theme.caption(10))
                        .foregroundStyle(Color(hex: kind.colorHex))
                }
                if state.claimed {
                    Text("CLAIMED").font(Theme.caption(9)).foregroundStyle(Theme.textTertiary)
                } else if complete {
                    Button("Claim") { app.claimMission(mission.id) }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .padding(12)
        .panel(elevated: true)
    }
}
