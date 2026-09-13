import Foundation
import SwiftUI
import CriticalStrikeCore

/// Collects touch input and turns it into an `InputCommand`.
///
/// The whole control scheme lives here so the HUD views stay dumb: they report gestures,
/// this object decides what they mean. It is an ObservableObject because the HUD needs to
/// draw button highlight states, but the game loop reads `currentCommand()` directly
/// rather than through SwiftUI, so input latency never depends on a view update.
@MainActor
final class TouchControls: ObservableObject {
    // Movement
    @Published var moveVector: CGVector = .zero
    @Published var joystickOrigin: CGPoint = .zero
    @Published var joystickActive = false

    // Buttons (published so they can light up)
    @Published var isFiring = false
    @Published var isAiming = false
    @Published var isCrouching = false
    @Published var isSprinting = false
    @Published var isUsing = false

    // One-shot latches consumed by the next command build.
    private var jumpLatched = false
    private var reloadLatched = false
    private var meleeLatched = false
    private var lethalLatched = false
    private var tacticalLatched = false
    private var swapLatched = false
    private var scopeLatched = false
    private var requestedSlot: LoadoutSlot?

    // Look
    private(set) var yaw: Float = 0
    private(set) var pitch: Float = 0
    private var pendingLookDelta: CGSize = .zero
    private var lookTouchActive = false

    // Gyro
    private var gyroDelta: CGSize = .zero

    var settings: GameSettings = GameSettings()
    var aimAssist = AimAssist()

    private var sequence: UInt16 = 0

    // MARK: - Look

    /// Called from the look drag gesture. Deltas are in points and are converted to
    /// radians using the sensitivity curve below.
    func addLookDelta(_ delta: CGSize) {
        pendingLookDelta.width += delta.width
        pendingLookDelta.height += delta.height
        lookTouchActive = true
    }

    func endLook() {
        lookTouchActive = false
    }

    func addGyroDelta(_ delta: CGSize) {
        guard settings.gyroEnabled else { return }
        gyroDelta.width += delta.width * CGFloat(settings.gyroSensitivity)
        gyroDelta.height += delta.height * CGFloat(settings.gyroSensitivity)
    }

    func setAngles(yaw: Float, pitch: Float) {
        self.yaw = yaw
        self.pitch = pitch
    }

    /// Sensitivity is deliberately non-linear: small drags are precise for tracking, and
    /// fast flicks accelerate so a 180 is possible without lifting a thumb.
    private func sensitivityCurve(_ delta: CGFloat, aiming: Bool, scoped: Bool) -> Float {
        let base = settings.effectiveSensitivity(aiming: aiming, scoped: scoped)
        let magnitude = abs(Float(delta))
        // Above ~14pt of movement in one frame, apply a mild acceleration.
        let acceleration = magnitude > 14 ? 1 + min((magnitude - 14) / 90, 0.9) : 1
        let radiansPerPoint: Float = 0.0042
        return Float(delta) * base * radiansPerPoint * acceleration
    }

    // MARK: - Buttons

    func pressJump() { jumpLatched = true }
    func pressReload() { reloadLatched = true }
    func pressMelee() { meleeLatched = true }
    func pressLethal() { lethalLatched = true }
    func pressTactical() { tacticalLatched = true }
    func pressSwap() { swapLatched = true }
    func pressScopeToggle() { scopeLatched = true }
    func selectSlot(_ slot: LoadoutSlot) { requestedSlot = slot }

    func setCrouch(_ value: Bool) { isCrouching = value }
    func setFiring(_ value: Bool) { isFiring = value }
    func setAiming(_ value: Bool) { isAiming = value }
    func setSprinting(_ value: Bool) { isSprinting = value }
    func setUsing(_ value: Bool) { isUsing = value }

    // MARK: - Command assembly

    /// Builds the command for this tick, applying look input, aim assist and auto-fire.
    /// `target` is the best aim-assist candidate found by the caller this frame.
    func buildCommand(deltaTime: Float, player: PlayerState,
                      assistTarget: AimAssist.Target?) -> InputCommand {
        let scoped = player.scopeLevel > 0 && player.adsProgress > 0.9
        let aiming = player.isAiming

        // Apply accumulated look.
        var dx = pendingLookDelta.width + gyroDelta.width
        var dy = pendingLookDelta.height + gyroDelta.height
        pendingLookDelta = .zero
        gyroDelta = .zero

        // Aim assist slows the camera near a target and nudges it toward them.
        if let assistTarget, settings.aimAssist != .off {
            let slowdown = aimAssist.slowdownFactor(for: assistTarget, level: settings.aimAssist,
                                                    aiming: aiming)
            dx *= CGFloat(slowdown)
            dy *= CGFloat(slowdown)
        }

        yaw = MathUtil.wrapAngle(yaw - sensitivityCurve(dx, aiming: aiming, scoped: scoped))
        let pitchDelta = sensitivityCurve(dy, aiming: aiming, scoped: scoped)
        pitch = MathUtil.clamp(pitch + (settings.invertY ? pitchDelta : -pitchDelta),
                               -ViewAngles.maxPitch, ViewAngles.maxPitch)

        if let assistTarget, settings.aimAssist != .off {
            let (yawNudge, pitchNudge) = aimAssist.magnetism(
                for: assistTarget, level: settings.aimAssist, aiming: aiming,
                currentYaw: yaw, currentPitch: pitch, deltaTime: deltaTime,
                isMoving: moveVector != .zero || lookTouchActive)
            yaw = MathUtil.wrapAngle(yaw + yawNudge)
            pitch = MathUtil.clamp(pitch + pitchNudge, -ViewAngles.maxPitch, ViewAngles.maxPitch)
        }

        // Auto fire: the standard mobile assist. Only fires when the crosshair is actually
        // on a target and the weapon is ready — never a blind trigger hold.
        var firing = isFiring
        switch settings.triggerMode {
        case .manual:
            break
        case .autoFire:
            if assistTarget?.isUnderCrosshair == true { firing = true }
        case .adsAutoFire:
            if aiming && assistTarget?.isUnderCrosshair == true { firing = true }
        }

        var buttons: InputButtons = []
        if firing { buttons.insert(.fire) }
        if isAiming { buttons.insert(.aim) }
        if isCrouching { buttons.insert(.crouch) }
        if isUsing { buttons.insert(.use) }
        if jumpLatched { buttons.insert(.jump) }
        if reloadLatched { buttons.insert(.reload) }
        if meleeLatched { buttons.insert(.melee) }
        if lethalLatched { buttons.insert(.lethal) }
        if tacticalLatched { buttons.insert(.tactical) }
        if swapLatched { buttons.insert(.swapWeapon) }
        if scopeLatched { buttons.insert(.scopeToggle) }

        // Auto sprint: holding the stick forward for a moment starts a sprint, which is
        // what mobile players expect instead of a dedicated button.
        let forward = Float(-moveVector.dy)
        if (settings.autoSprint && forward > 0.85 && !aiming) || isSprinting {
            buttons.insert(.sprint)
        }

        // Auto reload on empty.
        if settings.autoReload, let slot = player.slots[player.activeSlot],
           slot.ammoInMagazine == 0, slot.reserveAmmo > 0 {
            buttons.insert(.reload)
        }

        let slot = requestedSlot
        clearLatches()

        sequence = sequence &+ 1
        return InputCommand(tick: 0, deltaTime: deltaTime,
                            moveForward: MathUtil.clamp(Float(-moveVector.dy), -1, 1),
                            moveRight: MathUtil.clamp(Float(moveVector.dx), -1, 1),
                            yaw: yaw, pitch: pitch, buttons: buttons,
                            requestedSlot: slot, sequence: sequence)
    }

    private func clearLatches() {
        jumpLatched = false
        reloadLatched = false
        meleeLatched = false
        lethalLatched = false
        tacticalLatched = false
        swapLatched = false
        scopeLatched = false
        requestedSlot = nil
    }

    func reset() {
        moveVector = .zero
        joystickActive = false
        isFiring = false
        isAiming = false
        isCrouching = false
        isSprinting = false
        isUsing = false
        pendingLookDelta = .zero
        gyroDelta = .zero
        clearLatches()
    }
}
