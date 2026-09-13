import Foundation

public struct TraceResult: Sendable {
    public var hit: Bool
    public var fraction: Float       // 0...1 along the trace
    public var point: Vec3
    public var normal: Vec3
    public var surface: SurfaceKind
    public var brushIndex: Int
    public var startedSolid: Bool

    public static func miss(end: Vec3) -> TraceResult {
        TraceResult(hit: false, fraction: 1, point: end, normal: .zero,
                    surface: .concrete, brushIndex: -1, startedSolid: false)
    }
}

/// Uniform-grid broadphase over the map's brushes. Static geometry only: players and
/// projectiles are traced against separately, which keeps this structure immutable and
/// safe to share across threads (the bot threads raycast it constantly).
public final class CollisionWorld: @unchecked Sendable {
    public let brushes: [MapBrush]
    public let bounds: AABB

    private let cellSize: Float
    private let gridMin: Vec3
    private let gridDim: (x: Int, y: Int, z: Int)
    private var cells: [[Int32]]

    public init(map: MapData, cellSize: Float = 6) {
        self.brushes = map.brushes
        self.bounds = map.bounds.expanded(by: Vec3(2, 2, 2))
        self.cellSize = cellSize
        self.gridMin = bounds.min
        let size = bounds.size
        let dx = max(1, Int(ceil(size.x / cellSize)))
        let dy = max(1, Int(ceil(size.y / cellSize)))
        let dz = max(1, Int(ceil(size.z / cellSize)))
        self.gridDim = (dx, dy, dz)
        self.cells = Array(repeating: [], count: dx * dy * dz)
        buildGrid()
    }

    private func cellIndex(_ ix: Int, _ iy: Int, _ iz: Int) -> Int {
        (iz * gridDim.y + iy) * gridDim.x + ix
    }

    private func clampedCell(_ p: Vec3) -> (Int, Int, Int) {
        let local = p - gridMin
        return (MathUtil.clamp(Int(local.x / cellSize), 0, gridDim.x - 1),
                MathUtil.clamp(Int(local.y / cellSize), 0, gridDim.y - 1),
                MathUtil.clamp(Int(local.z / cellSize), 0, gridDim.z - 1))
    }

    private func buildGrid() {
        for (i, brush) in brushes.enumerated() {
            let (x0, y0, z0) = clampedCell(brush.box.min)
            let (x1, y1, z1) = clampedCell(brush.box.max)
            for z in z0...z1 {
                for y in y0...y1 {
                    for x in x0...x1 {
                        cells[cellIndex(x, y, z)].append(Int32(i))
                    }
                }
            }
        }
    }

    /// All brush indices whose cell overlaps `box`.
    public func candidates(in box: AABB) -> [Int] {
        let (x0, y0, z0) = clampedCell(box.min)
        let (x1, y1, z1) = clampedCell(box.max)
        var seen = Set<Int32>()
        var out: [Int] = []
        out.reserveCapacity(16)
        for z in z0...z1 {
            for y in y0...y1 {
                for x in x0...x1 {
                    for idx in cells[cellIndex(x, y, z)] where seen.insert(idx).inserted {
                        out.append(Int(idx))
                    }
                }
            }
        }
        return out
    }

    // MARK: - Ray traces

    /// Line trace against static geometry. `ignoreNonSolid` skips glass and other
    /// bullet-permeable brushes (used by the ballistics pass, which handles them itself).
    public func trace(from start: Vec3, to end: Vec3,
                      mask: TraceMask = .solid) -> TraceResult {
        let delta = end - start
        let distance = delta.length
        guard distance > 1e-5 else { return .miss(end: end) }
        let ray = Ray(origin: start, direction: delta / distance)

        var best = TraceResult.miss(end: end)
        best.fraction = 1

        let sweepBox = AABB(min: Vec3(min(start.x, end.x), min(start.y, end.y), min(start.z, end.z)),
                            max: Vec3(max(start.x, end.x), max(start.y, end.y), max(start.z, end.z)))
            .expanded(by: Vec3(0.05, 0.05, 0.05))

        for i in candidates(in: sweepBox) {
            let brush = brushes[i]
            guard mask.accepts(brush) else { continue }
            guard let (t, normal) = brush.box.raycast(ray, maxDistance: distance) else { continue }
            let f = t / distance
            if f < best.fraction {
                best = TraceResult(hit: true, fraction: f, point: ray.point(at: t),
                                   normal: normal, surface: brush.surface,
                                   brushIndex: i, startedSolid: false)
            }
        }
        return best
    }

    /// True when nothing blocks vision between two points (used by AI and by smoke checks).
    public func hasLineOfSight(from: Vec3, to: Vec3) -> Bool {
        !trace(from: from, to: to, mask: .vision).hit
    }

    // MARK: - Box sweeps (player movement)

    /// Swept AABB against the world, returning the first blocking contact.
    /// Uses conservative advancement: cheap, stable, and good enough at 64Hz.
    public func sweep(box: AABB, delta: Vec3, mask: TraceMask = .solid) -> TraceResult {
        let distance = delta.length
        guard distance > 1e-6 else { return .miss(end: box.center) }
        let dir = delta / distance

        let expandedArea = box.union(box.offset(by: delta)).expanded(by: Vec3(0.1, 0.1, 0.1))
        var bestFraction: Float = 1
        var bestNormal = Vec3.zero
        var bestSurface = SurfaceKind.concrete
        var bestIndex = -1
        var startedSolid = false

        let half = box.extents
        let center = box.center

        for i in candidates(in: expandedArea) {
            let brush = brushes[i]
            guard mask.accepts(brush) else { continue }
            // Minkowski: inflate the brush by our half-extents and ray-trace the center point.
            let inflated = brush.box.expanded(by: half)
            if inflated.contains(center) {
                startedSolid = true
                continue
            }
            guard let (t, normal) = inflated.raycast(Ray(origin: center, direction: dir),
                                                     maxDistance: distance) else { continue }
            let f = max(0, t / distance)
            if f < bestFraction {
                bestFraction = f
                bestNormal = normal
                bestSurface = brush.surface
                bestIndex = i
            }
        }

        if bestIndex < 0 {
            return TraceResult(hit: false, fraction: 1, point: center + delta, normal: .zero,
                               surface: .concrete, brushIndex: -1, startedSolid: startedSolid)
        }
        // Back off a hair so we never end the frame embedded in a surface.
        let safeFraction = max(0, bestFraction - 0.001)
        return TraceResult(hit: true, fraction: safeFraction, point: center + dir * (distance * safeFraction),
                           normal: bestNormal, surface: bestSurface, brushIndex: bestIndex,
                           startedSolid: startedSolid)
    }

    public func overlaps(box: AABB, mask: TraceMask = .solid) -> Bool {
        for i in candidates(in: box) where mask.accepts(brushes[i]) {
            if brushes[i].box.intersects(box) { return true }
        }
        return false
    }

    /// Drops a point onto the first surface below it. Used by spawn validation and nav baking.
    public func groundHeight(below p: Vec3, maxDrop: Float = 30) -> Float? {
        let result = trace(from: p, to: p + Vec3(0, -maxDrop, 0), mask: .solid)
        return result.hit ? result.point.y : nil
    }

    /// Surface material directly under a point (footstep audio).
    public func surface(below p: Vec3) -> SurfaceKind {
        let r = trace(from: p + Vec3(0, 0.2, 0), to: p + Vec3(0, -1.2, 0), mask: .solid)
        return r.hit ? r.surface : .concrete
    }
}

public struct TraceMask: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let solid = TraceMask(rawValue: 1 << 0)      // blocks movement
    public static let bullets = TraceMask(rawValue: 1 << 1)    // blocks bullets
    public static let vision = TraceMask(rawValue: 1 << 2)     // blocks line of sight
    public static let includeClip = TraceMask(rawValue: 1 << 3)

    func accepts(_ brush: MapBrush) -> Bool {
        if brush.isClip {
            // Player-clip brushes stop movement but not bullets or sight.
            return contains(.solid)
        }
        if contains(.bullets) && !brush.blocksBullets { return false }
        if contains(.vision) && !brush.blocksVision { return false }
        return true
    }
}
