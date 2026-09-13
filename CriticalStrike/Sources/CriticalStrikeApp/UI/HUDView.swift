import SwiftUI
import CriticalStrikeCore

/// The combat HUD. Every element reads its position from the player's saved HUD layout,
/// so the customisation screen and the live HUD are guaranteed to agree.
struct HUDView: View {
    @ObservedObject var session: GameSession
    let size: CGSize
    @EnvironmentObject private var app: AppState

    private var hud: HUDState { session.hud }
    private var settings: GameSettings { app.profile.settings }

    var body: some View {
        ZStack {
            // ── Full-screen feedback layers ──
            if hud.isScoped {
                ScopeOverlay(zoom: hud.scopeLevel)
            }
            DamageVignette(healthFraction: hud.healthFraction, burning: hud.isBurning)
            if hud.flashAmount > 0.02 {
                Color.white.opacity(Double(min(1, hud.flashAmount)))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            if hud.stunAmount > 0.02 {
                Color.black.opacity(Double(hud.stunAmount) * 0.35)
                    .blur(radius: 8)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // ── Crosshair and hit feedback ──
            if !hud.isScoped && hud.isAlive {
                CrosshairView(spread: hud.spread,
                              kind: hud.crosshairKind,
                              colorHex: settings.crosshairColorHex,
                              scale: settings.crosshairScale,
                              onTarget: hud.hasTargetUnderCrosshair,
                              screenHeight: size.height)
            }
            HitMarkerView(timestamp: hud.hitMarkerTimestamp,
                          headshot: hud.lastHitWasHeadshot,
                          now: sessionTime)

            // ── Directional damage indicators ──
            ForEach(session.damageIndicators) { indicator in
                DamageDirectionIndicator(indicator: indicator, now: sessionTime)
            }

            // ── Positioned elements ──
            element("scoreHeader") { MatchHeaderView(hud: hud, colorBlind: settings.colorBlindMode) }
            element("healthBar") { VitalsView(hud: hud) }
            element("ammoCounter") { AmmoView(hud: hud) }
            if settings.showMinimap {
                element("minimap") {
                    MinimapView(hud: hud, map: session.map,
                                localPosition: session.localPlayerState?.position ?? .zero,
                                localYaw: session.localPlayerState?.angles.yaw ?? 0,
                                colorBlind: settings.colorBlindMode)
                }
            }
            if settings.showKillFeed {
                element("killFeed") { KillFeedView(entries: session.killFeed,
                                                   colorBlind: settings.colorBlindMode) }
            }

            // ── Objective banners ──
            VStack {
                Spacer().frame(height: 64)
                if hud.bombPlanted {
                    BombTimerView(hud: hud)
                }
                if !hud.objectiveHeadline.isEmpty && hud.phase != .live {
                    Text(hud.objectiveHeadline.uppercased())
                        .font(Theme.title(15))
                        .foregroundStyle(Theme.textSecondary)
                        .hudText()
                }
                Spacer()
            }

            AnnouncementView(text: hud.announcement, timestamp: hud.announcementTimestamp,
                             now: sessionTime)
            StreakBannerView(text: hud.streakBanner, timestamp: hud.streakBannerTimestamp,
                             now: sessionTime)

            // ── Interaction prompt ──
            if hud.canPlant || hud.canDefuse {
                InteractionPromptView(hud: hud)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.15), value: hud.isScoped)
    }

    private var sessionTime: Float {
        session.simulation.time
    }

    /// Places a HUD element at its configured normalized position.
    @ViewBuilder
    private func element<Content: View>(_ id: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        let layout = settings.layout(for: id)
        if !layout.hidden {
            content()
                .scaleEffect(CGFloat(layout.scale))
                .opacity(Double(layout.opacity) * Double(settings.hudOpacity))
                .position(x: size.width * CGFloat(layout.x), y: size.height * CGFloat(layout.y))
        }
    }
}

// MARK: - Vitals

struct VitalsView: View {
    let hud: HUDState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(hud.lowHealthPulse ? Theme.danger : Theme.textPrimary)
                Text("\(Int(hud.health))")
                    .font(Theme.mono(22))
                    .foregroundStyle(hud.lowHealthPulse ? Theme.danger : Theme.textPrimary)
                    .contentTransition(.numericText())
                if hud.armor > 0 {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.accentSecondary)
                    Text("\(Int(hud.armor))")
                        .font(Theme.mono(17))
                        .foregroundStyle(Theme.accentSecondary)
                }
            }
            .hudText()

            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.55)).frame(width: 148, height: 7)
                Capsule()
                    .fill(hud.lowHealthPulse ? Theme.danger : Theme.success)
                    .frame(width: 148 * CGFloat(hud.healthFraction), height: 7)
                    .animation(.easeOut(duration: 0.2), value: hud.healthFraction)
            }
            if hud.armor > 0 {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.55)).frame(width: 148, height: 4)
                    Capsule().fill(Theme.accentSecondary)
                        .frame(width: 148 * CGFloat(hud.armorFraction), height: 4)
                }
            }
            if !hud.callout.isEmpty {
                Text(hud.callout.uppercased())
                    .font(Theme.caption(10))
                    .foregroundStyle(Theme.textTertiary)
                    .hudText()
            }
        }
        .opacity(hud.lowHealthPulse ? pulse : 1)
    }

    private var pulse: Double {
        // Subtle breathing so low health reads without becoming a distraction.
        0.75 + 0.25 * abs(sin(Date().timeIntervalSince1970 * 3))
    }
}

// MARK: - Ammo

struct AmmoView: View {
    let hud: HUDState

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(hud.weaponName.uppercased())
                .font(Theme.caption(10))
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(hud.ammoInMagazine)")
                    .font(Theme.mono(30))
                    .foregroundStyle(ammoColor)
                    .contentTransition(.numericText())
                Text("/ \(hud.reserveAmmo)")
                    .font(Theme.mono(15))
                    .foregroundStyle(Theme.textSecondary)
            }
            if hud.isReloading {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.6)).frame(width: 96, height: 4)
                    Capsule().fill(Theme.accent)
                        .frame(width: 96 * CGFloat(hud.reloadProgress), height: 4)
                }
                Text("RELOADING")
                    .font(Theme.caption(9))
                    .foregroundStyle(Theme.accent)
            }
            HStack(spacing: 10) {
                EquipmentPip(count: hud.lethalCount, icon: "burst.fill", color: Theme.danger)
                EquipmentPip(count: hud.tacticalCount, icon: "sparkles", color: Theme.accentSecondary)
            }
        }
        .hudText()
    }

    private var ammoColor: Color {
        if hud.isOutOfAmmo { return Theme.danger }
        if hud.isLowAmmo { return Theme.warning }
        return Theme.textPrimary
    }
}

struct EquipmentPip: View {
    let count: Int
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text("\(count)")
                .font(Theme.mono(12))
        }
        .foregroundStyle(count > 0 ? color : Theme.textTertiary)
    }
}

// MARK: - Match header

struct MatchHeaderView: View {
    let hud: HUDState
    let colorBlind: ColorBlindMode

    var body: some View {
        HStack(spacing: 14) {
            scoreBlock(team: .strike, score: hud.strikeScore)
            VStack(spacing: 1) {
                Text(timeText)
                    .font(Theme.mono(18))
                    .foregroundStyle(timeColor)
                if hud.round > 0 && hud.phase != .live {
                    Text(hud.phase.displayName.uppercased())
                        .font(Theme.caption(9))
                        .foregroundStyle(Theme.textSecondary)
                } else if !hud.objectiveDetail.isEmpty {
                    Text(hud.objectiveDetail)
                        .font(Theme.caption(9))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(minWidth: 84)
            scoreBlock(team: .shield, score: hud.shieldScore)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .hudText()
    }

    private func scoreBlock(team: Team, score: Int) -> some View {
        Text("\(score)")
            .font(Theme.mono(22))
            .foregroundStyle(Color(hex: colorBlind.teamColor(team)))
            .frame(minWidth: 34)
            .contentTransition(.numericText())
    }

    private var timeText: String {
        hud.matchTimeRemaining > 0 ? hud.formattedMatchTime : hud.formattedPhaseTime
    }

    private var timeColor: Color {
        let remaining = hud.matchTimeRemaining > 0 ? hud.matchTimeRemaining : hud.phaseTimeRemaining
        return remaining < 30 ? Theme.warning : Theme.textPrimary
    }
}

// MARK: - Bomb

struct BombTimerView: View {
    let hud: HUDState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 14, weight: .bold))
            Text(hud.formattedBombTime)
                .font(Theme.mono(20))
        }
        .foregroundStyle(hud.bombTimeRemaining < 10 ? Theme.danger : Theme.warning)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .hudText()
        .scaleEffect(hud.bombTimeRemaining < 10 ? 1.08 : 1)
        .animation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true),
                   value: hud.bombTimeRemaining < 10)
    }
}

struct InteractionPromptView: View {
    let hud: HUDState

    var body: some View {
        VStack(spacing: 6) {
            Spacer()
            Text(hud.canPlant ? "HOLD TO PLANT" : "HOLD TO DEFUSE")
                .font(Theme.title(14))
                .foregroundStyle(Theme.textPrimary)
                .hudText()
            let progress = hud.canPlant ? hud.plantProgress : hud.defuseProgress
            if progress > 0 {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.6)).frame(width: 180, height: 6)
                    Capsule().fill(Theme.accent)
                        .frame(width: 180 * CGFloat(progress), height: 6)
                }
            }
            Spacer().frame(height: 130)
        }
    }
}

// MARK: - Feedback

struct HitMarkerView: View {
    let timestamp: Float
    let headshot: Bool
    let now: Float

    var body: some View {
        let age = now - timestamp
        let visible = age >= 0 && age < 0.25
        Group {
            if visible {
                let opacity = 1 - Double(age / 0.25)
                ZStack {
                    ForEach(0..<4, id: \.self) { index in
                        Rectangle()
                            .fill(headshot ? Theme.danger : Color.white)
                            .frame(width: 2, height: 9)
                            .offset(y: -11)
                            .rotationEffect(.degrees(Double(index) * 90 + 45))
                    }
                }
                .opacity(opacity)
                .scaleEffect(1 + CGFloat(age) * 1.6)
            }
        }
    }
}

struct DamageDirectionIndicator: View {
    let indicator: DamageIndicator
    let now: Float

    var body: some View {
        let age = now - indicator.timestamp
        let opacity = max(0, 1 - Double(age / 2.0))
        Path { path in
            path.move(to: CGPoint(x: -22, y: -88))
            path.addLine(to: CGPoint(x: 0, y: -104))
            path.addLine(to: CGPoint(x: 22, y: -88))
        }
        .stroke(Theme.danger.opacity(opacity), lineWidth: 4)
        .rotationEffect(.radians(Double(indicator.direction)))
        .allowsHitTesting(false)
    }
}

struct AnnouncementView: View {
    let text: String
    let timestamp: Float
    let now: Float

    var body: some View {
        let age = now - timestamp
        Group {
            if !text.isEmpty && age >= 0 && age < 2.4 {
                VStack {
                    Spacer().frame(height: 96)
                    Text(text)
                        .font(Theme.display(26))
                        .foregroundStyle(Theme.textPrimary)
                        .hudText()
                        .opacity(age > 1.8 ? Double((2.4 - age) / 0.6) : 1)
                        .scaleEffect(age < 0.18 ? 1.25 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: age < 0.18)
                    Spacer()
                }
            }
        }
    }
}

struct StreakBannerView: View {
    let text: String
    let timestamp: Float
    let now: Float

    var body: some View {
        let age = now - timestamp
        Group {
            if !text.isEmpty && age >= 0 && age < 2.0 {
                VStack {
                    Spacer()
                    Text(text)
                        .font(Theme.display(20))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .hudText()
                        .opacity(age > 1.5 ? Double((2.0 - age) / 0.5) : 1)
                    Spacer().frame(height: 150)
                }
            }
        }
    }
}

struct DamageVignette: View {
    let healthFraction: Float
    let burning: Bool

    var body: some View {
        let intensity = burning ? 0.5 : Double(max(0, 0.45 - healthFraction)) * 1.4
        Group {
            if intensity > 0.01 {
                RadialGradient(colors: [.clear, (burning ? Color.orange : Color.red).opacity(intensity)],
                               center: .center, startRadius: 140, endRadius: 560)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
    }
}

struct ScopeOverlay: View {
    let zoom: Int

    var body: some View {
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) * 0.44
            ZStack {
                // Black surround with a circular cut-out.
                Color.black
                    .mask(
                        Rectangle()
                            .overlay(Circle()
                                .frame(width: radius * 2, height: radius * 2)
                                .blendMode(.destinationOut))
                            .compositingGroup()
                    )
                Circle()
                    .strokeBorder(Color.black.opacity(0.9), lineWidth: 3)
                    .frame(width: radius * 2, height: radius * 2)
                // Mil-dot reticle.
                Path { path in
                    let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    path.move(to: CGPoint(x: center.x - radius, y: center.y))
                    path.addLine(to: CGPoint(x: center.x - 10, y: center.y))
                    path.move(to: CGPoint(x: center.x + 10, y: center.y))
                    path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
                    path.move(to: CGPoint(x: center.x, y: center.y - radius))
                    path.addLine(to: CGPoint(x: center.x, y: center.y - 10))
                    path.move(to: CGPoint(x: center.x, y: center.y + 10))
                    path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
                }
                .stroke(Color.black.opacity(0.85), lineWidth: 1.5)
                Circle().fill(Color.black).frame(width: 3, height: 3)

                VStack {
                    Spacer()
                    Text("\(zoom + 1)x")
                        .font(Theme.mono(12))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 30)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}
