import Foundation
import CoreHaptics
import UIKit

/// Haptics carry real information in a shooter: a hit lands differently from a headshot,
/// and a near-miss differently again. Uses Core Haptics where available and falls back to
/// UIFeedbackGenerator on older devices.
final class HapticsService {
    var isEnabled = true {
        didSet { if !isEnabled { stopEngine() } else { prepareEngine() } }
    }

    private var engine: CHHapticEngine?
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private var supportsCoreHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    init() { prepareEngine() }

    private func prepareEngine() {
        guard isEnabled, supportsCoreHaptics, engine == nil else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            // A phone call or Siri can stop the engine; restart it rather than going silent.
            engine.resetHandler = { [weak self] in try? self?.engine?.start() }
            engine.stoppedHandler = { _ in }
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
        }
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
    }

    private func stopEngine() {
        engine?.stop()
        engine = nil
    }

    // MARK: - Game feedback

    func weaponFire(recoil: Float) {
        guard isEnabled else { return }
        let intensity = min(1, 0.25 + recoil * 22)
        transient(intensity: intensity, sharpness: 0.75)
    }

    func hitMarker(headshot: Bool) {
        guard isEnabled else { return }
        if headshot {
            transient(intensity: 0.9, sharpness: 1.0)
            transient(intensity: 0.6, sharpness: 0.8, delay: 0.06)
        } else {
            transient(intensity: 0.5, sharpness: 0.9)
        }
    }

    func tookDamage(amount: Float) {
        guard isEnabled else { return }
        continuous(intensity: min(1, amount / 60), sharpness: 0.3, duration: 0.12)
    }

    func explosion(distanceScale: Float) {
        guard isEnabled else { return }
        continuous(intensity: min(1, distanceScale), sharpness: 0.15, duration: 0.35)
    }

    func kill() {
        guard isEnabled else { return }
        transient(intensity: 1.0, sharpness: 0.6)
        transient(intensity: 0.7, sharpness: 0.9, delay: 0.08)
    }

    func death() {
        guard isEnabled else { return }
        continuous(intensity: 1, sharpness: 0.1, duration: 0.5)
    }

    func selection() {
        guard isEnabled else { return }
        selectionGenerator.selectionChanged()
    }

    func success() {
        guard isEnabled else { return }
        notification.notificationOccurred(.success)
    }

    func warning() {
        guard isEnabled else { return }
        notification.notificationOccurred(.warning)
    }

    func error() {
        guard isEnabled else { return }
        notification.notificationOccurred(.error)
    }

    // MARK: - Primitives

    private func transient(intensity: Float, sharpness: Float, delay: TimeInterval = 0) {
        guard let engine else {
            impactMedium.impactOccurred(intensity: CGFloat(intensity))
            return
        }
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
        ], relativeTime: delay)
        play([event], on: engine)
    }

    private func continuous(intensity: Float, sharpness: Float, duration: TimeInterval) {
        guard let engine else {
            impactHeavy.impactOccurred(intensity: CGFloat(intensity))
            return
        }
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
        ], relativeTime: 0, duration: duration)
        play([event], on: engine)
    }

    private func play(_ events: [CHHapticEvent], on engine: CHHapticEngine) {
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            impactLight.impactOccurred()
        }
    }
}
