import Foundation

/// Deterministic, **tileable** procedural noise.
///
/// Lives in the core rather than the render layer for two reasons: it is pure Foundation
/// maths with no Core Graphics in sight, and it is the one part of the art pipeline that
/// genuinely needs tests — a noise function that is not actually seamless produces a grid
/// of visible seams across every wall in the game, and that is very hard to spot by eye
/// until it is on a device.
///
/// Every function takes a `period` in lattice cells and wraps its lattice coordinates
/// modulo that period, so sampling the unit square [0,1) with the same period always
/// produces an image that tiles perfectly.
public enum Noise {

    // MARK: - Hashing

    /// Integer hash → [0, 1). A cheap, well-mixed 2D hash; the constants are the usual
    /// large primes, chosen so neighbouring cells decorrelate.
    @inlinable
    public static func hash(_ x: Int, _ y: Int, _ seed: UInt32) -> Float {
        var h = UInt32(truncatingIfNeeded: x) &* 0x8DA6B343
        h = h &+ UInt32(truncatingIfNeeded: y) &* 0xD8163841
        h = h &+ seed &* 0xCB1AB31F
        h ^= h >> 15
        h = h &* 0x2C1B3C6D
        h ^= h >> 12
        h = h &* 0x297A2D39
        h ^= h >> 15
        return Float(h >> 8) * (1.0 / Float(1 << 24))
    }

    /// Two independent hashes for a cell, used for cellular feature points.
    @inlinable
    public static func hash2(_ x: Int, _ y: Int, _ seed: UInt32) -> (Float, Float) {
        (hash(x, y, seed), hash(x, y, seed &+ 0x9E3779B9))
    }

    @inlinable
    static func wrap(_ value: Int, _ period: Int) -> Int {
        guard period > 0 else { return value }
        let m = value % period
        return m < 0 ? m + period : m
    }

    /// Quintic smoothstep. Its first and second derivatives vanish at the ends, which is
    /// what keeps fBm free of the faint lattice grid that cubic interpolation leaves.
    @inlinable
    static func fade(_ t: Float) -> Float {
        t * t * t * (t * (t * 6 - 15) + 10)
    }

    // MARK: - Value noise

    /// Tileable value noise in [0, 1). `x` and `y` are in lattice units.
    public static func value(_ x: Float, _ y: Float, period: Int, seed: UInt32) -> Float {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let xf = x - Float(xi), yf = y - Float(yi)
        let u = fade(xf), v = fade(yf)

        let x0 = wrap(xi, period), x1 = wrap(xi + 1, period)
        let y0 = wrap(yi, period), y1 = wrap(yi + 1, period)

        let n00 = hash(x0, y0, seed)
        let n10 = hash(x1, y0, seed)
        let n01 = hash(x0, y1, seed)
        let n11 = hash(x1, y1, seed)

        let top = n00 + (n10 - n00) * u
        let bottom = n01 + (n11 - n01) * u
        return top + (bottom - top) * v
    }

    /// Tileable gradient (Perlin-style) noise in [0, 1). Gradient noise has no axis-aligned
    /// bias, so it reads as a more natural surface than value noise for large features.
    public static func gradient(_ x: Float, _ y: Float, period: Int, seed: UInt32) -> Float {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let xf = x - Float(xi), yf = y - Float(yi)
        let u = fade(xf), v = fade(yf)

        func dot(_ cx: Int, _ cy: Int, _ dx: Float, _ dy: Float) -> Float {
            let angle = hash(wrap(cx, period), wrap(cy, period), seed) * 2 * .pi
            return cos(angle) * dx + sin(angle) * dy
        }

        let n00 = dot(xi, yi, xf, yf)
        let n10 = dot(xi + 1, yi, xf - 1, yf)
        let n01 = dot(xi, yi + 1, xf, yf - 1)
        let n11 = dot(xi + 1, yi + 1, xf - 1, yf - 1)

        let top = n00 + (n10 - n00) * u
        let bottom = n01 + (n11 - n01) * u
        // Gradient noise lands in about [-0.7, 0.7]; remap to [0, 1].
        return MathUtil.clamp((top + (bottom - top) * v) * 0.7071 + 0.5, 0, 1)
    }

    // MARK: - Fractal

    public enum Basis: Sendable {
        case value, gradient
    }

    /// Fractional Brownian motion: octaves of noise at doubling frequency and halving
    /// amplitude. Returns [0, 1].
    public static func fbm(_ x: Float, _ y: Float, period: Int, octaves: Int = 4,
                           gain: Float = 0.5, lacunarity: Float = 2,
                           basis: Basis = .value, seed: UInt32 = 0) -> Float {
        var amplitude: Float = 1
        var total: Float = 0
        var normalization: Float = 0
        var frequency: Float = 1
        var currentPeriod = period

        for octave in 0..<max(1, octaves) {
            let sample: Float
            switch basis {
            case .value:
                sample = value(x * frequency, y * frequency, period: currentPeriod,
                               seed: seed &+ UInt32(octave) &* 131)
            case .gradient:
                sample = gradient(x * frequency, y * frequency, period: currentPeriod,
                                  seed: seed &+ UInt32(octave) &* 131)
            }
            total += sample * amplitude
            normalization += amplitude
            amplitude *= gain
            frequency *= lacunarity
            // The period must scale with the frequency or higher octaves stop tiling.
            currentPeriod = Int(Float(currentPeriod) * lacunarity)
        }
        return normalization > 0 ? total / normalization : 0
    }

    /// Ridged multifractal — sharp creases instead of smooth hills. This is what makes
    /// convincing cracks, rock and cloud edges.
    public static func ridged(_ x: Float, _ y: Float, period: Int, octaves: Int = 4,
                              gain: Float = 0.5, lacunarity: Float = 2,
                              seed: UInt32 = 0) -> Float {
        var amplitude: Float = 1
        var total: Float = 0
        var normalization: Float = 0
        var frequency: Float = 1
        var currentPeriod = period

        for octave in 0..<max(1, octaves) {
            let sample = value(x * frequency, y * frequency, period: currentPeriod,
                               seed: seed &+ UInt32(octave) &* 977)
            let ridge = 1 - abs(sample * 2 - 1)
            total += ridge * ridge * amplitude
            normalization += amplitude
            amplitude *= gain
            frequency *= lacunarity
            currentPeriod = Int(Float(currentPeriod) * lacunarity)
        }
        return normalization > 0 ? MathUtil.clamp(total / normalization, 0, 1) : 0
    }

    // MARK: - Cellular

    public struct CellularResult: Sendable {
        /// Distance to the nearest feature point, normalized to roughly [0, 1].
        public var nearest: Float
        /// Distance to the second nearest — `second - nearest` draws cell borders.
        public var second: Float
        /// A stable random value per cell, for per-cell colour variation.
        public var cellValue: Float
        public var borderDistance: Float { second - nearest }
    }

    /// Tileable Worley/cellular noise. Feature points live one per lattice cell and the
    /// cell indices wrap, so the result tiles.
    public static func cellular(_ x: Float, _ y: Float, period: Int,
                                jitter: Float = 1, seed: UInt32 = 0) -> CellularResult {
        let xi = Int(floor(x)), yi = Int(floor(y))
        var nearest: Float = .greatestFiniteMagnitude
        var second: Float = .greatestFiniteMagnitude
        var nearestCell: Float = 0

        for dy in -1...1 {
            for dx in -1...1 {
                let cx = xi + dx, cy = yi + dy
                let (jx, jy) = hash2(wrap(cx, period), wrap(cy, period), seed)
                let px = Float(cx) + 0.5 + (jx - 0.5) * jitter
                let py = Float(cy) + 0.5 + (jy - 0.5) * jitter
                let ddx = px - x, ddy = py - y
                let distance = (ddx * ddx + ddy * ddy).squareRoot()
                if distance < nearest {
                    second = nearest
                    nearest = distance
                    nearestCell = hash(wrap(cx, period), wrap(cy, period), seed &+ 7717)
                } else if distance < second {
                    second = distance
                }
            }
        }
        return CellularResult(nearest: MathUtil.clamp(nearest, 0, 1.5),
                              second: MathUtil.clamp(second, 0, 2),
                              cellValue: nearestCell)
    }

    // MARK: - Domain warping

    /// Offsets the sample position by more noise. One warp turns bland fBm into something
    /// that looks weathered; two turns it into marble and wood grain.
    public static func warp(_ x: Float, _ y: Float, period: Int, strength: Float,
                            octaves: Int = 3, seed: UInt32 = 0) -> (x: Float, y: Float) {
        let ox = fbm(x, y, period: period, octaves: octaves, seed: seed &+ 13) - 0.5
        let oy = fbm(x, y, period: period, octaves: octaves, seed: seed &+ 29) - 0.5
        return (x + ox * strength, y + oy * strength)
    }

    // MARK: - Shaping helpers

    /// Smooth 0→1 ramp between two thresholds, the workhorse for turning noise into masks.
    @inlinable
    public static func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        guard edge1 != edge0 else { return value < edge0 ? 0 : 1 }
        let t = MathUtil.clamp((value - edge0) / (edge1 - edge0), 0, 1)
        return t * t * (3 - 2 * t)
    }

    /// Contrast around a pivot. Values above 1 push a noise field toward black and white.
    @inlinable
    public static func contrast(_ value: Float, amount: Float, pivot: Float = 0.5) -> Float {
        MathUtil.clamp((value - pivot) * amount + pivot, 0, 1)
    }

    /// A seamless sine wave over lattice coordinates.
    ///
    /// This exists because getting it wrong is subtle and expensive: a wave like
    /// `sin(x * 0.6)` over a tile of four lattice cells completes 2.4 cycles, so the tile's
    /// left and right edges do not match and every wall in the level shows a grid of seams.
    /// Taking the cycle counts as integers makes that impossible to express.
    ///
    /// - Parameters:
    ///   - x, y: lattice coordinates, running 0…`period` across one tile.
    ///   - cyclesX, cyclesY: whole wave cycles across the tile along each axis.
    ///   - phase: extra phase in radians; safe to drive from periodic noise.
    public static func wave(_ x: Float, _ y: Float, period: Int,
                            cyclesX: Int, cyclesY: Int, phase: Float = 0) -> Float {
        guard period > 0 else { return 0.5 }
        let u = x / Float(period)
        let v = y / Float(period)
        let angle = (u * Float(cyclesX) + v * Float(cyclesY)) * 2 * .pi + phase
        return (sin(angle) + 1) * 0.5
    }

    /// A tileable stripe field, used for brushed metal, wood planks and fabric weave.
    public static func stripes(_ position: Float, count: Int, sharpness: Float = 1) -> Float {
        let phase = position * Float(count) * 2 * .pi
        let wave = (sin(phase) + 1) * 0.5
        return sharpness == 1 ? wave : pow(wave, sharpness)
    }

    /// Distance from the nearest line of a tileable grid, in cell units — used for grout,
    /// panel seams and tile bevels.
    public static func gridDistance(_ x: Float, _ y: Float, cells: Int) -> Float {
        let fx = x * Float(cells)
        let fy = y * Float(cells)
        let dx = min(fx - floor(fx), 1 - (fx - floor(fx)))
        let dy = min(fy - floor(fy), 1 - (fy - floor(fy)))
        return min(dx, dy)
    }

    /// Which grid cell a point falls in, for per-cell variation (tiles, planks, panels).
    public static func gridCell(_ x: Float, _ y: Float, cells: Int) -> (Int, Int) {
        (Int(floor(x * Float(cells))), Int(floor(y * Float(cells))))
    }
}
