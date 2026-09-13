import Foundation
import CoreGraphics
import UIKit
import CriticalStrikeCore

/// A single-channel floating-point image. Every procedural texture starts life as one of
/// these — a height field — and the albedo, normal, roughness and ambient-occlusion maps
/// are all derived from it. Deriving them from a shared height field rather than
/// generating each independently is what makes the maps agree with each other, which is
/// the difference between a surface that reads as one material and one that reads as
/// noise with a normal map stuck on top.
struct ScalarField {
    let width: Int
    let height: Int
    var values: [Float]

    init(width: Int, height: Int, repeating value: Float = 0) {
        self.width = width
        self.height = height
        self.values = [Float](repeating: value, count: width * height)
    }

    /// Builds a field by evaluating a generator over normalized [0,1) coordinates.
    init(width: Int, height: Int, generator: (Float, Float) -> Float) {
        self.width = width
        self.height = height
        self.values = [Float](repeating: 0, count: width * height)
        let inverseWidth = 1 / Float(width)
        let inverseHeight = 1 / Float(height)
        for y in 0..<height {
            let v = Float(y) * inverseHeight
            for x in 0..<width {
                values[y * width + x] = generator(Float(x) * inverseWidth, v)
            }
        }
    }

    @inline(__always)
    subscript(x: Int, y: Int) -> Float {
        get {
            // Wrapped sampling keeps every derived map seamless at the tile edges.
            let wx = ((x % width) + width) % width
            let wy = ((y % height) + height) % height
            return values[wy * width + wx]
        }
        set {
            let wx = ((x % width) + width) % width
            let wy = ((y % height) + height) % height
            values[wy * width + wx] = newValue
        }
    }

    var range: (min: Float, max: Float) {
        var lo = Float.greatestFiniteMagnitude
        var hi = -Float.greatestFiniteMagnitude
        for value in values {
            lo = Swift.min(lo, value)
            hi = Swift.max(hi, value)
        }
        return (lo, hi)
    }

    /// Rescales to [0,1]. Procedural fields rarely use their full range, and normalizing
    /// before deriving normals keeps the bump strength predictable across surfaces.
    func normalized() -> ScalarField {
        let (lo, hi) = range
        guard hi - lo > 1e-6 else { return self }
        var out = self
        let scale = 1 / (hi - lo)
        for index in out.values.indices {
            out.values[index] = (out.values[index] - lo) * scale
        }
        return out
    }

    func mapped(_ transform: (Float) -> Float) -> ScalarField {
        var out = self
        for index in out.values.indices {
            out.values[index] = transform(out.values[index])
        }
        return out
    }

    func combined(with other: ScalarField, _ transform: (Float, Float) -> Float) -> ScalarField {
        var out = self
        for index in out.values.indices {
            out.values[index] = transform(out.values[index], other.values[index])
        }
        return out
    }

    /// Separable box blur with wrapping, used to soften masks and build cheap AO.
    func blurred(radius: Int) -> ScalarField {
        guard radius > 0 else { return self }
        var horizontal = self
        let window = Float(radius * 2 + 1)
        for y in 0..<height {
            for x in 0..<width {
                var sum: Float = 0
                for offset in -radius...radius { sum += self[x + offset, y] }
                horizontal.values[y * width + x] = sum / window
            }
        }
        var out = horizontal
        for y in 0..<height {
            for x in 0..<width {
                var sum: Float = 0
                for offset in -radius...radius { sum += horizontal[x, y + offset] }
                out.values[y * width + x] = sum / window
            }
        }
        return out
    }
}

/// An RGBA8 image under construction. Writing bytes directly is roughly two orders of
/// magnitude faster than drawing a rectangle per pixel with Core Graphics, which matters
/// when a match needs a few dozen 512² textures during the loading screen.
struct PixelCanvas {
    let width: Int
    let height: Int
    private(set) var pixels: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.pixels = [UInt8](repeating: 255, count: width * height * 4)
    }

    @inline(__always)
    mutating func set(x: Int, y: Int, r: Float, g: Float, b: Float, a: Float = 1) {
        let index = (y * width + x) * 4
        // Straight (non-premultiplied) bytes; the CGImage below is tagged to match.
        pixels[index] = UInt8(MathUtil.clamp(r, 0, 1) * 255)
        pixels[index + 1] = UInt8(MathUtil.clamp(g, 0, 1) * 255)
        pixels[index + 2] = UInt8(MathUtil.clamp(b, 0, 1) * 255)
        pixels[index + 3] = UInt8(MathUtil.clamp(a, 0, 1) * 255)
    }

    @inline(__always)
    mutating func set(x: Int, y: Int, color: RGB, alpha: Float = 1) {
        set(x: x, y: y, r: color.r, g: color.g, b: color.b, a: alpha)
    }

    func makeImage() -> UIImage? {
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        let bytesPerRow = width * 4
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8,
                                    bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: true,
                                    intent: .defaultIntent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

/// Linear RGB triple. Texture synthesis mixes colours constantly and `UIColor` round trips
/// are far too slow to do per pixel.
struct RGB {
    var r: Float
    var g: Float
    var b: Float

    init(_ r: Float, _ g: Float, _ b: Float) {
        self.r = r; self.g = g; self.b = b
    }

    init(hex: UInt32) {
        r = Float((hex >> 16) & 0xFF) / 255
        g = Float((hex >> 8) & 0xFF) / 255
        b = Float(hex & 0xFF) / 255
    }

    static func + (a: RGB, b: RGB) -> RGB { RGB(a.r + b.r, a.g + b.g, a.b + b.b) }
    static func * (a: RGB, s: Float) -> RGB { RGB(a.r * s, a.g * s, a.b * s) }
    static func * (a: RGB, b: RGB) -> RGB { RGB(a.r * b.r, a.g * b.g, a.b * b.b) }

    func lerp(_ other: RGB, _ t: Float) -> RGB {
        let clamped = MathUtil.clamp(t, 0, 1)
        return RGB(r + (other.r - r) * clamped,
                   g + (other.g - g) * clamped,
                   b + (other.b - b) * clamped)
    }

    /// Multiplies brightness while keeping hue — used to shade albedo by the height field.
    func scaled(_ factor: Float) -> RGB { RGB(r * factor, g * factor, b * factor) }

    var uiColor: UIColor {
        UIColor(red: CGFloat(MathUtil.clamp(r, 0, 1)),
                green: CGFloat(MathUtil.clamp(g, 0, 1)),
                blue: CGFloat(MathUtil.clamp(b, 0, 1)), alpha: 1)
    }

    static let white = RGB(1, 1, 1)
    static let black = RGB(0, 0, 0)
}

enum TextureMath {
    /// Tangent-space normal map from a height field, by central differences with wrapping.
    /// This is the correct way to get a normal map: deriving it from the same height field
    /// the albedo was shaded with means the lighting and the visible detail always agree.
    static func normalMap(from height: ScalarField, strength: Float) -> UIImage? {
        var canvas = PixelCanvas(width: height.width, height: height.height)
        // Sobel gives a smoother gradient than a two-tap difference and costs little.
        for y in 0..<height.height {
            for x in 0..<height.width {
                let tl = height[x - 1, y - 1], t = height[x, y - 1], tr = height[x + 1, y - 1]
                let l = height[x - 1, y], r = height[x + 1, y]
                let bl = height[x - 1, y + 1], b = height[x, y + 1], br = height[x + 1, y + 1]

                let dx = (tr + 2 * r + br) - (tl + 2 * l + bl)
                let dy = (bl + 2 * b + br) - (tl + 2 * t + tr)

                var nx = -dx * strength
                var ny = -dy * strength
                var nz: Float = 1
                let length = (nx * nx + ny * ny + nz * nz).squareRoot()
                nx /= length; ny /= length; nz /= length

                canvas.set(x: x, y: y,
                           r: nx * 0.5 + 0.5, g: ny * 0.5 + 0.5, b: nz * 0.5 + 0.5)
            }
        }
        return canvas.makeImage()
    }

    /// Grayscale image from a field, for roughness, metalness and occlusion maps.
    static func grayscale(_ field: ScalarField) -> UIImage? {
        var canvas = PixelCanvas(width: field.width, height: field.height)
        for y in 0..<field.height {
            for x in 0..<field.width {
                let value = field[x, y]
                canvas.set(x: x, y: y, r: value, g: value, b: value)
            }
        }
        return canvas.makeImage()
    }

    /// Cheap ambient occlusion: a point is occluded in proportion to how much the
    /// neighbourhood rises above it. Crevices darken, peaks stay lit.
    static func ambientOcclusion(from height: ScalarField, radius: Int = 4,
                                 strength: Float = 1) -> ScalarField {
        let blurred = height.blurred(radius: radius)
        return height.combined(with: blurred) { local, neighbourhood in
            let difference = local - neighbourhood
            // Below the local average ⇒ in a hollow ⇒ occluded.
            return MathUtil.clamp(1 + difference * 4 * strength, 0, 1)
        }
    }

    /// Curvature, which is what drives edge wear: convex edges lose paint and go shiny.
    static func curvature(from height: ScalarField, radius: Int = 2) -> ScalarField {
        let blurred = height.blurred(radius: radius)
        return height.combined(with: blurred) { local, neighbourhood in
            MathUtil.clamp((local - neighbourhood) * 6 + 0.5, 0, 1)
        }
    }
}
