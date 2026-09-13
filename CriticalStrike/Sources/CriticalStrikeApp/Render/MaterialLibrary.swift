import Foundation
import SceneKit
import UIKit
import CriticalStrikeCore

/// Materials for every surface type.
///
/// The game ships without bitmap texture assets: every material is generated once at load
/// time into a small tiling image with Core Graphics. That keeps the app download tiny,
/// guarantees the art style is consistent, and means a new surface type is a few lines of
/// code rather than a texturing job. Materials are cached and shared, so the whole level
/// draws from a handful of SCNMaterial instances.
final class MaterialLibrary {
    private var cache: [String: SCNMaterial] = [:]
    private var textureCache: [String: UIImage] = [:]
    private let quality: GraphicsQuality

    init(quality: GraphicsQuality) {
        self.quality = quality
    }

    // MARK: - Public API

    func material(for surface: SurfaceKind, tintOverride: UIColor? = nil) -> SCNMaterial {
        let key = "surface_\(surface.rawValue)_\(tintOverride?.description ?? "-")"
        if let cached = cache[key] { return cached }

        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        let spec = MaterialLibrary.spec(for: surface)
        let baseColor = tintOverride ?? spec.color

        material.diffuse.contents = texture(named: key, size: textureSize,
                                            generator: { context, size in
            MaterialLibrary.drawSurface(surface, color: baseColor, in: context, size: size)
        })
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.roughness.contents = NSNumber(value: spec.roughness)
        material.metalness.contents = NSNumber(value: spec.metalness)
        material.isDoubleSided = false

        if surface == .glass {
            material.transparency = 0.28
            material.transparencyMode = .dualLayer
            material.blendMode = .alpha
            material.writesToDepthBuffer = false
        }
        if surface == .water {
            material.transparency = 0.55
            material.roughness.contents = NSNumber(value: 0.08)
        }
        // Normal detail only where it will actually be seen.
        if quality != .low {
            material.normal.contents = texture(named: key + "_n", size: textureSize) { context, size in
                MaterialLibrary.drawNormalNoise(in: context, size: size, strength: spec.normalStrength)
            }
            material.normal.wrapS = .repeat
            material.normal.wrapT = .repeat
            material.normal.intensity = 0.7
        }
        cache[key] = material
        return material
    }

    /// Team-tinted material for character models.
    func characterMaterial(team: Team, colorBlind: ColorBlindMode, accent: Bool = false) -> SCNMaterial {
        let key = "char_\(team.rawValue)_\(colorBlind.rawValue)_\(accent)"
        if let cached = cache[key] { return cached }
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        let hex = colorBlind.teamColor(team)
        let base = UIColor(hex: hex)
        material.diffuse.contents = accent ? base : base.darkened(by: 0.55)
        material.roughness.contents = NSNumber(value: 0.65)
        material.metalness.contents = NSNumber(value: 0.1)
        material.emission.contents = accent ? base.withAlphaComponent(0.35) : UIColor.black
        cache[key] = material
        return material
    }

    /// Weapon material, optionally tinted by an equipped skin.
    func weaponMaterial(skin: CosmeticData?) -> SCNMaterial {
        let key = "weapon_\(skin?.id.value ?? "default")"
        if let cached = cache[key] { return cached }
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        let tint = skin.map { UIColor(hex: $0.tintHex) } ?? UIColor(white: 0.18, alpha: 1)
        material.diffuse.contents = texture(named: key, size: textureSize) { context, size in
            MaterialLibrary.drawGunmetal(color: tint, in: context, size: size)
        }
        material.roughness.contents = NSNumber(value: skin?.rarity == .legendary ? 0.25 : 0.45)
        material.metalness.contents = NSNumber(value: 0.85)
        if skin?.hasAnimatedShader == true {
            material.emission.contents = tint.withAlphaComponent(0.3)
        }
        cache[key] = material
        return material
    }

    func emissiveMaterial(color: UIColor, intensity: CGFloat = 1) -> SCNMaterial {
        let key = "emissive_\(color.description)_\(intensity)"
        if let cached = cache[key] { return cached }
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color
        material.emission.contents = color.withAlphaComponent(min(1, intensity))
        material.writesToDepthBuffer = false
        material.blendMode = .add
        cache[key] = material
        return material
    }

    func decalMaterial(surface: SurfaceKind) -> SCNMaterial {
        let key = "decal_\(surface.rawValue)"
        if let cached = cache[key] { return cached }
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = texture(named: key, size: 64) { context, size in
            MaterialLibrary.drawBulletHole(in: context, size: size)
        }
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        cache[key] = material
        return material
    }

    // MARK: - Texture generation

    private var textureSize: CGFloat {
        switch quality {
        case .low: return 128
        case .medium: return 256
        case .high, .ultra: return 512
        }
    }

    private func texture(named key: String, size: CGFloat,
                         generator: (CGContext, CGFloat) -> Void) -> UIImage {
        if let cached = textureCache[key] { return cached }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { ctx in
            generator(ctx.cgContext, size)
        }
        textureCache[key] = image
        return image
    }

    private struct SurfaceSpec {
        var color: UIColor
        var roughness: Float
        var metalness: Float
        var normalStrength: CGFloat
    }

    private static func spec(for surface: SurfaceKind) -> SurfaceSpec {
        switch surface {
        case .concrete: return SurfaceSpec(color: UIColor(hex: 0x8C8880), roughness: 0.85, metalness: 0.0, normalStrength: 0.5)
        case .metal:    return SurfaceSpec(color: UIColor(hex: 0x6E7681), roughness: 0.35, metalness: 0.9, normalStrength: 0.35)
        case .wood:     return SurfaceSpec(color: UIColor(hex: 0x8A6238), roughness: 0.75, metalness: 0.0, normalStrength: 0.6)
        case .dirt:     return SurfaceSpec(color: UIColor(hex: 0x6B563C), roughness: 0.95, metalness: 0.0, normalStrength: 0.8)
        case .sand:     return SurfaceSpec(color: UIColor(hex: 0xC8AE7D), roughness: 0.92, metalness: 0.0, normalStrength: 0.7)
        case .grass:    return SurfaceSpec(color: UIColor(hex: 0x4C6B3A), roughness: 0.95, metalness: 0.0, normalStrength: 0.9)
        case .water:    return SurfaceSpec(color: UIColor(hex: 0x2E5A72), roughness: 0.08, metalness: 0.2, normalStrength: 0.3)
        case .glass:    return SurfaceSpec(color: UIColor(hex: 0xBFE0EA), roughness: 0.05, metalness: 0.1, normalStrength: 0.1)
        case .fabric:   return SurfaceSpec(color: UIColor(hex: 0x7A5A4A), roughness: 0.98, metalness: 0.0, normalStrength: 0.5)
        case .flesh:    return SurfaceSpec(color: UIColor(hex: 0x9B5A52), roughness: 0.7, metalness: 0.0, normalStrength: 0.3)
        case .plastic:  return SurfaceSpec(color: UIColor(hex: 0x9AA3AB), roughness: 0.5, metalness: 0.0, normalStrength: 0.2)
        case .tile:     return SurfaceSpec(color: UIColor(hex: 0xADB4BC), roughness: 0.3, metalness: 0.05, normalStrength: 0.25)
        }
    }

    private static func drawSurface(_ surface: SurfaceKind, color: UIColor,
                                    in context: CGContext, size: CGFloat) {
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        var generator = SystemRandomNumberGenerator()
        func random(_ range: ClosedRange<CGFloat>) -> CGFloat {
            CGFloat.random(in: range, using: &generator)
        }

        switch surface {
        case .concrete, .sand, .dirt, .plastic, .flesh:
            // Fine speckle.
            for _ in 0..<Int(size * 1.6) {
                let shade = random(-0.09...0.09)
                context.setFillColor(color.adjusted(brightness: shade).cgColor)
                let s = random(1...3)
                context.fill(CGRect(x: random(0...size), y: random(0...size), width: s, height: s))
            }
        case .metal:
            // Brushed streaks plus panel lines.
            for _ in 0..<Int(size / 2) {
                let shade = random(-0.12...0.12)
                context.setFillColor(color.adjusted(brightness: shade).cgColor)
                let y = random(0...size)
                context.fill(CGRect(x: 0, y: y, width: size, height: random(0.5...1.5)))
            }
            context.setStrokeColor(color.adjusted(brightness: -0.3).cgColor)
            context.setLineWidth(2)
            context.stroke(CGRect(x: 1, y: 1, width: size - 2, height: size - 2))
        case .wood:
            for _ in 0..<Int(size / 6) {
                context.setStrokeColor(color.adjusted(brightness: random(-0.18...0.05)).cgColor)
                context.setLineWidth(random(1...4))
                let y = random(0...size)
                context.move(to: CGPoint(x: 0, y: y))
                context.addCurve(to: CGPoint(x: size, y: y + random(-6...6)),
                                 control1: CGPoint(x: size * 0.33, y: y + random(-8...8)),
                                 control2: CGPoint(x: size * 0.66, y: y + random(-8...8)))
                context.strokePath()
            }
        case .grass:
            for _ in 0..<Int(size * 2) {
                context.setStrokeColor(color.adjusted(brightness: random(-0.15...0.2)).cgColor)
                context.setLineWidth(1)
                let x = random(0...size), y = random(0...size)
                context.move(to: CGPoint(x: x, y: y))
                context.addLine(to: CGPoint(x: x + random(-2...2), y: y - random(2...6)))
                context.strokePath()
            }
        case .tile:
            let cell = size / 4
            context.setStrokeColor(color.adjusted(brightness: -0.35).cgColor)
            context.setLineWidth(2)
            for i in 0...4 {
                let p = CGFloat(i) * cell
                context.move(to: CGPoint(x: p, y: 0)); context.addLine(to: CGPoint(x: p, y: size))
                context.move(to: CGPoint(x: 0, y: p)); context.addLine(to: CGPoint(x: size, y: p))
            }
            context.strokePath()
        case .glass, .water:
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [color.adjusted(brightness: 0.2).cgColor,
                                               color.adjusted(brightness: -0.15).cgColor] as CFArray,
                                      locations: [0, 1])
            if let gradient {
                context.drawLinearGradient(gradient, start: .zero,
                                           end: CGPoint(x: size, y: size), options: [])
            }
        case .fabric:
            for i in stride(from: CGFloat(0), to: size, by: 3) {
                context.setStrokeColor(color.adjusted(brightness: random(-0.08...0.08)).cgColor)
                context.setLineWidth(1)
                context.move(to: CGPoint(x: i, y: 0)); context.addLine(to: CGPoint(x: i, y: size))
                context.move(to: CGPoint(x: 0, y: i)); context.addLine(to: CGPoint(x: size, y: i))
                context.strokePath()
            }
        }
    }

    private static func drawNormalNoise(in context: CGContext, size: CGFloat, strength: CGFloat) {
        // Flat normal is (0.5, 0.5, 1.0) in tangent space.
        context.setFillColor(UIColor(red: 0.5, green: 0.5, blue: 1, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<Int(size * strength * 3) {
            let dx = CGFloat.random(in: -0.2...0.2, using: &generator) * strength
            let dy = CGFloat.random(in: -0.2...0.2, using: &generator) * strength
            context.setFillColor(UIColor(red: 0.5 + dx, green: 0.5 + dy, blue: 1, alpha: 1).cgColor)
            let s = CGFloat.random(in: 1...3, using: &generator)
            context.fill(CGRect(x: CGFloat.random(in: 0...size, using: &generator),
                                y: CGFloat.random(in: 0...size, using: &generator),
                                width: s, height: s))
        }
    }

    private static func drawGunmetal(color: UIColor, in context: CGContext, size: CGFloat) {
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<Int(size) {
            let shade = CGFloat.random(in: -0.1...0.1, using: &generator)
            context.setFillColor(color.adjusted(brightness: shade).cgColor)
            let y = CGFloat.random(in: 0...size, using: &generator)
            context.fill(CGRect(x: 0, y: y, width: size, height: 1))
        }
        // Faint hex pattern reads as a modern weapon finish at viewmodel distance.
        context.setStrokeColor(color.adjusted(brightness: 0.12).cgColor)
        context.setLineWidth(1)
        let step = size / 8
        for row in 0..<8 {
            for col in 0..<8 {
                let x = CGFloat(col) * step + (row % 2 == 0 ? 0 : step / 2)
                let y = CGFloat(row) * step
                context.strokeEllipse(in: CGRect(x: x, y: y, width: step * 0.6, height: step * 0.6))
            }
        }
    }

    private static func drawBulletHole(in context: CGContext, size: CGFloat) {
        context.clear(CGRect(x: 0, y: 0, width: size, height: size))
        let center = CGPoint(x: size / 2, y: size / 2)
        // Dark core with a lighter ring of displaced material.
        context.setFillColor(UIColor(white: 0.05, alpha: 0.95).cgColor)
        context.fillEllipse(in: CGRect(x: center.x - size * 0.16, y: center.y - size * 0.16,
                                       width: size * 0.32, height: size * 0.32))
        context.setStrokeColor(UIColor(white: 0.75, alpha: 0.35).cgColor)
        context.setLineWidth(size * 0.05)
        context.strokeEllipse(in: CGRect(x: center.x - size * 0.22, y: center.y - size * 0.22,
                                         width: size * 0.44, height: size * 0.44))
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<10 {
            context.setStrokeColor(UIColor(white: 0.1, alpha: 0.5).cgColor)
            context.setLineWidth(CGFloat.random(in: 0.5...1.5, using: &generator))
            let angle = CGFloat.random(in: 0...(2 * .pi), using: &generator)
            let length = CGFloat.random(in: size * 0.18...size * 0.42, using: &generator)
            context.move(to: center)
            context.addLine(to: CGPoint(x: center.x + cos(angle) * length,
                                        y: center.y + sin(angle) * length))
            context.strokePath()
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    func adjusted(brightness delta: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return self }
        return UIColor(red: min(1, max(0, r + delta)),
                       green: min(1, max(0, g + delta)),
                       blue: min(1, max(0, b + delta)), alpha: a)
    }

    func darkened(by factor: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return self }
        return UIColor(red: r * factor, green: g * factor, blue: b * factor, alpha: a)
    }
}
