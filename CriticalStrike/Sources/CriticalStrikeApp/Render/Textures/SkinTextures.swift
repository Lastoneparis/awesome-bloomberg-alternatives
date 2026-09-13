import Foundation
import UIKit
import CriticalStrikeCore

/// Weapon and operator finishes.
///
/// A skin is a pattern plus a palette. Keeping the patterns procedural means a new
/// legendary is a palette and a pattern name rather than an artist-week, and because every
/// pattern is driven by the same tileable noise as the world surfaces, skins sit in the
/// same visual language as the maps.
enum SkinPattern: String, CaseIterable {
    case gunmetal       // the default: machined steel with a hex micro-texture
    case urbanCamo      // hard-edged blotches
    case digitalCamo    // pixel blocks
    case hydra          // organic warped bands
    case fade           // hue gradient along the barrel
    case gilded         // polished gold with engraving
    case neon           // dark body with glowing circuit lines
    case dragonScale    // overlapping scales
    case arcticSplinter // angular splinter camo
    case phantomGlass   // translucent, iridescent

    /// Maps a cosmetic to a pattern. New skins pick a pattern by name convention, and fall
    /// back to something appropriate for their rarity.
    static func pattern(for cosmetic: CosmeticData?) -> SkinPattern {
        guard let cosmetic else { return .gunmetal }
        let id = cosmetic.id.value
        if id.contains("urban") { return .urbanCamo }
        if id.contains("crimson") { return .digitalCamo }
        if id.contains("hydra") { return .hydra }
        if id.contains("fade") { return .fade }
        if id.contains("gold") || id.contains("gilded") { return .gilded }
        if id.contains("neon") { return .neon }
        if id.contains("dragon") { return .dragonScale }
        if id.contains("arctic") { return .arcticSplinter }
        if id.contains("phantom") { return .phantomGlass }
        switch cosmetic.rarity {
        case .common, .uncommon: return .urbanCamo
        case .rare: return .digitalCamo
        case .epic: return .hydra
        case .legendary: return .gilded
        case .mythic: return .dragonScale
        }
    }

    var isEmissive: Bool { self == .neon || self == .dragonScale }
    var isMetal: Bool {
        switch self {
        case .gunmetal, .gilded, .fade, .phantomGlass: return true
        default: return false
        }
    }
}

enum SkinTextureFactory {

    static func resolution(for quality: GraphicsQuality) -> Int {
        switch quality {
        case .low: return 256
        case .medium: return 384
        case .high, .ultra: return 512
        }
    }

    static func make(pattern: SkinPattern, tint: RGB, size: Int, seed: UInt32 = 0x5C1) -> TextureSet {
        switch pattern {
        case .gunmetal: return gunmetal(tint: tint, size: size, seed: seed)
        case .urbanCamo: return blotchCamo(tint: tint, size: size, seed: seed, hardEdged: true)
        case .digitalCamo: return digitalCamo(tint: tint, size: size, seed: seed)
        case .hydra: return hydra(tint: tint, size: size, seed: seed)
        case .fade: return fade(tint: tint, size: size, seed: seed)
        case .gilded: return gilded(tint: tint, size: size, seed: seed)
        case .neon: return neon(tint: tint, size: size, seed: seed)
        case .dragonScale: return dragonScale(tint: tint, size: size, seed: seed)
        case .arcticSplinter: return blotchCamo(tint: tint, size: size, seed: seed, hardEdged: false)
        case .phantomGlass: return phantomGlass(tint: tint, size: size, seed: seed)
        }
    }

    // MARK: - Patterns

    private static func gunmetal(tint: RGB, size: Int, seed: UInt32) -> TextureSet {
        // Hex micro-texture is what makes a weapon read as modern at viewmodel distance.
        let hex = ScalarField(width: size, height: size) { x, y in
            let cell = Noise.cellular(x * 34, y * 34, period: 34, jitter: 0.0, seed: seed)
            return Noise.smoothstep(0.02, 0.09, cell.borderDistance)
        }
        let machining = ScalarField(width: size, height: size) { x, y in
            Noise.fbm(x * 4, y * 140, period: 140, octaves: 2, seed: seed &+ 3)
        }
        let wear = ScalarField(width: size, height: size) { x, y in
            let ridge = Noise.ridged(x * 16, y * 6, period: 16, octaves: 3, seed: seed &+ 7)
            return Noise.smoothstep(0.86, 1.0, ridge)
        }
        let height = hex.mapped { $0 * 0.35 }
            .combined(with: machining) { base, m in base + m * 0.12 }
            .normalized()

        var canvas = PixelCanvas(width: size, height: size)
        var roughnessField = ScalarField(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                var color = tint.scaled(0.8 + hex[x, y] * 0.35 + machining[x, y] * 0.12)
                color = color.lerp(RGB(hex: 0xD5DAE0), wear[x, y] * 0.8)
                canvas.set(x: x, y: y, color: color)
                roughnessField[x, y] = MathUtil.clamp(0.42 - wear[x, y] * 0.25
                                                      + (1 - hex[x, y]) * 0.12, 0.05, 1)
            }
        }
        return TextureSet(albedo: canvas.makeImage(),
                          normal: TextureMath.normalMap(from: height, strength: 2.2),
                          roughness: TextureMath.grayscale(roughnessField),
                          metalness: TextureMath.grayscale(
                            ScalarField(width: size, height: size, repeating: 0.9)))
    }

    private static func blotchCamo(tint: RGB, size: Int, seed: UInt32, hardEdged: Bool) -> TextureSet {
        let base = ScalarField(width: size, height: size) { x, y in
            let (wx, wy) = Noise.warp(x * 5, y * 5, period: 5, strength: 1.1, seed: seed)
            return Noise.fbm(wx, wy, period: 5, octaves: 4, basis: .gradient, seed: seed &+ 3)
        }
        let secondary = ScalarField(width: size, height: size) { x, y in
            Noise.fbm(x * 9, y * 9, period: 9, octaves: 3, basis: .gradient, seed: seed &+ 5)
        }
        let grain = ScalarField(width: size, height: size) { x, y in
            Noise.fbm(x * 110, y * 110, period: 110, octaves: 2, seed: seed &+ 7)
        }

        // Three tones sampled around the skin's tint keeps every camo on-brand.
        let dark = tint.scaled(0.45)
        let mid = tint
        let light = tint.lerp(.white, 0.35)
        let edge: Float = hardEdged ? 0.02 : 0.12

        var canvas = PixelCanvas(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                let a = Noise.smoothstep(0.46 - edge, 0.46 + edge, base[x, y])
                let b = Noise.smoothstep(0.58 - edge, 0.58 + edge, secondary[x, y])
                var color = dark.lerp(mid, a)
                color = color.lerp(light, b * 0.7)
                color = color.scaled(0.94 + grain[x, y] * 0.12)
                canvas.set(x: x, y: y, color: color)
            }
        }
        let height = grain.mapped { $0 * 0.2 }.normalized()
        return TextureSet(albedo: canvas.makeImage(),
                          normal: TextureMath.normalMap(from: height, strength: 0.9),
                          roughness: TextureMath.grayscale(base.mapped { 0.55 + $0 * 0.2 }))
    }

    private static func digitalCamo(tint: RGB, size: Int, seed: UInt32) -> TextureSet {
        let blocks = 22
        var canvas = PixelCanvas(width: size, height: size)
        let dark = tint.scaled(0.4)
        let mid = tint
        let light = tint.lerp(.white, 0.4)

        for y in 0..<size {
            for x in 0..<size {
                let nx = Float(x) / Float(size), ny = Float(y) / Float(size)
                let (cellX, cellY) = Noise.gridCell(nx, ny, cells: blocks)
                // Two scales of blocks so it does not read as a single checkerboard.
                let coarse = Noise.hash(cellX / 2, cellY / 2, seed)
                let fine = Noise.hash(cellX, cellY, seed &+ 11)
                var color = dark
                if coarse > 0.45 { color = mid }
                if fine > 0.78 { color = light }
                if fine < 0.12 { color = dark.scaled(0.7) }
                canvas.set(x: x, y: y, color: color)
            }
        }
        let height = ScalarField(width: size, height: size) { x, y in
            Noise.fbm(x * 120, y * 120, period: 120, octaves: 2, seed: seed &+ 3) * 0.2
        }
        return TextureSet(albedo: canvas.makeImage(),
                          normal: TextureMath.normalMap(from: height, strength: 0.8),
                          roughness: TextureMath.grayscale(
                            ScalarField(width: size, height: size, repeating: 0.6)))
    }

    private static func hydra(tint: RGB, size: Int, seed: UInt32) -> TextureSet {
        // Heavily warped bands — the classic "liquid" high-tier finish.
        let bands = ScalarField(width: size, height: size) { x, y in
            var (wx, wy) = Noise.warp(x * 3, y * 3, period: 3, strength: 2.2, seed: seed)
            (wx, wy) = Noise.warp(wx, wy, period: 3, strength: 1.1, seed: seed &+ 13)
            return (sin((wx * 1.6 + wy * 0.8) * .pi * 2) + 1) * 0.5
        }
        let filigree = ScalarField(width: size, height: size) { x, y in
            let (wx, wy) = Noise.warp(x * 8, y * 8, period: 8, strength: 1.6, seed: seed &+ 17)
            let ridge = Noise.ridged(wx, wy, period: 8, octaves: 3, seed: seed &+ 19)
            return Noise.smoothstep(0.75, 0.95, ridge)
        }
        let height = bands.mapped { $0 * 0.3 }
            .combined(with: filigree) { base, f in base + f * 0.4 }
            .normalized()

        let deep = tint.scaled(0.3)
        let bright = tint.lerp(.white, 0.55)
        var canvas = PixelCanvas(width: size, height: size)
        var emissionCanvas = PixelCanvas(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                let color = deep.lerp(bright, bands[x, y]).lerp(.white, filigree[x, y] * 0.5)
                canvas.set(x: x, y: y, color: color)
                emissionCanvas.set(x: x, y: y, color: tint.scaled(filigree[x, y] * 0.6))
            }
        }
        return TextureSet(albedo: canvas.makeImage(),
                          normal: TextureMath.normalMap(from: height, strength: 1.8),
                          roughness: TextureMath.grayscale(bands.mapped { 0.25 + $0 * 0.3 }),
                          metalness: TextureMath.grayscale(
                            ScalarField(width: size, height: size, repeating: 0.6)),
                          emission: emissionCanvas.makeImage())
    }

    private static func fade(tint: RGB, size: Int, seed: UInt32) -> TextureSet {
        // A hue sweep along the length of the weapon, with a polished finish.
        let polish = ScalarField(width: size, height: size) { x, y in
            Noise.fbm(x * 3, y * 90, period: 90, octaves: 2, seed: seed)
        }
        var canvas = PixelCanvas(width: size, height: size)
        let start = tint
        let middle = RGB(hex: 0xFF6FD8)
        let end = RGB(hex: 0x6FC5FF)
        for y in 0..<size {
            for x in 0..<size {
                let t = Float(x) / Float(size)
                let color = t < 0.5 ? start.lerp(middle, t * 2) : middle.lerp(end, (t - 0.5) * 2)
                canvas.set(x: x, y: y, color: color.scaled(0.9 + polish[x, y] * 0.2))
            }
        }
        return TextureSet(albedo: canvas.makeImage(),
                          normal: TextureMath.normalMap(from: polish.normalized(), strength: 0.6),
                          roughness: TextureMath.grayscale(
                            ScalarField(width: size, height: size, repeating: 0.12)),
                          metalness: TextureMath.grayscale(
                            ScalarField(width: size, height: size, repeating: 1.0)))
    }

    private static func gilded(tint: RGB, size: Int, seed: UInt32) -> TextureSet {
        // Engraved scrollwork cut into polished gold.
        let engraving = ScalarField(width: size, height: size) { x, y in
            let (wx, wy) = Noise.warp(x * 7, y * 7, period: 7, strength: 1.8, seed: seed)
            let ridge = Noise.ridged(wx, wy, period: 7, octaves: 4, seed: seed &+ 3)
            return Noise.smoothstep(0.82, 0.96, ridge)
        }
        let polish = ScalarField(width: size, height: size) { x, y in
            Noise.fbm(x * 6, y * 60, period: 60, octaves: 2, seed: seed &+ 5)
        }
        let height = engraving.mapped { -$0 * 0.8 }
            .combined(with: polish) { base, p in base + p * 0.08 }
            .normalized()

        let gold = tint
        let shadow = tint.scaled(0.35)
        var canvas = PixelCanvas(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                let color = gold.scaled(0.86 + polish[x, y] * 0.28).lerp(shadow, engraving[x, y])
                canvas.set(x: x, y: y, color: color)
            }
        }
        return TextureSet(albedo: canvas.makeImage(),
                          normal: TextureMath.normalMap(from: height, strength: 3.0),
                          roughness: TextureMath.grayscale(engraving.mapped { 0.14 + $0 * 0.4 }),
                          occlusion: TextureMath.grayscale(
                            TextureMath.ambientOcclusion(from: height, radius: 2)),
                          metalness: TextureMath.grayscale(
                            ScalarField(width: size, height: size, repeating: 1.0)))
    }

    private static func neon(tint: RGB, size: Int, seed: UInt32) -> TextureSet {
        // Circuit traces: grid-snapped paths that light up.
        let traces = ScalarField(width: size, height: size) { x, y in
            let cells = 16
            let fx = x * Float(cells), fy = y * Float(cells)
            let (cellX, cellY) = (Int(floor(fx)), Int(floor(fy)))
            let choice = Noise.hash(cellX, cellY, seed)
            let localX = fx - floor(fx), localY = fy - floor(fy)
            let lineWidth: Float = 0.09
            // Each cell carries a horizontal or vertical trace, sometimes both.
            var value: Float = 0
            if choice > 0.35 {
                value = Swift.max(value, 1 - Noise.smoothstep(0, lineWidth, abs(localY - 0.5)))
            }
            if choice < 0.65 {
                value = Swift.max(value, 1 - Noise.smoothstep(0, lineWidth, abs(localX - 0.5)))
            }
            return value
        }
        let panels = ScalarField(width: size, height: size) { x, y in
            1 - Noise.smoothstep(0.0, 0.02, Noise.gridDistance(x, y, cells: 4))
        }
        let height = traces.mapped { $0 * 0.4 }
            .combined(with: panels) { base, p in base - p * 0.6 }
            .normalized()

        let body = RGB(hex: 0x14161C)
        var canvas = PixelCanvas(width: size, height: size)
        var emissionCanvas = PixelCanvas(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                let glow = traces[x, y]
                let color = body.lerp(tint, glow).lerp(RGB(hex: 0x05060A), panels[x, y] * 0.8)
                canvas.set(x: x, y: y, color: color)
                emissionCanvas.set(x: x, y: y, color: tint.scaled(glow))
            }
        }
        return TextureSet(albedo: canvas.makeImage(),
                          normal: TextureMath.normalMap(from: height, strength: 2.4),
                          roughness: TextureMath.grayscale(traces.mapped { 0.6 - $0 * 0.35 }),
                          emission: emissionCanvas.makeImage())
    }

    private static func dragonScale(tint: RGB, size: Int, seed: UInt32) -> TextureSet {
        // Offset rows of overlapping scales, each with its own height dome.
        let scaleRows = 18
        let height = ScalarField(width: size, height: size) { x, y in
            let fy = y * Float(scaleRows)
            let row = Int(floor(fy))
            let offset = row % 2 == 0 ? Float(0) : 0.5
            let fx = x * Float(scaleRows) + offset
            let localX = fx - floor(fx) - 0.5
            let localY = fy - floor(fy)
            // Teardrop: wide at the top, tapering down.
            let width = 0.5 * (1 - localY * 0.5)
            let inside = 1 - Noise.smoothstep(width * 0.6, width, abs(localX))
            let dome = inside * (1 - localY * 0.7)
            return dome
        }.normalized()

        let veins = ScalarField(width: size, height: size) { x, y in
            let ridge = Noise.ridged(x * 20, y * 20, period: 20, octaves: 2, seed: seed)
            return Noise.smoothstep(0.8, 1.0, ridge)
        }

        let deep = tint.scaled(0.35)
        let bright = tint.lerp(RGB(hex: 0xFFD27F), 0.5)
        var canvas = PixelCanvas(width: size, height: size)
        var emissionCanvas = PixelCanvas(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                let h = height[x, y]
                let color = deep.lerp(bright, h).lerp(.white, veins[x, y] * 0.3)
                canvas.set(x: x, y: y, color: color)
                // The gaps between scales glow, as if there is fire underneath.
                emissionCanvas.set(x: x, y: y,
                                   color: RGB(hex: 0xFF6A1F).scaled((1 - h) * 0.5))
            }
        }
        return TextureSet(albedo: canvas.makeImage(),
                          normal: TextureMath.normalMap(from: height, strength: 3.4),
                          roughness: TextureMath.grayscale(height.mapped { 0.5 - $0 * 0.3 }),
                          occlusion: TextureMath.grayscale(
                            TextureMath.ambientOcclusion(from: height, radius: 3)),
                          metalness: TextureMath.grayscale(
                            ScalarField(width: size, height: size, repeating: 0.5)),
                          emission: emissionCanvas.makeImage())
    }

    private static func phantomGlass(tint: RGB, size: Int, seed: UInt32) -> TextureSet {
        let iridescence = ScalarField(width: size, height: size) { x, y in
            let (wx, wy) = Noise.warp(x * 4, y * 4, period: 4, strength: 1.4, seed: seed)
            return Noise.fbm(wx, wy, period: 4, octaves: 3, basis: .gradient, seed: seed &+ 3)
        }
        var canvas = PixelCanvas(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                let t = iridescence[x, y]
                // Sweep through the spectrum so the finish shifts with the viewing angle.
                let color = RGB(0.5 + 0.5 * sin(t * 6.2), 0.5 + 0.5 * sin(t * 6.2 + 2.1),
                                0.5 + 0.5 * sin(t * 6.2 + 4.2))
                    .lerp(tint, 0.35)
                canvas.set(x: x, y: y, color: color, alpha: 0.75)
            }
        }
        return TextureSet(albedo: canvas.makeImage(),
                          normal: TextureMath.normalMap(from: iridescence.normalized(), strength: 1.0),
                          roughness: TextureMath.grayscale(
                            ScalarField(width: size, height: size, repeating: 0.08)),
                          metalness: TextureMath.grayscale(
                            ScalarField(width: size, height: size, repeating: 0.8)))
    }
}
