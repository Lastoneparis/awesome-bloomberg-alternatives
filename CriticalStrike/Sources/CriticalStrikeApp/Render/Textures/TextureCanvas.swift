import Foundation
import CoreGraphics
import UIKit
import CriticalStrikeCore

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

extension RGB {
    /// Bridge to UIKit, kept out of the core so the field maths stays platform-free.
    var uiColor: UIColor {
        UIColor(red: CGFloat(MathUtil.clamp(r, 0, 1)),
                green: CGFloat(MathUtil.clamp(g, 0, 1)),
                blue: CGFloat(MathUtil.clamp(b, 0, 1)), alpha: 1)
    }
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

    /// Occlusion and curvature live on `ScalarField` in the core, where they can be
    /// tested; these forward for call-site readability.
    static func ambientOcclusion(from height: ScalarField, radius: Int = 4,
                                 strength: Float = 1) -> ScalarField {
        height.ambientOcclusion(radius: radius, strength: strength)
    }

    static func curvature(from height: ScalarField, radius: Int = 2) -> ScalarField {
        height.curvature(radius: radius)
    }
}
