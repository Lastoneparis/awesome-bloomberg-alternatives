import Foundation
import UIKit
import CriticalStrikeCore

/// Particle sprites and decals.
///
/// SceneKit's default particle is a flat white square. Every effect in the game — smoke,
/// sparks, blood, muzzle flash, bullet holes — is a generated RGBA sprite with a real
/// alpha falloff, which is the single cheapest upgrade available to how the game looks in
/// motion.
enum SpriteKind: String, CaseIterable {
    case smokePuff
    case dustPuff
    case spark
    case ember
    case muzzleStar
    case muzzleCore
    case bloodDroplet
    case glowDot
    case tracerSegment
    case snowFlake
    case waterSplash
}

enum DecalKind: String, CaseIterable {
    case bulletHoleHard      // concrete, tile, stone
    case bulletHoleMetal     // bright rim, torn edges
    case bulletHoleWood      // splintered
    case bulletHoleSoft      // dirt, sand, fabric
    case glassCrack
    case bloodSplat
    case scorch

    static func forSurface(_ surface: SurfaceKind) -> DecalKind {
        switch surface {
        case .metal: return .bulletHoleMetal
        case .wood: return .bulletHoleWood
        case .glass: return .glassCrack
        case .flesh: return .bloodSplat
        case .dirt, .sand, .grass, .fabric: return .bulletHoleSoft
        default: return .bulletHoleHard
        }
    }
}

enum SpriteFactory {

    static func spriteResolution(for quality: GraphicsQuality) -> Int {
        switch quality {
        case .low: return 32
        case .medium: return 48
        case .high: return 64
        case .ultra: return 96
        }
    }

    static func decalResolution(for quality: GraphicsQuality) -> Int {
        switch quality {
        case .low: return 48
        case .medium: return 64
        case .high: return 96
        case .ultra: return 128
        }
    }

    // MARK: - Particles

    static func sprite(_ kind: SpriteKind, size: Int, seed: UInt32 = 0x59A1) -> UIImage? {
        var canvas = PixelCanvas(width: size, height: size)
        let centre = Float(size) * 0.5
        let inverseRadius = 1 / centre

        for y in 0..<size {
            for x in 0..<size {
                let dx = (Float(x) + 0.5 - centre) * inverseRadius
                let dy = (Float(y) + 0.5 - centre) * inverseRadius
                let radius = (dx * dx + dy * dy).squareRoot()
                let angle = atan2(dy, dx)
                let nx = Float(x) / Float(size), ny = Float(y) / Float(size)

                var color = RGB.white
                var alpha: Float = 0

                switch kind {
                case .smokePuff:
                    // Billowing edge: modulate the radius by angular noise so no two
                    // puffs read as the same circle.
                    let lump = Noise.fbm(nx * 6, ny * 6, period: 6, octaves: 4, seed: seed)
                    let edge = 0.95 + (lump - 0.5) * 0.5
                    alpha = 1 - Noise.smoothstep(edge * 0.25, edge, radius)
                    alpha *= 0.55 + lump * 0.45
                    // Interior density variation so overlapping puffs do not flatten out.
                    let density = Noise.fbm(nx * 12, ny * 12, period: 12, octaves: 3,
                                            seed: seed &+ 3)
                    color = RGB(0.78, 0.78, 0.8).scaled(0.75 + density * 0.35)

                case .dustPuff:
                    let lump = Noise.fbm(nx * 8, ny * 8, period: 8, octaves: 3, seed: seed &+ 5)
                    alpha = (1 - Noise.smoothstep(0.2, 0.9 + (lump - 0.5) * 0.4, radius))
                        * (0.4 + lump * 0.5)
                    color = RGB(0.72, 0.66, 0.55)

                case .spark:
                    // Hot core with a hard falloff — additive blending does the rest.
                    let core = 1 - Noise.smoothstep(0.0, 0.18, radius)
                    let halo = (1 - Noise.smoothstep(0.1, 0.7, radius)) * 0.35
                    alpha = MathUtil.clamp(core + halo, 0, 1)
                    color = RGB(1, 0.85, 0.5).lerp(.white, core)

                case .ember:
                    let core = 1 - Noise.smoothstep(0.0, 0.3, radius)
                    alpha = core
                    color = RGB(1, 0.45, 0.12).lerp(RGB(1, 0.9, 0.6), core * core)

                case .muzzleStar:
                    // Four-point star: cheap, and reads instantly as a muzzle flash.
                    let points: Float = 4
                    let spikes = abs(cos(angle * points)) 
                    let reach = 0.22 + pow(spikes, 3) * 0.78
                    alpha = 1 - Noise.smoothstep(reach * 0.35, reach, radius)
                    color = RGB(1, 0.92, 0.72)

                case .muzzleCore:
                    let core = 1 - Noise.smoothstep(0.0, 0.42, radius)
                    alpha = pow(core, 0.6)
                    color = RGB(1, 0.97, 0.88)

                case .bloodDroplet:
                    let wobble = Noise.fbm(nx * 5, ny * 5, period: 5, octaves: 3, seed: seed &+ 7)
                    alpha = 1 - Noise.smoothstep(0.55 + (wobble - 0.5) * 0.3, 0.78, radius)
                    color = RGB(0.42, 0.05, 0.06).lerp(RGB(0.62, 0.1, 0.1), wobble)

                case .glowDot:
                    alpha = pow(MathUtil.clamp(1 - radius, 0, 1), 2.2)
                    color = .white

                case .tracerSegment:
                    // A horizontal bar with a soft vertical falloff; stretched along the
                    // shot direction by the effect that uses it.
                    let vertical = 1 - Noise.smoothstep(0.0, 0.5, abs(dy))
                    let horizontal = 1 - Noise.smoothstep(0.7, 1.0, abs(dx))
                    alpha = pow(vertical, 2) * horizontal
                    color = RGB(1, 0.88, 0.62)

                case .snowFlake:
                    let arms: Float = 6
                    let spikes = abs(cos(angle * arms * 0.5))
                    let reach = 0.3 + pow(spikes, 4) * 0.7
                    alpha = (1 - Noise.smoothstep(reach * 0.5, reach, radius)) * 0.9
                    color = RGB(0.95, 0.97, 1)

                case .waterSplash:
                    let ring = 1 - Noise.smoothstep(0.0, 0.12, abs(radius - 0.6))
                    let core = 1 - Noise.smoothstep(0.0, 0.35, radius)
                    alpha = MathUtil.clamp(ring * 0.7 + core * 0.5, 0, 1)
                    color = RGB(0.7, 0.85, 0.95)
                }

                canvas.set(x: x, y: y, color: color, alpha: MathUtil.clamp(alpha, 0, 1))
            }
        }
        return canvas.makeImage()
    }

    // MARK: - Decals

    static func decal(_ kind: DecalKind, size: Int, seed: UInt32 = 0xDEC1) -> UIImage? {
        var canvas = PixelCanvas(width: size, height: size)
        let centre = Float(size) * 0.5
        let inverseRadius = 1 / centre

        for y in 0..<size {
            for x in 0..<size {
                let dx = (Float(x) + 0.5 - centre) * inverseRadius
                let dy = (Float(y) + 0.5 - centre) * inverseRadius
                let radius = (dx * dx + dy * dy).squareRoot()
                let angle = atan2(dy, dx)
                let nx = Float(x) / Float(size), ny = Float(y) / Float(size)

                var color = RGB.black
                var alpha: Float = 0

                switch kind {
                case .bulletHoleHard:
                    // Crater, a ring of pulverised material, and chipped radial cracks.
                    let hole = 1 - Noise.smoothstep(0.14, 0.2, radius)
                    let chipped = Noise.fbm(nx * 6, ny * 6, period: 6, octaves: 3, seed: seed &+ 5)
                    // An irregular rim: a perfectly round ring reads as a sticker.
                    let rim = (1 - Noise.smoothstep(0.2 + (chipped - 0.5) * 0.18, 0.46, radius))
                        * Noise.smoothstep(0.12, 0.2, radius)
                    let cracks = radialCracks(angle: angle, radius: radius, seed: seed,
                                              count: 11, reach: 0.9, width: 0.032)
                    alpha = MathUtil.clamp(hole + rim * 0.5 + cracks * 0.85, 0, 1)
                    color = RGB(0.06, 0.06, 0.07).lerp(RGB(0.78, 0.76, 0.72), rim)

                case .bulletHoleMetal:
                    let hole = 1 - Noise.smoothstep(0.12, 0.17, radius)
                    // Torn metal petals around the entry.
                    let petals = abs(cos(angle * 5 + Noise.hash(0, 0, seed) * 6))
                    let tear = (1 - Noise.smoothstep(0.15, 0.15 + petals * 0.22, radius))
                        * Noise.smoothstep(0.1, 0.16, radius)
                    alpha = MathUtil.clamp(hole + tear * 0.85, 0, 1)
                    color = RGB(0.04, 0.04, 0.05).lerp(RGB(0.85, 0.86, 0.9), tear)

                case .bulletHoleWood:
                    let hole = 1 - Noise.smoothstep(0.12, 0.18, radius)
                    let splinters = radialCracks(angle: angle, radius: radius, seed: seed,
                                                 count: 14, reach: 0.95)
                    alpha = MathUtil.clamp(hole + splinters * 0.7, 0, 1)
                    color = RGB(0.09, 0.05, 0.02).lerp(RGB(0.55, 0.38, 0.2), splinters * 0.7)

                case .bulletHoleSoft:
                    // No crack structure in soft material: a scatter of displaced grains.
                    let scatter = Noise.fbm(nx * 7, ny * 7, period: 7, octaves: 3, seed: seed)
                    let hole = 1 - Noise.smoothstep(0.16, 0.34 + (scatter - 0.5) * 0.2, radius)
                    alpha = hole * (0.55 + scatter * 0.45)
                    color = RGB(0.12, 0.09, 0.06)

                case .glassCrack:
                    let hole = 1 - Noise.smoothstep(0.05, 0.1, radius)
                    let radials = radialCracks(angle: angle, radius: radius, seed: seed,
                                               count: 11, reach: 1.0, width: 0.012)
                    // Concentric fractures make it read as a spider web rather than a star.
                    let rings = concentricCracks(radius: radius, seed: seed)
                    alpha = MathUtil.clamp(hole + radials * 0.9 + rings * 0.5, 0, 1)
                    color = RGB(0.86, 0.94, 0.98)

                case .bloodSplat:
                    // A ragged pool, not a disc: the edge radius is modulated hard enough
                    // that the outline reads as splatter rather than a stamp.
                    let wobble = Noise.fbm(nx * 7, ny * 7, period: 7, octaves: 4,
                                           basis: .gradient, seed: seed)
                    let edge = 0.3 + (wobble - 0.5) * 0.7
                    let body = 1 - Noise.smoothstep(edge, edge + 0.16, radius)
                    // Satellite droplets thrown outward from the main pool, bigger further
                    // out so the cast direction reads.
                    let droplets = Noise.cellular(nx * 6, ny * 6, period: 6, jitter: 1,
                                                  seed: seed &+ 3)
                    let dropletSize = 0.06 + droplets.cellValue * 0.14
                    let spatter = droplets.cellValue > 0.6
                        ? (1 - Noise.smoothstep(dropletSize * 0.5, dropletSize, droplets.nearest))
                        : 0
                    alpha = MathUtil.clamp(body + spatter * 0.85, 0, 1)
                        * (1 - Noise.smoothstep(0.82, 1.0, radius))
                    color = RGB(0.3, 0.02, 0.03).lerp(RGB(0.55, 0.07, 0.07), wobble)

                case .scorch:
                    let smudge = Noise.fbm(nx * 5, ny * 5, period: 5, octaves: 4,
                                           basis: .gradient, seed: seed)
                    alpha = (1 - Noise.smoothstep(0.25 + (smudge - 0.5) * 0.4, 0.85, radius))
                        * (0.5 + smudge * 0.5)
                    color = RGB(0.05, 0.045, 0.04)
                }

                canvas.set(x: x, y: y, color: color, alpha: MathUtil.clamp(alpha, 0, 1))
            }
        }
        return canvas.makeImage()
    }

    /// Cracks radiating from the centre, with each spoke at its own angle and length.
    private static func radialCracks(angle: Float, radius: Float, seed: UInt32,
                                     count: Int, reach: Float, width: Float = 0.02) -> Float {
        var strongest: Float = 0
        for index in 0..<count {
            let spokeSeed = seed &+ UInt32(index) &* 131
            let spokeAngle = (Noise.hash(index, 0, spokeSeed) * 2 - 1) * .pi
            let spokeLength = reach * (0.35 + Noise.hash(index, 1, spokeSeed) * 0.65)
            guard radius < spokeLength else { continue }

            var difference = abs(MathUtil.wrapAngle(angle - spokeAngle))
            // A slight wander so the spokes are not perfectly straight lines.
            difference -= (Noise.hash(index, Int(radius * 20), spokeSeed) - 0.5) * 0.08
            // Cracks taper: wide at the hole, hairline at the tip.
            let taper = 1 - radius / spokeLength
            let halfWidth = (width + taper * width * 2) / Swift.max(radius, 0.08)
            let line = 1 - Noise.smoothstep(0, halfWidth, abs(difference))
            strongest = Swift.max(strongest, line * taper)
        }
        return strongest
    }

    private static func concentricCracks(radius: Float, seed: UInt32) -> Float {
        var strongest: Float = 0
        for index in 1...3 {
            let ringRadius = 0.2 + Float(index) * 0.2 + Noise.hash(index, 9, seed) * 0.06
            let line = 1 - Noise.smoothstep(0, 0.012, abs(radius - ringRadius))
            strongest = Swift.max(strongest, line * (1 - radius))
        }
        return strongest
    }
}
