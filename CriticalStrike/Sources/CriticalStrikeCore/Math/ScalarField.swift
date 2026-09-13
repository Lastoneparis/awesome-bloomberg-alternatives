import Foundation

/// A single-channel floating-point image — a height field.
///
/// Every procedural texture in the game starts life as one of these, and the albedo,
/// normal, roughness and ambient-occlusion maps are all derived from it. Deriving them
/// from a shared field rather than generating each independently is what makes the maps
/// agree with each other, which is the difference between a surface that reads as one
/// material and one that reads as noise with a normal map stuck on top.
///
/// It lives in the core, with no Core Graphics anywhere near it, so the sampling and
/// filtering can be tested.
public struct ScalarField {
    public let width: Int
    public let height: Int
    public var values: [Float]

    public init(width: Int, height: Int, repeating value: Float = 0) {
        self.width = width
        self.height = height
        self.values = [Float](repeating: value, count: width * height)
    }

    /// Builds a field by evaluating a generator over normalized [0,1) coordinates.
    public init(width: Int, height: Int, generator: (Float, Float) -> Float) {
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
    public subscript(x: Int, y: Int) -> Float {
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

    public var range: (min: Float, max: Float) {
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
    public func normalized() -> ScalarField {
        let (lo, hi) = range
        guard hi - lo > 1e-6 else { return self }
        var out = self
        let scale = 1 / (hi - lo)
        for index in out.values.indices {
            out.values[index] = (out.values[index] - lo) * scale
        }
        return out
    }

    public func mapped(_ transform: (Float) -> Float) -> ScalarField {
        var out = self
        for index in out.values.indices {
            out.values[index] = transform(out.values[index])
        }
        return out
    }

    public func combined(with other: ScalarField, _ transform: (Float, Float) -> Float) -> ScalarField {
        var out = self
        for index in out.values.indices {
            out.values[index] = transform(out.values[index], other.values[index])
        }
        return out
    }

    /// Separable box blur with wrapping, used to soften masks and build cheap AO.
    public func blurred(radius: Int) -> ScalarField {
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

public extension ScalarField {
    /// Cheap ambient occlusion: a point is occluded in proportion to how much the
    /// neighbourhood rises above it. Crevices darken, peaks stay lit.
    func ambientOcclusion(radius: Int = 4, strength: Float = 1) -> ScalarField {
        let neighbourhood = blurred(radius: radius)
        return combined(with: neighbourhood) { local, average in
            MathUtil.clamp(1 + (local - average) * 4 * strength, 0, 1)
        }
    }

    /// Curvature, which is what drives edge wear: convex edges lose paint and go shiny.
    func curvature(radius: Int = 2) -> ScalarField {
        let neighbourhood = blurred(radius: radius)
        return combined(with: neighbourhood) { local, average in
            MathUtil.clamp((local - average) * 6 + 0.5, 0, 1)
        }
    }
}

/// Linear RGB triple. Texture synthesis mixes colours constantly and `UIColor` round trips
/// are far too slow to do per pixel.
public struct RGB {
    public var r: Float
    public var g: Float
    public var b: Float

    public init(_ r: Float, _ g: Float, _ b: Float) {
        self.r = r; self.g = g; self.b = b
    }

    public init(hex: UInt32) {
        r = Float((hex >> 16) & 0xFF) / 255
        g = Float((hex >> 8) & 0xFF) / 255
        b = Float(hex & 0xFF) / 255
    }

    public static func + (a: RGB, b: RGB) -> RGB { RGB(a.r + b.r, a.g + b.g, a.b + b.b) }
    public static func * (a: RGB, s: Float) -> RGB { RGB(a.r * s, a.g * s, a.b * s) }
    public static func * (a: RGB, b: RGB) -> RGB { RGB(a.r * b.r, a.g * b.g, a.b * b.b) }

    public func lerp(_ other: RGB, _ t: Float) -> RGB {
        let clamped = MathUtil.clamp(t, 0, 1)
        return RGB(r + (other.r - r) * clamped,
                   g + (other.g - g) * clamped,
                   b + (other.b - b) * clamped)
    }

    /// Multiplies brightness while keeping hue — used to shade albedo by the height field.
    public func scaled(_ factor: Float) -> RGB { RGB(r * factor, g * factor, b * factor) }

    public static let white = RGB(1, 1, 1)
    public static let black = RGB(0, 0, 0)
}
