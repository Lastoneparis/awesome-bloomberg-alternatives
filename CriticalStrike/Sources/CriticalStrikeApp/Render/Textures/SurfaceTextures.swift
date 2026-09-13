import Foundation
import UIKit
import CriticalStrikeCore

/// A complete PBR material's worth of generated images.
struct TextureSet {
    var albedo: UIImage?
    var normal: UIImage?
    var roughness: UIImage?
    var occlusion: UIImage?
    var metalness: UIImage?
    var emission: UIImage?
}

/// Generates the surface textures.
///
/// Each surface is authored as a height field plus a small number of masks, and every
/// other map is derived from those. The results tile seamlessly because every noise call
/// is periodic, and they are deterministic because every seed is fixed — which is what
/// lets the results be cached on disk between launches.
enum SurfaceTextureFactory {

    /// Texture resolution by quality tier. Low-end devices get 256², which still reads
    /// correctly at the distances a shooter actually plays at.
    static func resolution(for quality: GraphicsQuality) -> Int {
        #if DEBUG
        // Generation is float-heavy and a debug build runs it unoptimised, where a 512²
        // surface takes long enough to make iteration painful. Release is unaffected.
        return quality == .low ? 192 : 256
        #else
        switch quality {
        case .low: return 256
        case .medium: return 384
        case .high: return 512
        case .ultra: return 768
        }
        #endif
    }

    /// Large-scale variation, sampled in world space across tens of metres rather than
    /// once per texture tile.
    ///
    /// A surface texture repeats every 2.5 m, so a forty-metre wall shows the same tile
    /// sixteen times, and the eye finds that grid immediately no matter how good the tile
    /// is. Every world material multiplies its albedo by this field at a scale no tile can
    /// reach, which breaks the repetition for the cost of one texture fetch. It is
    /// deliberately low-contrast: the goal is a drift in tone across a wall, not a second
    /// pattern competing with the first.
    static func macroVariation(size: Int = 256, seed: UInt32 = 0xACE5) -> UIImage? {
        // Three scales, because one is not enough: broad fBm alone reads as fog drifting
        // across the wall rather than as anything that happened to the wall. The mid band
        // supplies the streaks and stains, and the cellular patches supply the flat-toned
        // regions that make one stretch of concrete look like a different pour.
        let broadPeriod = 6, midPeriod = 14, patchPeriod = 4
        let field = ScalarField(width: size, height: size) { x, y in
            let warped = Noise.warp(x * Float(broadPeriod), y * Float(broadPeriod),
                                    period: broadPeriod, strength: 0.6, octaves: 2, seed: seed)
            let broad = Noise.fbm(warped.x, warped.y, period: broadPeriod, octaves: 4,
                                  gain: 0.55, seed: seed)
            let mid = Noise.smoothstep(0.35, 0.72,
                                       Noise.fbm(x * Float(midPeriod), y * Float(midPeriod),
                                                 period: midPeriod, octaves: 3, seed: seed &+ 11))
            let patch = Noise.cellular(x * Float(patchPeriod), y * Float(patchPeriod),
                                       period: patchPeriod, jitter: 0.9, seed: seed &+ 5)
            return broad * 0.52 + mid * 0.30 + patch.cellValue * 0.18
        }
        .normalized()
        .mapped { 0.5 + ($0 - 0.5) * 0.9 }
        // Radius 1, not more: blurring harder turns the streaks back into fog.
        .blurred(radius: 1)
        return TextureMath.grayscale(field)
    }

    /// Deterministic per-surface seed, so a given surface always looks the same.
    private static func seed(for surface: SurfaceKind) -> UInt32 {
        0x5EED &+ UInt32(surface.rawValue) &* 7919
    }

    static func make(surface: SurfaceKind, size: Int) -> TextureSet {
        let seed = seed(for: surface)
        // `period` is in lattice cells across the tile. Bigger numbers mean finer detail.
        switch surface {
        case .concrete: return concrete(size: size, seed: seed)
        case .metal: return metal(size: size, seed: seed)
        case .wood: return wood(size: size, seed: seed)
        case .dirt: return dirt(size: size, seed: seed)
        case .sand: return sand(size: size, seed: seed)
        case .grass: return grass(size: size, seed: seed)
        case .water: return water(size: size, seed: seed)
        case .glass: return glass(size: size, seed: seed)
        case .fabric: return fabric(size: size, seed: seed)
        case .flesh: return flesh(size: size, seed: seed)
        case .plastic: return plastic(size: size, seed: seed)
        case .tile: return tile(size: size, seed: seed)
        }
    }

    // MARK: - Concrete

    /// Poured concrete: coarse aggregate under a trowelled surface, air-bubble pits, a
    /// crack network, and darker water staining that pools in the low spots.
    private static func concrete(size: Int, seed: UInt32) -> TextureSet {
        // Exposed aggregate: stones of varying size, mostly buried, a few proud of the
        // surface. Using the cell value to vary the size is what stops it reading as an
        // evenly-spaced dot screen.
        let aggregate = ScalarField(width: size, height: size) { x, y in
            let cell = Noise.cellular(x * 17, y * 17, period: 17, jitter: 1, seed: seed)
            let stoneSize = 0.22 + cell.cellValue * 0.2
            return (1 - Noise.smoothstep(stoneSize * 0.55, stoneSize, cell.nearest))
                * (0.35 + cell.cellValue * 0.65)
        }
        // Air-bubble pits, which is what actually breaks up a concrete surface close up.
        let pits = ScalarField(width: size, height: size) { x, y in
            let cell = Noise.cellular(x * 40, y * 40, period: 40, jitter: 1, seed: seed &+ 29)
            guard cell.cellValue > 0.7 else { return 0 }
            return 1 - Noise.smoothstep(0.0, 0.22, cell.nearest)
        }
        let grain = ScalarField(width: size, height: size) { x, y in
            Noise.fbm(x * 48, y * 48, period: 48, octaves: 4, seed: seed &+ 3)
        }
        // Cracks follow cell borders, not noise ridges. A thresholded ridged field gives
        // disconnected squiggles; the boundary between Worley cells gives a connected
        // polygonal network, which is how concrete actually fractures.
        let cracks = ScalarField(width: size, height: size) { x, y in
            let (wx, wy) = Noise.warp(x * 5, y * 5, period: 5, strength: 1.2, seed: seed &+ 11)
            let major = Noise.cellular(wx, wy, period: 5, jitter: 1, seed: seed &+ 17)
            // Only some borders crack, so the network is broken rather than a full mesh.
            // Only the most stressed borders crack — a fully cracked mesh reads as dried
            // mud, not as a wall.
            let majorCrack = (1 - Noise.smoothstep(0.0, 0.045, major.borderDistance))
                * Noise.smoothstep(0.62, 0.82, major.cellValue)

            let (cx, cy) = Noise.warp(x * 13, y * 13, period: 13, strength: 0.8, seed: seed &+ 31)
            let craze = Noise.cellular(cx, cy, period: 13, jitter: 1, seed: seed &+ 37)
            let crazeCrack = (1 - Noise.smoothstep(0.0, 0.025, craze.borderDistance))
                * Noise.smoothstep(0.78, 0.93, craze.cellValue)

            return MathUtil.clamp(majorCrack + crazeCrack * 0.45, 0, 1)
        }
        // Broad tonal blotches — pours never cure evenly, and without this the surface
        // reads as a flat swatch no matter how much fine detail it has.
        let mottle = ScalarField(width: size, height: size) { x, y in
            Noise.fbm(x * 2, y * 2, period: 2, octaves: 4, basis: .gradient, seed: seed &+ 19)
        }
        let stains = ScalarField(width: size, height: size) { x, y in
            Noise.fbm(x * 4, y * 4, period: 4, octaves: 5, basis: .gradient, seed: seed &+ 23)
        }

        let height = grain.mapped { $0 * 0.35 }
            .combined(with: aggregate) { base, a in base + a * 0.5 }
            .combined(with: pits) { base, p in base - p * 0.8 }
            .combined(with: cracks) { base, c in base - c * 0.8 }
            .normalized()

        let base = RGB(hex: 0x8F8B82)
        let pale = RGB(hex: 0xA9A59A)
        let dark = RGB(hex: 0x55534E)
        let aggregateColor = RGB(hex: 0x8E8A80)

        var canvas = PixelCanvas(width: size, height: size)
        var roughnessField = ScalarField(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                let h = height[x, y]
                // Large-scale tone first, fine detail on top.
                var color = base.lerp(pale, mottle[x, y])
                color = color.lerp(aggregateColor, aggregate[x, y] * 0.55)
                color = color.scaled(0.86 + h * 0.26)
                color = color.lerp(dark, Noise.smoothstep(0.58, 0.92, stains[x, y]) * 0.3)
                color = color.lerp(dark.scaled(0.75), pits[x, y] * 0.8)
                color = color.lerp(dark.scaled(0.55), cracks[x, y] * 0.85)
                canvas.set(x: x, y: y, color: color)
                // Concrete is uniformly rough; cracks and pits are rougher still.
                roughnessField[x, y] = MathUtil.clamp(0.86 + cracks[x, y] * 0.1
                                                      + pits[x, y] * 0.08
                                                      - aggregate[x, y] * 0.06, 0, 1)
            }
        }

        return TextureSet(albedo: canvas.makeImage(),
                          normal: TextureMath.normalMap(from: height, strength: 3.0),
                          roughness: TextureMath.grayscale(roughnessField),
                          occlusion: TextureMath.grayscale(
                            TextureMath.ambientOcclusion(from: height, radius: 3)))
    }

    // MARK: - Metal

    /// Industrial panel: brushed grain along X, panel seams, rivets on the seams, and
    /// scratches that cut through to bright bare metal.
    private static func metal(size: Int, seed: UInt32) -> TextureSet {
        let cells = 2
        let brushed = ScalarField(width: size, height: size) { x, y in
            // Very anisotropic noise: stretched 40:1 so it reads as a brushed finish.
            Noise.fbm(x * 3, y * 110, period: 110, octaves: 3, seed: seed)
        }
        let seams = ScalarField(width: size, height: size) { x, y in
            1 - Noise.smoothstep(0.0, 0.022, Noise.gridDistance(x, y, cells: cells))
        }
        // Rivets sit *on* the seam lines at regular spacing, which is where they would
        // actually be. Placing them on a separate grid and masking by the seam produced
        // clipped arcs instead of round heads.
        let rivetSpacing = 8
        let rivets = ScalarField(width: size, height: size) { x, y in
            let seamU = x * Float(cells)
            let seamV = y * Float(cells)
            // Distance to the nearest vertical and horizontal seam, in tile units.
            let toVertical = abs(seamU - (seamU).rounded()) / Float(cells)
            let toHorizontal = abs(seamV - (seamV).rounded()) / Float(cells)
            let step = 1 / Float(rivetSpacing)

            // Along a vertical seam, rivets are spaced down it; and vice versa.
            let alongY = abs(y / step - (y / step).rounded()) * step
            let alongX = abs(x / step - (x / step).rounded()) * step
            let verticalRivet = (toVertical * toVertical + alongY * alongY).squareRoot()
            let horizontalRivet = (toHorizontal * toHorizontal + alongX * alongX).squareRoot()
            let distance = Swift.min(verticalRivet, horizontalRivet)
            return 1 - Noise.smoothstep(0.013, 0.021, distance)
        }
        let scratches = ScalarField(width: size, height: size) { x, y in
            let (wx, wy) = Noise.warp(x * 10, y * 10, period: 10, strength: 2.2, seed: seed &+ 41)
            let ridge = Noise.ridged(wx * 1.4, wy * 0.3, period: 14, octaves: 3, seed: seed &+ 47)
            return Noise.smoothstep(0.88, 0.99, ridge)
        }
        // Rust starts where water sits: along the seams and around the rivets.
        let rust = ScalarField(width: size, height: size) { x, y in
            let field = Noise.fbm(x * 4, y * 4, period: 4, octaves: 5, basis: .gradient,
                                  seed: seed &+ 59)
            // A little rust at the seams, not a rusted sheet: the panels should still
            // read as maintained industrial steel.
            let nearSeam = 1 - Noise.smoothstep(0.0, 0.12, Noise.gridDistance(x, y, cells: cells))
            let bias = field + nearSeam * 0.16
            return Noise.smoothstep(0.60, 0.82, bias)
        }

        let height = brushed.mapped { $0 * 0.12 }
            .combined(with: seams) { base, s in base - s * 0.7 }
            .combined(with: rivets) { base, r in base + r * 0.9 }
            .combined(with: scratches) { base, s in base - s * 0.25 }
            .normalized()

        let steel = RGB(hex: 0x7C848D)
        let bare = RGB(hex: 0xC8CED4)
        let rustColor = RGB(hex: 0x7E5233)
        let shadow = RGB(hex: 0x2E3339)

        var canvas = PixelCanvas(width: size, height: size)
        var roughnessField = ScalarField(width: size, height: size)
        var metalnessField = ScalarField(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                let rustAmount = rust[x, y]
                var color = steel.scaled(0.88 + brushed[x, y] * 0.3)
                color = color.lerp(shadow, seams[x, y] * 0.65)
                color = color.lerp(bare, scratches[x, y])
                color = color.lerp(rustColor.lerp(RGB(hex: 0x6B4028), rustAmount), rustAmount * 0.7)
                // Rivet heads are proud of the panel, so they catch more light.
                color = color.lerp(bare.scaled(1.02), rivets[x, y] * 0.8)
                canvas.set(x: x, y: y, color: color)
                // Rust kills both the reflectivity and the metalness.
                roughnessField[x, y] = MathUtil.clamp(0.32 + rustAmount * 0.55
                                                      + seams[x, y] * 0.2
                                                      - scratches[x, y] * 0.2, 0.05, 1)
                metalnessField[x, y] = MathUtil.clamp(0.95 - rustAmount * 0.8, 0, 1)
            }
        }

        return TextureSet(albedo: canvas.makeImage(),
                          normal: TextureMath.normalMap(from: height, strength: 4.0),
                          roughness: TextureMath.grayscale(roughnessField),
                          occlusion: TextureMath.grayscale(
                            TextureMath.ambientOcclusion(from: height, radius: 3)),
                          metalness: TextureMath.grayscale(metalnessField))
    }

    // MARK: - Wood

    /// Planks: growth rings from domain-warped concentric noise, grain lines along the
    /// plank, per-plank colour variation, and dark gaps between boards.
    private static func wood(size: Int, seed: UInt32) -> TextureSet {
        let plankCount = 5

        func plankIndex(_ y: Float) -> Int { Int(floor(y * Float(plankCount))) }

        let rings = ScalarField(width: size, height: size) { x, y in
            let plank = plankIndex(y)
            let plankSeed = seed &+ UInt32(truncatingIfNeeded: plank) &* 313
            // Rings run along the plank, warped so they are never perfectly straight.
            let (wx, wy) = Noise.warp(x * 3, y * 12, period: 12, strength: 0.9, seed: plankSeed)
            // Each board is cut from a different part of the log, so the ring spacing
            // differs — boards with identical grain are the giveaway of a tiled texture.
            let cycles = 34 + Int(Noise.hash(plank, 3, plankSeed) * 3) * 6
            let drift = Noise.fbm(wx, wy, period: 12, octaves: 3, seed: plankSeed) * 4
            return Noise.wave(wx, wy, period: 12, cyclesX: 0, cyclesY: cycles, phase: drift)
        }
        let grain = ScalarField(width: size, height: size) { x, y in
            Noise.fbm(x * 120, y * 8, period: 120, octaves: 3, seed: seed &+ 71)
        }
        let gaps = ScalarField(width: size, height: size) { _, y in
            let fy = y * Float(plankCount)
            let local = fy - floor(fy)
            let edge = Swift.min(local, 1 - local)
            return 1 - Noise.smoothstep(0.0, 0.035, edge)
        }
        let knots = ScalarField(width: size, height: size) { x, y in
            let cell = Noise.cellular(x * 3, y * 3, period: 3, jitter: 1, seed: seed &+ 83)
            guard cell.cellValue > 0.82 else { return 0 }
            return 1 - Noise.smoothstep(0.0, 0.16, cell.nearest)
        }
        // Grain bends around a knot rather than running through it.
        let knotHalo = ScalarField(width: size, height: size) { x, y in
            let cell = Noise.cellular(x * 3, y * 3, period: 3, jitter: 1, seed: seed &+ 83)
            guard cell.cellValue > 0.82 else { return 0 }
            return (1 - Noise.smoothstep(0.12, 0.34, cell.nearest))
                * Noise.smoothstep(0.1, 0.18, cell.nearest)
        }

        let height = rings.mapped { $0 * 0.35 }
            .combined(with: grain) { base, g in base + g * 0.25 }
            .combined(with: gaps) { base, g in base - g * 1.2 }
            .combined(with: knots) { base, k in base - k * 0.5 }
            .normalized()

        // Slightly desaturated from the obvious "pine orange", which reads as plastic.
        let light = RGB(hex: 0xA3805A)
        let dark = RGB(hex: 0x63472C)
        let knotColor = RGB(hex: 0x3A2313)

        var canvas = PixelCanvas(width: size, height: size)
        var roughnessField = ScalarField(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                let plank = plankIndex(Float(y) / Float(size))
                // Each board comes from a different part of the tree.
                let plankTint = Noise.hash(plank, 0, seed &+ 97) * 0.22 - 0.11
                var color = light.lerp(dark, rings[x, y] * 0.75)
                color = color.scaled(1 + plankTint)
                color = color.scaled(0.9 + grain[x, y] * 0.22)
                color = color.lerp(dark, knotHalo[x, y] * 0.5)
                color = color.lerp(knotColor, knots[x, y])
                color = color.lerp(RGB(hex: 0x241608), gaps[x, y])
                canvas.set(x: x, y: y, color: color)
                // Late growth rings are denser and shinier than early wood.
                roughnessField[x, y] = MathUtil.clamp(0.72 - rings[x, y] * 0.14
                                                      + gaps[x, y] * 0.2, 0, 1)
            }
        }

        return TextureSet(albedo: canvas.makeImage(),
                          normal: TextureMath.normalMap(from: height, strength: 2.6),
                          roughness: TextureMath.grayscale(roughnessField),
                          occlusion: TextureMath.grayscale(
                            TextureMath.ambientOcclusion(from: height, radius: 4)))
    }

    // MARK: - Ground

    private static func dirt(size: Int, seed: UInt32) -> TextureSet {
        let clumps = ScalarField(width: size, height: size) { x, y in
            Noise.fbm(x * 9, y * 9, period: 9, octaves: 5, basis: .gradient, seed: seed)
        }
        let pebbles = ScalarField(width: size, height: size) { x, y in
            let cell = Noise.cellular(x * 34, y * 34, period: 34, jitter: 1, seed: seed &+ 5)
            guard cell.cellValue > 0.55 else { return 0 }
            return 1 - Noise.smoothstep(0.0, 0.3, cell.nearest)
        }
        // Dried mud cracks into plates, which is a cell-border pattern too.
        let cracks = ScalarField(width: size, height: size) { x, y in
            let (wx, wy) = Noise.warp(x * 9, y * 9, period: 9, strength: 0.9, seed: seed &+ 11)
            let cell = Noise.cellular(wx, wy, period: 9, jitter: 1, seed: seed &+ 13)
            return (1 - Noise.smoothstep(0.0, 0.05, cell.borderDistance))
                * Noise.smoothstep(0.4, 0.7, cell.cellValue)
        }
        let height = clumps.mapped { $0 * 0.5 }
            .combined(with: pebbles) { base, p in base + p * 0.55 }
            .combined(with: cracks) { base, c in base - c * 0.6 }
            .normalized()

        let soil = RGB(hex: 0x6E5942)
        let drySoil = RGB(hex: 0x8B7454)
        let stone = RGB(hex: 0x9A948A)

        var canvas = PixelCanvas(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                var color = soil.lerp(drySoil, clumps[x, y])
                color = color.lerp(stone, pebbles[x, y] * 0.9)
                color = color.scaled(0.8 + height[x, y] * 0.4)
                canvas.set(x: x, y: y, color: color)
            }
        }
        return TextureSet(albedo: canvas.makeImage(),
                          normal: TextureMath.normalMap(from: height, strength: 3.4),
                          roughness: TextureMath.grayscale(height.mapped { 0.95 - $0 * 0.1 }),
                          occlusion: TextureMath.grayscale(
                            TextureMath.ambientOcclusion(from: height, radius: 4)))
    }

    private static func sand(size: Int, seed: UInt32) -> TextureSet {
        // Wind ripples: a warped sine, which is genuinely how dunes pattern.
        let ripples = ScalarField(width: size, height: size) { x, y in
            let (wx, wy) = Noise.warp(x * 4, y * 4, period: 4, strength: 0.6, seed: seed)
            // Whole cycles per tile, or the ripples would not line up at the edges.
            return Noise.wave(wx, wy, period: 4, cyclesX: 3, cyclesY: 11)
        }
        let grains = ScalarField(width: size, height: size) { x, y in
            Noise.fbm(x * 150, y * 150, period: 150, octaves: 2, seed: seed &+ 3)
        }
        let drift = ScalarField(width: size, height: size) { x, y in
            Noise.fbm(x * 5, y * 5, period: 5, octaves: 4, basis: .gradient, seed: seed &+ 7)
        }
        let height = ripples.mapped { $0 * 0.5 }
            .combined(with: grains) { base, g in base + g * 0.12 }
            .combined(with: drift) { base, d in base + d * 0.35 }
            .normalized()

        let sandLight = RGB(hex: 0xD9C08A)
        let sandDark = RGB(hex: 0xB0946A)

        var canvas = PixelCanvas(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                let color = sandDark.lerp(sandLight, height[x, y]).scaled(0.94 + grains[x, y] * 0.12)
                canvas.set(x: x, y: y, color: color)
            }
        }
        return TextureSet(albedo: canvas.makeImage(),
                          normal: TextureMath.normalMap(from: height, strength: 2.0),
                          roughness: TextureMath.grayscale(height.mapped { _ in 0.93 }),
                          occlusion: TextureMath.grayscale(
                            TextureMath.ambientOcclusion(from: height, radius: 5, strength: 0.6)))
    }

    private static func grass(size: Int, seed: UInt32) -> TextureSet {
        // Two blade layers at different scales and orientations. One layer alone spaces
        // the blades too evenly and reads as corduroy.
        let blades = ScalarField(width: size, height: size) { x, y in
            let coarse = Noise.cellular(x * 46, y * 18, period: 46, jitter: 1, seed: seed)
            let fine = Noise.cellular(x * 24, y * 70, period: 70, jitter: 1, seed: seed &+ 101)
            // Blade length varies per cell, so the field is not a uniform stipple.
            let coarseBlade = (1 - Noise.smoothstep(0.0, 0.3 + coarse.cellValue * 0.4,
                                                    coarse.nearest)) * (0.5 + coarse.cellValue * 0.5)
            let fineBlade = (1 - Noise.smoothstep(0.0, 0.25 + fine.cellValue * 0.3,
                                                  fine.nearest)) * 0.7
            return MathUtil.clamp(Swift.max(coarseBlade, fineBlade), 0, 1)
        }
        // Which blade a pixel belongs to, for per-blade colour.
        let bladeTint = ScalarField(width: size, height: size) { x, y in
            Noise.cellular(x * 46, y * 18, period: 46, jitter: 1, seed: seed).cellValue
        }
        let patches = ScalarField(width: size, height: size) { x, y in
            Noise.fbm(x * 6, y * 6, period: 6, octaves: 4, basis: .gradient, seed: seed &+ 9)
        }
        let soil = ScalarField(width: size, height: size) { x, y in
            Noise.fbm(x * 20, y * 20, period: 20, octaves: 3, seed: seed &+ 15)
        }
        let height = blades.mapped { $0 * 0.6 }
            .combined(with: patches) { base, p in base + p * 0.3 }
            .normalized()

        let freshGrass = RGB(hex: 0x5C8442)
        let dryGrass = RGB(hex: 0x8A8B4A)
        let earth = RGB(hex: 0x4A3B28)

        var canvas = PixelCanvas(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                let patch = patches[x, y]
                let blade = blades[x, y]
                var color = freshGrass.lerp(dryGrass, Noise.smoothstep(0.45, 0.8, patch))
                // Per-blade tint: real turf is never one green.
                color = color.lerp(color.scaled(0.7).lerp(dryGrass, 0.4), bladeTint[x, y] * 0.6)
                // Thin patches show the soil through, and the gaps between blades sit in
                // their shadow — that contact shadow is what gives turf depth.
                color = color.lerp(earth, (1 - blade) * 0.5 * (1 - patch * 0.6))
                color = color.scaled(0.7 + blade * 0.48 + soil[x, y] * 0.08)
                canvas.set(x: x, y: y, color: color)
            }
        }
        return TextureSet(albedo: canvas.makeImage(),
                          normal: TextureMath.normalMap(from: height, strength: 2.2),
                          roughness: TextureMath.grayscale(height.mapped { 0.95 - $0 * 0.08 }),
                          occlusion: TextureMath.grayscale(
                            TextureMath.ambientOcclusion(from: height, radius: 3)))
    }

    // MARK: - Water, glass, fabric, flesh, plastic, tile

    private static func water(size: Int, seed: UInt32) -> TextureSet {
        // Two crossing wave trains plus a warp reads as moving water once it catches a
        // specular highlight, which is all a frozen river needs.
        let waves = ScalarField(width: size, height: size) { x, y in
            let (wx, wy) = Noise.warp(x * 6, y * 6, period: 6, strength: 0.5, seed: seed)
            let a = Noise.wave(wx, wy, period: 6, cyclesX: 18, cyclesY: 7)
            let b = Noise.wave(wx, wy, period: 6, cyclesX: 8, cyclesY: -16, phase: 1.3)
            return a * 0.6 + b * 0.4
        }
        let detail = ScalarField(width: size, height: size) { x, y in
            Noise.fbm(x * 40, y * 40, period: 40, octaves: 3, seed: seed &+ 3)
        }
        let height = waves.combined(with: detail) { w, d in w * 0.8 + d * 0.2 }.normalized()

        let deep = RGB(hex: 0x1E4458)
        let shallow = RGB(hex: 0x4F87A0)

        var canvas = PixelCanvas(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                canvas.set(x: x, y: y, color: deep.lerp(shallow, height[x, y]))
            }
        }
        return TextureSet(albedo: canvas.makeImage(),
                          normal: TextureMath.normalMap(from: height, strength: 1.6),
                          roughness: TextureMath.grayscale(height.mapped { _ in 0.06 }))
    }

    private static func glass(size: Int, seed: UInt32) -> TextureSet {
        let smudges = ScalarField(width: size, height: size) { x, y in
            let field = Noise.fbm(x * 7, y * 7, period: 7, octaves: 4, basis: .gradient, seed: seed)
            return Noise.smoothstep(0.55, 0.9, field)
        }
        let dust = ScalarField(width: size, height: size) { x, y in
            Noise.fbm(x * 90, y * 90, period: 90, octaves: 2, seed: seed &+ 5)
        }
        let height = smudges.mapped { $0 * 0.15 }.normalized()

        let tint = RGB(hex: 0xCDE4EC)
        var canvas = PixelCanvas(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                let color = tint.scaled(0.95 + dust[x, y] * 0.1)
                // Alpha carries the smudging so clean glass stays clear.
                canvas.set(x: x, y: y, color: color,
                           alpha: 0.18 + smudges[x, y] * 0.22)
            }
        }
        return TextureSet(albedo: canvas.makeImage(),
                          normal: TextureMath.normalMap(from: height, strength: 0.8),
                          roughness: TextureMath.grayscale(smudges.mapped { 0.04 + $0 * 0.25 }))
    }

    private static func fabric(size: Int, seed: UInt32) -> TextureSet {
        let weaveCount = 46
        // A real weave: warp and weft threads alternating over and under.
        let weave = ScalarField(width: size, height: size) { x, y in
            let fx = x * Float(weaveCount), fy = y * Float(weaveCount)
            let overUnder = (Int(floor(fx)) + Int(floor(fy))) % 2 == 0
            let warp = (sin(fx * .pi) + 1) * 0.5
            let weft = (sin(fy * .pi) + 1) * 0.5
            return overUnder ? warp : weft
        }
        let fuzz = ScalarField(width: size, height: size) { x, y in
            Noise.fbm(x * 130, y * 130, period: 130, octaves: 2, seed: seed)
        }
        let wear = ScalarField(width: size, height: size) { x, y in
            Noise.fbm(x * 5, y * 5, period: 5, octaves: 4, basis: .gradient, seed: seed &+ 11)
        }
        let height = weave.mapped { $0 * 0.5 }
            .combined(with: fuzz) { base, f in base + f * 0.15 }
            .normalized()

        let cloth = RGB(hex: 0x8A6552)
        let faded = RGB(hex: 0xA88A72)

        var canvas = PixelCanvas(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                let color = cloth.lerp(faded, wear[x, y] * 0.6)
                    .scaled(0.82 + weave[x, y] * 0.3 + fuzz[x, y] * 0.08)
                canvas.set(x: x, y: y, color: color)
            }
        }
        return TextureSet(albedo: canvas.makeImage(),
                          normal: TextureMath.normalMap(from: height, strength: 2.4),
                          roughness: TextureMath.grayscale(height.mapped { _ in 0.97 }),
                          occlusion: TextureMath.grayscale(
                            TextureMath.ambientOcclusion(from: height, radius: 2)))
    }

    private static func flesh(size: Int, seed: UInt32) -> TextureSet {
        let mottle = ScalarField(width: size, height: size) { x, y in
            Noise.fbm(x * 12, y * 12, period: 12, octaves: 4, basis: .gradient, seed: seed)
        }
        let pores = ScalarField(width: size, height: size) { x, y in
            let cell = Noise.cellular(x * 80, y * 80, period: 80, jitter: 1, seed: seed &+ 3)
            return 1 - Noise.smoothstep(0.0, 0.35, cell.nearest)
        }
        let height = pores.mapped { -$0 * 0.4 }
            .combined(with: mottle) { base, m in base + m * 0.3 }
            .normalized()

        let skin = RGB(hex: 0xA9685C)
        let flush = RGB(hex: 0x8C4038)
        var canvas = PixelCanvas(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                let color = skin.lerp(flush, mottle[x, y] * 0.7).scaled(0.9 + height[x, y] * 0.2)
                canvas.set(x: x, y: y, color: color)
            }
        }
        return TextureSet(albedo: canvas.makeImage(),
                          normal: TextureMath.normalMap(from: height, strength: 1.4),
                          roughness: TextureMath.grayscale(mottle.mapped { 0.6 + $0 * 0.2 }))
    }

    private static func plastic(size: Int, seed: UInt32) -> TextureSet {
        // Injection-moulded: a fine stipple finish with parting lines.
        let stipple = ScalarField(width: size, height: size) { x, y in
            let cell = Noise.cellular(x * 100, y * 100, period: 100, jitter: 1, seed: seed)
            return 1 - Noise.smoothstep(0.0, 0.45, cell.nearest)
        }
        let partingLines = ScalarField(width: size, height: size) { x, _ in
            1 - Noise.smoothstep(0.0, 0.006, abs(x - 0.5))
        }
        let scuffs = ScalarField(width: size, height: size) { x, y in
            let ridge = Noise.ridged(x * 18, y * 4, period: 18, octaves: 2, seed: seed &+ 7)
            return Noise.smoothstep(0.9, 1.0, ridge)
        }
        let height = stipple.mapped { $0 * 0.25 }
            .combined(with: partingLines) { base, p in base + p * 0.4 }
            .normalized()

        let body = RGB(hex: 0x8F979E)
        var canvas = PixelCanvas(width: size, height: size)
        var roughnessField = ScalarField(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                let color = body.scaled(0.9 + stipple[x, y] * 0.16)
                    .lerp(RGB(hex: 0xC9CFD4), scuffs[x, y] * 0.5)
                canvas.set(x: x, y: y, color: color)
                roughnessField[x, y] = MathUtil.clamp(0.45 + stipple[x, y] * 0.25
                                                      - scuffs[x, y] * 0.2, 0, 1)
            }
        }
        return TextureSet(albedo: canvas.makeImage(),
                          normal: TextureMath.normalMap(from: height, strength: 1.6),
                          roughness: TextureMath.grayscale(roughnessField))
    }

    private static func tile(size: Int, seed: UInt32) -> TextureSet {
        let tiles = 6
        let grout = ScalarField(width: size, height: size) { x, y in
            1 - Noise.smoothstep(0.012, 0.03, Noise.gridDistance(x, y, cells: tiles))
        }
        // A slight dome per tile catches the light the way glazed ceramic does.
        let bevel = ScalarField(width: size, height: size) { x, y in
            let edge = Noise.gridDistance(x, y, cells: tiles)
            return Noise.smoothstep(0.0, 0.08, edge)
        }
        let speckle = ScalarField(width: size, height: size) { x, y in
            Noise.fbm(x * 70, y * 70, period: 70, octaves: 3, seed: seed)
        }
        let height = bevel.combined(with: grout) { b, g in b - g * 1.1 }.normalized()

        let ceramic = RGB(hex: 0xC2C8CE)
        let groutColor = RGB(hex: 0x6C6F73)

        var canvas = PixelCanvas(width: size, height: size)
        var roughnessField = ScalarField(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                let nx = Float(x) / Float(size), ny = Float(y) / Float(size)
                let (cellX, cellY) = Noise.gridCell(nx, ny, cells: tiles)
                // Per-tile tint, so a floor never looks like one stretched texture.
                let tint = Noise.hash(cellX, cellY, seed &+ 31) * 0.14 - 0.07
                var color = ceramic.scaled(1 + tint).scaled(0.95 + speckle[x, y] * 0.1)
                color = color.lerp(groutColor, grout[x, y])
                canvas.set(x: x, y: y, color: color)
                roughnessField[x, y] = MathUtil.clamp(0.22 + grout[x, y] * 0.7, 0, 1)
            }
        }
        return TextureSet(albedo: canvas.makeImage(),
                          normal: TextureMath.normalMap(from: height, strength: 3.2),
                          roughness: TextureMath.grayscale(roughnessField),
                          occlusion: TextureMath.grayscale(
                            TextureMath.ambientOcclusion(from: height, radius: 3)))
    }
}
