import Foundation

/// Pitch/yaw view angles in radians. Pitch is clamped so the player can never flip over.
public struct ViewAngles: Codable, Equatable, Sendable {
    public static let maxPitch: Float = 89.0 * .pi / 180.0

    public var pitch: Float   // + looks up
    public var yaw: Float     // + turns left (counter-clockwise around +Y)
    public var roll: Float    // cosmetic only (lean / recoil kick)

    public init(pitch: Float = 0, yaw: Float = 0, roll: Float = 0) {
        self.pitch = pitch; self.yaw = yaw; self.roll = roll
    }

    public mutating func clampPitch() {
        pitch = min(max(pitch, -ViewAngles.maxPitch), ViewAngles.maxPitch)
    }

    public mutating func normalizeYaw() {
        yaw = MathUtil.wrapAngle(yaw)
    }

    /// Unit vector the player is looking along.
    public var forward: Vec3 {
        let cp = cos(pitch), sp = sin(pitch)
        let cy = cos(yaw), sy = sin(yaw)
        return Vec3(-sy * cp, sp, -cy * cp)
    }

    /// Unit vector pointing to the player's right (used for strafing).
    public var right: Vec3 {
        Vec3(cos(yaw), 0, -sin(yaw))
    }

    /// Forward projected onto the ground plane — movement uses this, not `forward`.
    public var groundForward: Vec3 {
        Vec3(-sin(yaw), 0, -cos(yaw))
    }

    public var up: Vec3 { right.cross(forward) }

    public func lerp(_ o: ViewAngles, _ t: Float) -> ViewAngles {
        ViewAngles(pitch: MathUtil.lerp(pitch, o.pitch, t),
                   yaw: MathUtil.lerpAngle(yaw, o.yaw, t),
                   roll: MathUtil.lerp(roll, o.roll, t))
    }

    public static func looking(from: Vec3, at target: Vec3) -> ViewAngles {
        let d = (target - from)
        let horiz = d.horizontalLength
        var a = ViewAngles(pitch: atan2(d.y, max(horiz, 1e-5)),
                           yaw: atan2(-d.x, -d.z))
        a.clampPitch(); a.normalizeYaw()
        return a
    }
}
