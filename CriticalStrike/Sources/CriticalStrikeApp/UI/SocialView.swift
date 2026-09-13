import SwiftUI
import CriticalStrikeCore

/// Clan and friends. Deliberately self-contained: there is no account system behind it,
/// so a clan lives on the device and is shared by code, exactly like a lobby invite.
struct SocialView: View {
    @EnvironmentObject private var app: AppState
    @State private var tab: Tab = .clan
    @State private var showCreateClan = false
    @State private var clanNameDraft = ""
    @State private var clanTagDraft = ""
    @State private var friendCodeDraft = ""

    enum Tab: String, CaseIterable {
        case clan = "Clan"
        case friends = "Friends"
    }

    private var profile: PlayerProfile { app.profile }

    var body: some View {
        VStack(spacing: 12) {
            ScreenHeader(title: "Social", subtitle: "Your code: \(profile.friendCode)",
                         onBack: { app.goBack() },
                         trailing: AnyView(CurrencyBar(wallet: profile.wallet)))

            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            ScrollView {
                switch tab {
                case .clan: clanSection
                case .friends: friendsSection
                }
            }
        }
        .padding(16)
        .alert("Create a clan", isPresented: $showCreateClan) {
            TextField("Clan name", text: $clanNameDraft)
            TextField("Tag (2-4 characters)", text: $clanTagDraft)
            Button("Create") { app.createClan(name: clanNameDraft, tag: clanTagDraft) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Costs \(Clan.creationCostCoins) credits. You can rename it later.")
        }
    }

    // MARK: Clan

    @ViewBuilder
    private var clanSection: some View {
        if let clan = profile.clan {
            VStack(spacing: 12) {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Theme.accentGradient)
                                .frame(width: 62, height: 62)
                            Text(clan.tag)
                                .font(Theme.display(18))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(clan.name)
                                .font(Theme.display(20))
                                .foregroundStyle(Theme.textPrimary)
                            Text(clan.motto.isEmpty ? "No motto set" : clan.motto)
                                .font(Theme.caption(11))
                                .foregroundStyle(Theme.textSecondary)
                            Text("\(clan.memberCount)/\(Clan.maximumMembers) members • "
                                 + "+\(Int((clan.xpBonus - 1) * 100))% XP")
                                .font(Theme.caption(10))
                                .foregroundStyle(Theme.success)
                        }
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("CLAN LEVEL \(clan.level)")
                                .font(Theme.caption(10))
                                .foregroundStyle(Theme.textTertiary)
                            Spacer()
                            Text("\(clan.weeklyXP) / \(clan.xpToNextLevel) weekly XP")
                                .font(Theme.caption(10))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.surfaceElevated).frame(height: 6)
                            GeometryReader { geometry in
                                Capsule().fill(Theme.accentGradient)
                                    .frame(width: geometry.size.width * CGFloat(clan.levelProgress))
                            }
                            .frame(height: 6)
                        }
                        .frame(height: 6)
                    }
                }
                .padding(14)
                .panel()

                VStack(alignment: .leading, spacing: 8) {
                    Text("MEMBERS")
                        .font(Theme.caption(10))
                        .foregroundStyle(Theme.textTertiary)
                    ForEach(clan.memberIDs, id: \.self) { memberID in
                        HStack(spacing: 10) {
                            Circle().fill(Theme.surfaceElevated).frame(width: 28, height: 28)
                                .overlay(Text(String(memberID.prefix(1)))
                                    .font(Theme.caption(11))
                                    .foregroundStyle(Theme.textSecondary))
                            Text(memberID == profile.accountID ? profile.displayName : memberID)
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textPrimary)
                            if memberID == clan.leaderID {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.warning)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .panel()

                Button("Leave Clan") { app.leaveClan() }
                    .buttonStyle(SecondaryButtonStyle(wide: true))
                    .foregroundStyle(Theme.danger)
            }
        } else {
            VStack(spacing: 12) {
                EmptyStateView(icon: "person.3.fill",
                               title: "You are not in a clan",
                               message: "Clans share a tag, a weekly leaderboard and a small XP bonus.")
                Button("Create a Clan") {
                    clanNameDraft = ""
                    clanTagDraft = ""
                    showCreateClan = true
                }
                .buttonStyle(PrimaryButtonStyle())
                Text("\(Clan.creationCostCoins) credits")
                    .font(Theme.caption(10))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: Friends

    private var friendsSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("Friend code", text: $friendCodeDraft)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(14))
                    .foregroundStyle(Theme.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surfaceElevated))
                Button("Add") {
                    app.addFriend(code: friendCodeDraft)
                    friendCodeDraft = ""
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            if profile.friends.isEmpty {
                EmptyStateView(icon: "person.badge.plus",
                               title: "No friends added",
                               message: "Share your code — \(profile.friendCode) — to play together.")
            } else {
                ForEach(profile.friends) { friend in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(friend.isOnline ? Theme.success : Theme.textTertiary)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(friend.displayName)
                                .font(Theme.body(14))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Level \(friend.level) • \(friend.lastSeenDescription)")
                                .font(Theme.caption(10))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        Button("Invite") { app.inviteToLobby(friend) }
                            .buttonStyle(SecondaryButtonStyle())
                        Button {
                            app.removeFriend(friend)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .padding(10)
                    .panel(elevated: true)
                }
            }
        }
    }
}

/// The in-match ping wheel. Held open from the ping button; releasing over a segment
/// sends that ping. Communication without voice chat matters on mobile, where most
/// players have neither a microphone open nor the hands to type.
struct PingWheelView: View {
    let onSelect: (PingKind) -> Void
    let onDismiss: () -> Void
    @State private var highlighted: PingKind?

    private let options: [(PingKind, String, String)] = [
        (.enemy, "Enemy", "eye.fill"),
        (.danger, "Danger", "exclamationmark.triangle.fill"),
        (.going, "On my way", "figure.run"),
        (.needBackup, "Need backup", "shield.lefthalf.filled"),
        (.defend, "Defend", "flag.fill"),
        (.bombHere, "Bomb here", "burst.fill"),
        (.generic, "Look here", "mappin")
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { onDismiss() }

            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let angle = Double(index) / Double(options.count) * 2 * .pi - .pi / 2
                let radius: CGFloat = 96
                Button {
                    onSelect(option.0)
                    onDismiss()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: option.2)
                            .font(.system(size: 16, weight: .bold))
                        Text(option.1)
                            .font(Theme.caption(9))
                    }
                    .foregroundStyle(highlighted == option.0 ? Theme.accent : Theme.textPrimary)
                    .frame(width: 74, height: 58)
                    .background(Circle().fill(Color.black.opacity(0.55)).frame(width: 66, height: 66))
                }
                .offset(x: cos(angle) * radius, y: sin(angle) * radius)
            }

            Circle()
                .strokeBorder(Theme.stroke, lineWidth: 2)
                .frame(width: 44, height: 44)
        }
        .transition(.opacity)
    }
}
