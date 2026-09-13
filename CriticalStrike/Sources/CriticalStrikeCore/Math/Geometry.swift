import Foundation

/// Axis-aligned bounding box. The whole collision world is built from these
/// (brush-style level geometry), which keeps sweeps cheap enough for mobile.
public struct AABB: Codable, Equatable, Sendable {
    public var min: Vec3
    public var max: Vec3

    /// Orders the corners, so `min` really is the minimum on every axis.
    ///
    /// Everything downstream relies on it — the collision grid walks `cellIndex(min)` to
    /// `cellIndex(max)` as a range, and an inverted box crashed the whole test suite on the
    /// first map that was built. Cheap here, once, at authoring time; impossible to forget.
    public init(min: Vec3, max: Vec3) {
        self.min = Vec3(Swift.min(min.x, max.x), Swift.min(min.y, max.y), Swift.min(min.z, max.z))
        self.max = Vec3(Swift.max(min.x, max.x), Swift.max(min.y, max.y), Swift.max(min.z, max.z))
    }

    public init(center: Vec3, size: Vec3) {
        let h = size * 0.5
        self.min = center - h
        self.max = center + h
    }

    public var center: Vec3 { (min + max) * 0.5 }
    public var size: Vec3 { max - min }
    public var extents: Vec3 { size * 0.5 }

    public func contains(_ p: Vec3) -> Bool {
        p.x >= min.x && p.x <= max.x &&
        p.y >= min.y && p.y <= max.y &&
        p.z >= min.z && p.z <= max.z
    }

    public func intersects(_ o: AABB) -> Bool {
        min.x <= o.max.x && max.x >= o.min.x &&
        min.y <= o.max.y && max.y >= o.min.y &&
        min.z <= o.max.z && max.z >= o.min.z
    }

    public func expanded(by v: Vec3) -> AABB {
        AABB(min: min - v, max: max + v)
    }

    public func offset(by v: Vec3) -> AABB {
        AABB(min: min + v, max: max + v)
    }

    public func closestPoint(to p: Vec3) -> Vec3 {
        Vec3(MathUtil.clamp(p.x, min.x, max.x),
             MathUtil.clamp(p.y, min.y, max.y),
             MathUtil.clamp(p.z, min.z, max.z))
    }

    public func distanceSquared(to p: Vec3) -> Float {
        closestPoint(to: p).distanceSquared(to: p)
    }

    public func union(_ o: AABB) -> AABB {
        AABB(min: Vec3(Swift.min(min.x, o.min.x), Swift.min(min.y, o.min.y), Swift.min(min.z, o.min.z)),
             max: Vec3(Swift.max(max.x, o.max.x), Swift.max(max.y, o.max.y), Swift.max(max.z, o.max.z)))
    }

    /// Slab test. Returns entry distance along `ray` and the surface normal, or nil.
    public func raycast(_ ray: Ray, maxDistance: Float) -> (t: Float, normal: Vec3)? {
        var tmin: Float = 0
        var tmax = maxDistance
        var normal = Vec3.zero
        let o = ray.origin, d = ray.direction

        for axis in 0..<3 {
            let od = axis == 0 ? o.x : (axis == 1 ? o.y : o.z)
            let dd = axis == 0 ? d.x : (axis == 1 ? d.y : d.z)
            let lo = axis == 0 ? min.x : (axis == 1 ? min.y : min.z)
            let hi = axis == 0 ? max.x : (axis == 1 ? max.y : max.z)

            if abs(dd) < 1e-6 {
                if od < lo || od > hi { return nil }
                continue
            }
            let inv = 1 / dd
            var t1 = (lo - od) * inv
            var t2 = (hi - od) * inv
            var sign: Float = -1
            if t1 > t2 { swap(&t1, &t2); sign = 1 }
            if t1 > tmin {
                tmin = t1
                var n = Vec3.zero
                switch axis {
                case 0: n.x = sign
                case 1: n.y = sign
                default: n.z = sign
                }
                normal = n
            }
            tmax = Swift.min(tmax, t2)
            if tmin > tmax { return nil }
        }
        if normal == .zero { return nil } // started inside the box
        return (tmin, normal)
    }
}

public struct Ray: Sendable {
    public var origin: Vec3
    public var direction: Vec3  // expected normalized

    public init(origin: Vec3, direction: Vec3) {
        self.origin = origin
        self.direction = direction.normalized
    }

    public func point(at t: Float) -> Vec3 { origin + direction * t }
}

public struct Sphere: Sendable {
    public var center: Vec3
    public var radius: Float

    public init(center: Vec3, radius: Float) {
        self.center = center; self.radius = radius
    }

    public func raycast(_ ray: Ray, maxDistance: Float) -> Float? {
        let m = ray.origin - center
        let b = m.dot(ray.direction)
        let c = m.lengthSquared - radius * radius
        if c > 0 && b > 0 { return nil }
        let disc = b * b - c
        if disc < 0 { return nil }
        let t = -b - disc.squareRoot()
        let hit = Swift.max(t, 0)
        return hit <= maxDistance ? hit : nil
    }

    public func contains(_ p: Vec3) -> Bool {
        p.distanceSquared(to: center) <= radius * radius
    }
}

public enum Geometry {
    /// Shortest distance between a point and a segment — used by explosion and AI cover checks.
    public static func distancePointToSegment(_ p: Vec3, _ a: Vec3, _ b: Vec3) -> Float {
        let ab = b - a
        let denom = ab.lengthSquared
        guard denom > 1e-6 else { return p.distance(to: a) }
        let t = MathUtil.clamp((p - a).dot(ab) / denom, 0, 1)
        return p.distance(to: a + ab * t)
    }

    /// True if `target` lies inside a cone of `halfAngle` radians around `forward` from `origin`.
    public static func inCone(origin: Vec3, forward: Vec3, halfAngle: Float, target: Vec3) -> Bool {
        let to = (target - origin)
        let l = to.length
        guard l > 1e-5 else { return true }
        return (to / l).dot(forward) >= cos(halfAngle)
    }

    /// Builds an orthonormal basis around `forward` (for spread cones and decal orientation).
    public static func basis(forward f: Vec3) -> (right: Vec3, up: Vec3) {
        let ref: Vec3 = abs(f.y) > 0.99 ? Vec3(1, 0, 0) : Vec3(0, 1, 0)
        let right = f.cross(ref).normalized
        return (right, right.cross(f).normalized)
    }
}
