import Foundation

/// Minimal, dependency-free 3D vector. Right-handed, Y-up, -Z forward (SceneKit convention).
public struct Vec3: Codable, Equatable, Hashable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float

    @inlinable public init(_ x: Float = 0, _ y: Float = 0, _ z: Float = 0) {
        self.x = x; self.y = y; self.z = z
    }

    public static let zero = Vec3(0, 0, 0)
    public static let one = Vec3(1, 1, 1)
    public static let up = Vec3(0, 1, 0)
    public static let down = Vec3(0, -1, 0)
    public static let right = Vec3(1, 0, 0)
    public static let forward = Vec3(0, 0, -1)

    @inlinable public var lengthSquared: Float { x * x + y * y + z * z }
    @inlinable public var length: Float { lengthSquared.squareRoot() }

    @inlinable public var normalized: Vec3 {
        let l = length
        return l > 1e-6 ? self / l : .zero
    }

    /// Horizontal (XZ) component only — used constantly by movement and AI.
    @inlinable public var flattened: Vec3 { Vec3(x, 0, z) }
    @inlinable public var horizontalLength: Float { (x * x + z * z).squareRoot() }

    @inlinable public func dot(_ o: Vec3) -> Float { x * o.x + y * o.y + z * o.z }

    @inlinable public func cross(_ o: Vec3) -> Vec3 {
        Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    }

    @inlinable public func distance(to o: Vec3) -> Float { (self - o).length }
    @inlinable public func distanceSquared(to o: Vec3) -> Float { (self - o).lengthSquared }

    @inlinable public func lerp(_ o: Vec3, _ t: Float) -> Vec3 {
        Vec3(x + (o.x - x) * t, y + (o.y - y) * t, z + (o.z - z) * t)
    }

    /// Reflects the vector about a (unit) normal — bullet ricochets, grenade bounces.
    @inlinable public func reflected(normal n: Vec3) -> Vec3 {
        self - n * (2 * dot(n))
    }

    /// Removes the component of the vector pointing into a surface (wall sliding).
    @inlinable public func clipped(normal n: Vec3, bounce: Float = 1.0) -> Vec3 {
        let backoff = dot(n) * bounce
        return backoff < 0 ? self - n * backoff : self
    }

    @inlinable public func clampedLength(_ maxLength: Float) -> Vec3 {
        let l = length
        return l > maxLength && l > 1e-6 ? self * (maxLength / l) : self
    }

    public var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }

    @inlinable public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    @inlinable public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    @inlinable public static prefix func - (a: Vec3) -> Vec3 { Vec3(-a.x, -a.y, -a.z) }
    @inlinable public static func * (a: Vec3, s: Float) -> Vec3 { Vec3(a.x * s, a.y * s, a.z * s) }
    @inlinable public static func * (s: Float, a: Vec3) -> Vec3 { a * s }
    @inlinable public static func / (a: Vec3, s: Float) -> Vec3 { Vec3(a.x / s, a.y / s, a.z / s) }
    @inlinable public static func += (a: inout Vec3, b: Vec3) { a = a + b }
    @inlinable public static func -= (a: inout Vec3, b: Vec3) { a = a - b }
    @inlinable public static func *= (a: inout Vec3, s: Float) { a = a * s }

    /// Component-wise multiply (scaling boxes, per-axis damping).
    @inlinable public func scaled(by o: Vec3) -> Vec3 { Vec3(x * o.x, y * o.y, z * o.z) }
}

extension Vec3: CustomStringConvertible {
    public var description: String {
        String(format: "(%.2f, %.2f, %.2f)", x, y, z)
    }
}
