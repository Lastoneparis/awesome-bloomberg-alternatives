import Foundation

public enum MathUtil {
    public static let deg2rad: Float = .pi / 180
    public static let rad2deg: Float = 180 / .pi

    @inlinable public static func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
        min(max(v, lo), hi)
    }

    @inlinable public static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * clamp(t, 0, 1)
    }

    @inlinable public static func unlerp(_ a: Float, _ b: Float, _ v: Float) -> Float {
        abs(b - a) < 1e-6 ? 0 : clamp((v - a) / (b - a), 0, 1)
    }

    /// Frame-rate independent exponential smoothing.
    /// `halfLife` is the time it takes to close half the remaining distance.
    @inlinable public static func damp(_ a: Float, _ b: Float, halfLife: Float, dt: Float) -> Float {
        guard halfLife > 1e-5 else { return b }
        let t = 1 - pow(2, -dt / halfLife)
        return a + (b - a) * t
    }

    public static func dampVec(_ a: Vec3, _ b: Vec3, halfLife: Float, dt: Float) -> Vec3 {
        guard halfLife > 1e-5 else { return b }
        let t = 1 - pow(2, -dt / halfLife)
        return a.lerp(b, t)
    }

    /// Wraps an angle into (-pi, pi].
    public static func wrapAngle(_ a: Float) -> Float {
        var x = a.truncatingRemainder(dividingBy: 2 * .pi)
        if x > .pi { x -= 2 * .pi }
        if x <= -.pi { x += 2 * .pi }
        return x
    }

    /// Shortest signed difference between two angles.
    public static func angleDelta(_ from: Float, _ to: Float) -> Float {
        wrapAngle(to - from)
    }

    public static func lerpAngle(_ a: Float, _ b: Float, _ t: Float) -> Float {
        wrapAngle(a + angleDelta(a, b) * clamp(t, 0, 1))
    }

    public static func moveTowards(_ a: Float, _ b: Float, maxDelta: Float) -> Float {
        let d = b - a
        return abs(d) <= maxDelta ? b : a + (d < 0 ? -maxDelta : maxDelta)
    }

    public static func moveAngleTowards(_ a: Float, _ b: Float, maxDelta: Float) -> Float {
        let d = angleDelta(a, b)
        return abs(d) <= maxDelta ? b : wrapAngle(a + (d < 0 ? -maxDelta : maxDelta))
    }

    public static func smoothStep(_ t: Float) -> Float {
        let x = clamp(t, 0, 1)
        return x * x * (3 - 2 * x)
    }

    public static func easeOutCubic(_ t: Float) -> Float {
        let x = clamp(t, 0, 1)
        return 1 - pow(1 - x, 3)
    }

    /// Remaps a value from one range to another, clamped.
    public static func remap(_ v: Float, _ inMin: Float, _ inMax: Float, _ outMin: Float, _ outMax: Float) -> Float {
        lerp(outMin, outMax, unlerp(inMin, inMax, v))
    }
}
