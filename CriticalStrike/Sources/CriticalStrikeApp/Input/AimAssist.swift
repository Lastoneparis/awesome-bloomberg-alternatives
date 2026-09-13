import Foundation
import CoreGraphics
import CriticalStrikeCore

/// Aim assist for touch controls.
///
/// Two independent mechanisms, both standard in mobile shooters and both deliberately
/// bounded so they help without playing the game for the player:
///  * **Slowdown** — the camera turns more slowly while the crosshair is near a target,
///    which makes tracking possible with a thumb.
///  * **Magnetism** — a small rotational nudge toward the target, applied only while the
///    player is actively providing input. It never moves the camera on its own.
///
/// Neither ever changes where a bullet goes: the simulation reads the aim angles the
/// player ends up with, so the assist is purely an input-space effect and behaves the same
/// on the server.
final class AimAssist {
    struct Target {
        var player: PlayerID
        /// Angle between the crosshair and the target centre, in radians.
        var angularError: Float
        var distance: Float
        /// Approximate screen-space distance in points.
        var screenDistance: Float
        var isUnderCrosshair: Bool
        var worldAngles: ViewAngles
    }

    /// Beyond this, assist does nothing at all — snipers get no free tracking.
    static let maximumRange: Float = 60

    /// Picks the best assist candidate from everyone currently visible.
    func findTarget(from player: PlayerState, candidates: [HitVolume], world: CollisionWorld,
                    level: AimAssistLevel, screenHeightPoints: Float, verticalFOV: Float) -> Target? {
        guard level != .off else { return nil }
        let eye = player.eyePosition
        let aim = RecoilSystem.aimDirection(for: player)
        let pointsPerRadian = screenHeightPoints / max(verticalFOV, 0.1)

        var best: Target?
        for candidate in candidates {
            guard candidate.isAlive, candidate.player != player.id else { continue }
            guard candidate.team != player.team || player.team == .none else { continue }

            let centre = candidate.position + Vec3(0, 1.15 * candidate.crouchScale, 0)
            let toTarget = centre - eye
            let distance = toTarget.length
            guard distance < AimAssist.maximumRange, distance > 0.5 else { continue }

            let direction = toTarget / distance
            let dot = MathUtil.clamp(direction.dot(aim), -1, 1)
            let angularError = acos(dot)
            let screenDistance = angularError * pointsPerRadian
            guard screenDistance < level.radius * 1.6 else { continue }

            // Assist never sees through walls.
            guard world.hasLineOfSight(from: eye, to: centre) else { continue }

            let underCrosshair = screenDistance < level.radius * 0.35
            let target = Target(player: candidate.player, angularError: angularError,
                                distance: distance, screenDistance: screenDistance,
                                isUnderCrosshair: underCrosshair,
                                worldAngles: ViewAngles.looking(from: eye, at: centre))
            if best == nil || screenDistance < best!.screenDistance { best = target }
        }
        return best
    }

    /// Multiplier applied to raw look input. 1 means no assist.
    func slowdownFactor(for target: Target, level: AimAssistLevel, aiming: Bool) -> Float {
        let strength = level.stickiness * (aiming ? 1.0 : 0.7)
        // Full strength at the centre, tapering to nothing at the edge of the radius.
        let proximity = 1 - MathUtil.clamp(target.screenDistance / max(level.radius, 1), 0, 1)
        let falloff = 1 - MathUtil.clamp(target.distance / AimAssist.maximumRange, 0, 1) * 0.5
        return 1 - strength * proximity * falloff
    }

    /// Rotational nudge toward the target, in radians for this frame.
    func magnetism(for target: Target, level: AimAssistLevel, aiming: Bool,
                   currentYaw: Float, currentPitch: Float, deltaTime: Float,
                   isMoving: Bool) -> (yaw: Float, pitch: Float) {
        // Magnetism only applies while the player is providing input. Standing still with
        // a thumb off the screen gives no pull at all.
        guard isMoving else { return (0, 0) }
        let strength = level.magnetism * (aiming ? 1.2 : 0.8)
        let proximity = 1 - MathUtil.clamp(target.screenDistance / max(level.radius, 1), 0, 1)
        guard proximity > 0 else { return (0, 0) }

        let yawError = MathUtil.angleDelta(currentYaw, target.worldAngles.yaw)
        let pitchError = target.worldAngles.pitch - currentPitch
        // Cap the pull so it can never exceed a plausible thumb movement.
        let maxPull = 2.2 * deltaTime
        let pull = strength * proximity * deltaTime * 7
        return (MathUtil.clamp(yawError * pull, -maxPull, maxPull),
                MathUtil.clamp(pitchError * pull, -maxPull, maxPull))
    }

    /// Hip-fire "bullet magnetism" is deliberately NOT implemented: the spread cone is the
    /// only thing that decides accuracy, so two players with the same settings always have
    /// the same weapon behaviour.
    static let bulletMagnetismEnabled = false
}
