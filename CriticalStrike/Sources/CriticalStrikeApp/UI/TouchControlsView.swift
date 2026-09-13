import SwiftUI
import CriticalStrikeCore

/// The touch layer: a movement stick, a look area, and every action button.
///
/// Layout comes entirely from the player's saved HUD layout, so the customisation screen
/// moves the real controls. Buttons use `DragGesture(minimumDistance: 0)` rather than
/// `Button` because a shooter needs press-and-hold semantics and zero tap delay.
struct TouchControlsView: View {
    @ObservedObject var session: GameSession
    let size: CGSize
    @EnvironmentObject private var app: AppState

    private var settings: GameSettings { app.profile.settings }
    private var controls: TouchControls { session.controls }
    private var hud: HUDState { session.hud }

    var body: some View {
        ZStack {
            lookArea
            movementStick
            actionButtons
        }
        .opacity(hud.isAlive ? 1 : 0.35)
        .allowsHitTesting(hud.isAlive && !session.showScoreboard && !session.showBuyMenu)
    }

    // MARK: - Look

    /// The whole right half of the screen turns the camera. Multi-touch matters here: a
    /// player firing with one thumb must still be able to aim with the other, which is why
    /// this is a separate gesture region rather than a gesture on the root view.
    private var lookArea: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: size.width * (settings.leftHanded ? 0.5 : 0.55))
            .position(x: settings.leftHanded ? size.width * 0.25 : size.width * 0.72,
                      y: size.height / 2)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Deltas, not absolute positions: the camera should keep turning
                        // as long as the thumb keeps moving.
                        let previous = lastLookLocation ?? value.startLocation
                        controls.addLookDelta(CGSize(width: value.location.x - previous.x,
                                                     height: value.location.y - previous.y))
                        lastLookLocation = value.location
                    }
                    .onEnded { _ in
                        lastLookLocation = nil
                        controls.endLook()
                    }
            )
    }

    @State private var lastLookLocation: CGPoint?

    // MARK: - Movement

    private var movementStick: some View {
        let layout = settings.layout(for: "movementStick")
        let centre = CGPoint(x: size.width * CGFloat(settings.leftHanded ? 1 - layout.x : layout.x),
                             y: size.height * CGFloat(layout.y))
        return VirtualJoystick(
            deadZone: CGFloat(settings.joystickDeadZone),
            followsTouch: settings.joystickFollowsTouch,
            radius: 58 * CGFloat(layout.scale),
            onChange: { vector in controls.moveVector = vector },
            onEnd: { controls.moveVector = .zero })
            .position(centre)
            .opacity(Double(layout.opacity) * Double(settings.hudOpacity))
    }

    // MARK: - Buttons

    private var actionButtons: some View {
        ZStack {
            actionButton("fireButton", systemImage: "scope", size: 74, tint: Theme.danger,
                         held: controls.isFiring) { pressed in
                controls.setFiring(pressed)
            }
            actionButton("adsButton", systemImage: "dot.viewfinder", size: 54,
                         tint: Theme.accentSecondary, held: controls.isAiming) { pressed in
                controls.setAiming(pressed)
            }
            actionButton("jumpButton", systemImage: "arrow.up", size: 50, tint: Theme.textPrimary,
                         held: false) { pressed in
                if pressed { controls.pressJump() }
            }
            actionButton("crouchButton", systemImage: "arrow.down.to.line", size: 50,
                         tint: Theme.textPrimary, held: controls.isCrouching) { pressed in
                if settings.tapToCrouchSlide {
                    if pressed { controls.setCrouch(!controls.isCrouching) }
                } else {
                    controls.setCrouch(pressed)
                }
            }
            actionButton("reloadButton", systemImage: "arrow.triangle.2.circlepath", size: 50,
                         tint: hud.isLowAmmo ? Theme.warning : Theme.textPrimary,
                         held: hud.isReloading) { pressed in
                if pressed { controls.pressReload() }
            }
            actionButton("lethalButton", systemImage: "burst.fill", size: 46,
                         tint: hud.lethalCount > 0 ? Theme.danger : Theme.textTertiary,
                         held: false, badge: "\(hud.lethalCount)") { pressed in
                if pressed && hud.lethalCount > 0 { controls.pressLethal() }
            }
            actionButton("tacticalButton", systemImage: "sparkles", size: 46,
                         tint: hud.tacticalCount > 0 ? Theme.accentSecondary : Theme.textTertiary,
                         held: false, badge: "\(hud.tacticalCount)") { pressed in
                if pressed && hud.tacticalCount > 0 { controls.pressTactical() }
            }
            actionButton("meleeButton", systemImage: "scissors", size: 46,
                         tint: Theme.textPrimary, held: false) { pressed in
                if pressed { controls.pressMelee() }
            }
            actionButton("weaponSwap", systemImage: "arrow.left.arrow.right", size: 46,
                         tint: Theme.textPrimary, held: false) { pressed in
                if pressed { controls.pressSwap() }
            }

            // Contextual interact button — only present when it can do something.
            if hud.canPlant || hud.canDefuse {
                actionButton("useButton", systemImage: "hand.tap.fill", size: 58,
                             tint: Theme.accent, held: controls.isUsing) { pressed in
                    controls.setUsing(pressed)
                }
            }

            // Scope toggle for variable-zoom optics.
            if hud.isScoped {
                actionButton("scopeToggle", systemImage: "plus.magnifyingglass", size: 42,
                             tint: Theme.textPrimary, held: false,
                             fallbackPosition: CGPoint(x: 0.62, y: 0.30)) { pressed in
                    if pressed { controls.pressScopeToggle() }
                }
            }

            // Scoreboard (hold) and ping.
            actionButton("pingButton", systemImage: "mappin.and.ellipse", size: 42,
                         tint: Theme.textPrimary, held: false) { pressed in
                if pressed { session.sendPing(kind: .enemy) }
            }
            scoreboardButton
            if session.mode.usesBuyMenu && hud.phase == .freezeTime {
                buyButton
            }
        }
    }

    private var scoreboardButton: some View {
        Image(systemName: "list.bullet.rectangle")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.black.opacity(0.45)))
            .position(x: size.width * 0.5 - 40, y: 26)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in session.toggleScoreboard(true) }
                .onEnded { _ in session.toggleScoreboard(false) })
    }

    private var buyButton: some View {
        HStack(spacing: 5) {
            Image(systemName: "cart.fill").font(.system(size: 12, weight: .bold))
            Text("$\(hud.money)").font(Theme.mono(13))
        }
        .foregroundStyle(Theme.warning)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.5)))
        .position(x: size.width * 0.5 + 60, y: 26)
        .onTapGesture { session.toggleBuyMenu() }
    }

    /// One action button, positioned from the saved layout and mirrored for left-handed
    /// players.
    private func actionButton(_ id: String, systemImage: String, size buttonSize: CGFloat,
                              tint: Color, held: Bool, badge: String? = nil,
                              fallbackPosition: CGPoint? = nil,
                              action: @escaping (Bool) -> Void) -> some View {
        let layout = settings.layout(for: id)
        let x = fallbackPosition?.x ?? CGFloat(layout.x)
        let y = fallbackPosition?.y ?? CGFloat(layout.y)
        let mirroredX = settings.leftHanded ? 1 - x : x
        let scaled = buttonSize * CGFloat(layout.scale)

        return ZStack {
            Circle()
                .fill(held ? tint.opacity(0.35) : Color.black.opacity(0.34))
                .overlay(Circle().strokeBorder(tint.opacity(held ? 0.95 : 0.55), lineWidth: 1.5))
            Image(systemName: systemImage)
                .font(.system(size: scaled * 0.4, weight: .bold))
                .foregroundStyle(tint)
            if let badge {
                Text(badge)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(3)
                    .background(Circle().fill(Color.black.opacity(0.7)))
                    .offset(x: scaled * 0.32, y: -scaled * 0.32)
            }
        }
        .frame(width: scaled, height: scaled)
        .scaleEffect(held ? 0.94 : 1)
        .opacity(Double(layout.opacity) * Double(settings.hudOpacity))
        .position(x: size.width * mirroredX, y: size.height * y)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !held || id == "fireButton" || id == "adsButton" || id == "useButton" else { return }
                    action(true)
                }
                .onEnded { _ in action(false) }
        )
        .animation(.easeOut(duration: 0.08), value: held)
    }
}

/// Analog stick. Follows the touch when enabled, which is what makes running while
/// re-gripping the phone feel natural.
struct VirtualJoystick: View {
    let deadZone: CGFloat
    let followsTouch: Bool
    let radius: CGFloat
    let onChange: (CGVector) -> Void
    let onEnd: () -> Void

    @State private var knobOffset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var isActive = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(isActive ? 0.35 : 0.2), lineWidth: 2)
                .background(Circle().fill(Color.black.opacity(0.2)))
                .frame(width: radius * 2, height: radius * 2)
                .offset(baseOffset)

            Circle()
                .fill(Color.white.opacity(isActive ? 0.5 : 0.3))
                .frame(width: radius * 0.72, height: radius * 0.72)
                .offset(CGSize(width: baseOffset.width + knobOffset.width,
                               height: baseOffset.height + knobOffset.height))
        }
        .frame(width: radius * 2.6, height: radius * 2.6)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isActive {
                        isActive = true
                        if followsTouch {
                            // Re-centre the stick under the thumb on first touch.
                            baseOffset = CGSize(width: value.startLocation.x - radius * 1.3,
                                                height: value.startLocation.y - radius * 1.3)
                        }
                    }
                    var delta = CGSize(width: value.location.x - value.startLocation.x,
                                       height: value.location.y - value.startLocation.y)
                    let distance = sqrt(delta.width * delta.width + delta.height * delta.height)
                    if distance > radius {
                        delta.width = delta.width / distance * radius
                        delta.height = delta.height / distance * radius
                    }
                    knobOffset = delta

                    var vector = CGVector(dx: delta.width / radius, dy: delta.height / radius)
                    let magnitude = sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
                    if magnitude < deadZone {
                        vector = .zero
                    } else {
                        // Rescale past the dead zone so the first responsive input is
                        // still a small movement, not a jump to half speed.
                        let scaled = (magnitude - deadZone) / (1 - deadZone)
                        vector.dx = vector.dx / magnitude * scaled
                        vector.dy = vector.dy / magnitude * scaled
                    }
                    onChange(vector)
                }
                .onEnded { _ in
                    isActive = false
                    knobOffset = .zero
                    baseOffset = .zero
                    onEnd()
                }
        )
        .animation(.easeOut(duration: 0.12), value: isActive)
    }
}
