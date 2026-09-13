import Foundation

/// Tiny authoring DSL so maps read like level design instead of coordinate soup.
/// Everything is axis-aligned; `x` runs west→east, `z` runs north→south, `y` is up.
public struct MapAuthor {
    public var brushes: [MapBrush] = []
    public var props: [MapProp] = []
    public var lights: [MapLight] = []
    public var spawns: [SpawnPoint] = []
    public var pickups: [PickupSpawn] = []
    public var callouts: [Callout] = []

    public init() {}

    // MARK: Geometry helpers

    /// Ground plane slab.
    public mutating func floor(x: ClosedRange<Float>, z: ClosedRange<Float>, y: Float = 0,
                              thickness: Float = 1, surface: SurfaceKind = .concrete) {
        brushes.append(MapBrush(box: AABB(min: Vec3(x.lowerBound, y - thickness, z.lowerBound),
                                          max: Vec3(x.upperBound, y, z.upperBound)),
                                surface: surface))
    }

    /// Solid box given by its footprint and height.
    public mutating func block(x: ClosedRange<Float>, z: ClosedRange<Float>,
                               y: Float = 0, height: Float,
                               surface: SurfaceKind = .concrete, breakable: Bool = false,
                               blocksVision: Bool = true, blocksBullets: Bool = true) {
        brushes.append(MapBrush(box: AABB(min: Vec3(x.lowerBound, y, z.lowerBound),
                                          max: Vec3(x.upperBound, y + height, z.upperBound)),
                                surface: surface, isBreakable: breakable,
                                blocksBullets: blocksBullets, blocksVision: blocksVision))
    }

    /// Wall running along X or Z between two points.
    public mutating func wall(from a: Vec3, to b: Vec3, height: Float = 4,
                              thickness: Float = 0.4, surface: SurfaceKind = .concrete,
                              breakable: Bool = false) {
        let minX = Swift.min(a.x, b.x), maxX = Swift.max(a.x, b.x)
        let minZ = Swift.min(a.z, b.z), maxZ = Swift.max(a.z, b.z)
        let halfT = thickness * 0.5
        let box = AABB(min: Vec3(minX - (maxX - minX < 0.01 ? halfT : 0), a.y,
                                 minZ - (maxZ - minZ < 0.01 ? halfT : 0)),
                       max: Vec3(maxX + (maxX - minX < 0.01 ? halfT : 0), a.y + height,
                                 maxZ + (maxZ - minZ < 0.01 ? halfT : 0)))
        brushes.append(MapBrush(box: box, surface: surface, isBreakable: breakable))
    }

    /// Wall with a doorway gap punched in the middle of the given span.
    public mutating func wallWithDoor(from a: Vec3, to b: Vec3, height: Float = 4,
                                      thickness: Float = 0.4, doorWidth: Float = 2.4,
                                      doorHeight: Float = 2.6, surface: SurfaceKind = .concrete) {
        let alongX = abs(b.x - a.x) > abs(b.z - a.z)
        let start = alongX ? Swift.min(a.x, b.x) : Swift.min(a.z, b.z)
        let end = alongX ? Swift.max(a.x, b.x) : Swift.max(a.z, b.z)
        let mid = (start + end) * 0.5
        let gapLo = mid - doorWidth * 0.5, gapHi = mid + doorWidth * 0.5

        func segment(_ lo: Float, _ hi: Float, yMin: Float, h: Float) {
            guard hi - lo > 0.01, h > 0.01 else { return }
            if alongX {
                wall(from: Vec3(lo, yMin, a.z), to: Vec3(hi, yMin, a.z), height: h,
                     thickness: thickness, surface: surface)
            } else {
                wall(from: Vec3(a.x, yMin, lo), to: Vec3(a.x, yMin, hi), height: h,
                     thickness: thickness, surface: surface)
            }
        }
        segment(start, gapLo, yMin: a.y, h: height)
        segment(gapHi, end, yMin: a.y, h: height)
        // Lintel above the doorway.
        if height > doorHeight {
            let saveA = a
            if alongX {
                wall(from: Vec3(gapLo, saveA.y + doorHeight, saveA.z),
                     to: Vec3(gapHi, saveA.y + doorHeight, saveA.z),
                     height: height - doorHeight, thickness: thickness, surface: surface)
            } else {
                wall(from: Vec3(saveA.x, saveA.y + doorHeight, gapLo),
                     to: Vec3(saveA.x, saveA.y + doorHeight, gapHi),
                     height: height - doorHeight, thickness: thickness, surface: surface)
            }
        }
    }

    /// Window band: shootable-through glass with a sill and a header.
    public mutating func window(from a: Vec3, to b: Vec3, sill: Float = 1.1, openingHeight: Float = 1.3,
                                height: Float = 4, thickness: Float = 0.4,
                                surface: SurfaceKind = .concrete, glass: Bool = true) {
        wall(from: a, to: b, height: sill, thickness: thickness, surface: surface)
        let top = sill + openingHeight
        if height > top {
            var upper = a; upper.y = a.y + top
            var upperB = b; upperB.y = b.y + top
            wall(from: upper, to: upperB, height: height - top, thickness: thickness, surface: surface)
        }
        if glass {
            var g = a; g.y = a.y + sill
            var gb = b; gb.y = b.y + sill
            // Glass blocks vision until broken but never stops a bullet.
            let minX = Swift.min(g.x, gb.x), maxX = Swift.max(g.x, gb.x)
            let minZ = Swift.min(g.z, gb.z), maxZ = Swift.max(g.z, gb.z)
            let halfT = thickness * 0.25
            brushes.append(MapBrush(
                box: AABB(min: Vec3(minX - (maxX - minX < 0.01 ? halfT : 0), g.y,
                                    minZ - (maxZ - minZ < 0.01 ? halfT : 0)),
                          max: Vec3(maxX + (maxX - minX < 0.01 ? halfT : 0), g.y + openingHeight,
                                    maxZ + (maxZ - minZ < 0.01 ? halfT : 0))),
                surface: .glass, isBreakable: true, blocksBullets: false, blocksVision: true))
        }
    }

    /// Four walls + optional ceiling, with doorways on the requested sides.
    public mutating func room(x: ClosedRange<Float>, z: ClosedRange<Float>, y: Float = 0,
                              height: Float = 4, thickness: Float = 0.4,
                              doors: Set<Side> = [], windows: Set<Side> = [],
                              ceiling: Bool = false, surface: SurfaceKind = .concrete) {
        let corners: [(Side, Vec3, Vec3)] = [
            (.north, Vec3(x.lowerBound, y, z.lowerBound), Vec3(x.upperBound, y, z.lowerBound)),
            (.south, Vec3(x.lowerBound, y, z.upperBound), Vec3(x.upperBound, y, z.upperBound)),
            (.west,  Vec3(x.lowerBound, y, z.lowerBound), Vec3(x.lowerBound, y, z.upperBound)),
            (.east,  Vec3(x.upperBound, y, z.lowerBound), Vec3(x.upperBound, y, z.upperBound))
        ]
        for (side, a, b) in corners {
            if doors.contains(side) {
                wallWithDoor(from: a, to: b, height: height, thickness: thickness, surface: surface)
            } else if windows.contains(side) {
                window(from: a, to: b, height: height, thickness: thickness, surface: surface)
            } else {
                wall(from: a, to: b, height: height, thickness: thickness, surface: surface)
            }
        }
        if ceiling {
            brushes.append(MapBrush(box: AABB(min: Vec3(x.lowerBound, y + height, z.lowerBound),
                                              max: Vec3(x.upperBound, y + height + 0.3, z.upperBound)),
                                    surface: surface))
        }
    }

    /// Staircase approximated by steps — cheap and reliably walkable.
    public mutating func stairs(x: ClosedRange<Float>, z: ClosedRange<Float>, from y0: Float,
                                to y1: Float, steps: Int = 8, alongZ: Bool = true,
                                surface: SurfaceKind = .concrete) {
        let n = Swift.max(steps, 1)
        // Each step is a solid from below the staircase up to its tread. The base has to be
        // the lower of the two ends, not y0: a descending staircase (from: 3.4, to: 0) put
        // the base above the tread from the second step on, which is an inverted box.
        let base = Swift.min(y0, y1) - 0.5
        for i in 0..<n {
            let t0 = Float(i) / Float(n), t1 = Float(i + 1) / Float(n)
            let tread = Swift.max(y0 + (y1 - y0) * t1, base + 0.01)
            if alongZ {
                let zLo = z.lowerBound + (z.upperBound - z.lowerBound) * t0
                let zHi = z.lowerBound + (z.upperBound - z.lowerBound) * t1
                brushes.append(MapBrush(box: AABB(min: Vec3(x.lowerBound, base, zLo),
                                                  max: Vec3(x.upperBound, tread, zHi)),
                                        surface: surface))
            } else {
                let xLo = x.lowerBound + (x.upperBound - x.lowerBound) * t0
                let xHi = x.lowerBound + (x.upperBound - x.lowerBound) * t1
                brushes.append(MapBrush(box: AABB(min: Vec3(xLo, base, z.lowerBound),
                                                  max: Vec3(xHi, tread, z.upperBound)),
                                        surface: surface))
            }
        }
    }

    /// Waist-high cover box — the bread and butter of a shooter layout.
    public mutating func crate(at p: Vec3, size: Float = 1.2, height: Float? = nil,
                               surface: SurfaceKind = .wood) {
        let h = height ?? size
        brushes.append(MapBrush(box: AABB(min: Vec3(p.x - size / 2, p.y, p.z - size / 2),
                                          max: Vec3(p.x + size / 2, p.y + h, p.z + size / 2)),
                                surface: surface, thickness: Swift.min(size, h)))
    }

    public mutating func crateStack(at p: Vec3, columns: Int = 2, rows: Int = 2, size: Float = 1.2,
                                    surface: SurfaceKind = .wood) {
        for c in 0..<columns {
            for r in 0..<rows {
                crate(at: Vec3(p.x + Float(c) * size, p.y + Float(r) * size, p.z),
                      size: size, surface: surface)
            }
        }
    }

    /// Invisible wall that keeps players inside the playable area.
    public mutating func skyboxClip(bounds: AABB, height: Float = 24) {
        let t: Float = 2
        let b = bounds
        let sides = [
            AABB(min: Vec3(b.min.x - t, b.min.y, b.min.z - t), max: Vec3(b.max.x + t, b.min.y + height, b.min.z)),
            AABB(min: Vec3(b.min.x - t, b.min.y, b.max.z), max: Vec3(b.max.x + t, b.min.y + height, b.max.z + t)),
            AABB(min: Vec3(b.min.x - t, b.min.y, b.min.z - t), max: Vec3(b.min.x, b.min.y + height, b.max.z + t)),
            AABB(min: Vec3(b.max.x, b.min.y, b.min.z - t), max: Vec3(b.max.x + t, b.min.y + height, b.max.z + t))
        ]
        for s in sides {
            brushes.append(MapBrush(box: s, surface: .concrete, isClip: true, blocksVision: false))
        }
    }

    // MARK: Content helpers

    public mutating func spawn(_ p: Vec3, yaw: Float = 0, team: Team = .none, priority: Int = 0) {
        spawns.append(SpawnPoint(position: p, yaw: yaw * MathUtil.deg2rad, team: team, priority: priority))
    }

    public mutating func spawnCluster(center: Vec3, yaw: Float, team: Team, count: Int = 5,
                                      spread: Float = 2.0) {
        for i in 0..<count {
            let offset = Float(i) - Float(count - 1) * 0.5
            spawn(center + Vec3(offset * spread, 0, 0), yaw: yaw, team: team, priority: 10 - i)
        }
    }

    public mutating func light(_ p: Vec3, intensity: Float = 700, range: Float = 16,
                               colorHex: UInt32 = 0xFFE9C8, shadows: Bool = false,
                               kind: MapLightKind = .omni) {
        lights.append(MapLight(kind: kind, position: p, colorHex: colorHex,
                               intensity: intensity, range: range, castsShadows: shadows))
    }

    public mutating func prop(_ name: String, at p: Vec3, yaw: Float = 0, scale: Float = 1,
                              collides: Bool = false, surface: SurfaceKind = .metal) {
        props.append(MapProp(name: name, position: p, yaw: yaw * MathUtil.deg2rad,
                             scale: scale, collides: collides, surface: surface))
    }

    public mutating func pickup(_ kind: PickupKind, at p: Vec3, weapon: WeaponID? = nil) {
        pickups.append(PickupSpawn(kind: kind, position: p, weapon: weapon))
    }

    public mutating func callout(_ name: String, x: ClosedRange<Float>, z: ClosedRange<Float>,
                                 y: ClosedRange<Float> = -2...12) {
        callouts.append(Callout(name: name,
                                box: AABB(min: Vec3(x.lowerBound, y.lowerBound, z.lowerBound),
                                          max: Vec3(x.upperBound, y.upperBound, z.upperBound))))
    }

    public enum Side: Hashable, Sendable { case north, south, east, west }
}
