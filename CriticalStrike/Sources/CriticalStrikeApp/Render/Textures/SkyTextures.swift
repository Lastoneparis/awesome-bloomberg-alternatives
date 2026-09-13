import Foundation
import UIKit
import CriticalStrikeCore

/// Generates the skybox as six cube faces.
///
/// A shooter's sky is doing more work than it looks: it sets the ambient colour that every
/// surface picks up, it is the only thing behind a player silhouetted on a ridge, and on a
/// mobile GPU it is far cheaper than any form of atmospheric scattering. Each face is
/// evaluated per direction, so the six images line up seamlessly at the edges by
/// construction — the function is continuous in direction space, and adjacent faces
/// evaluate the same direction at a shared seam.
enum SkyTextureFactory {

    struct Preset {
        var zenith: RGB
        var horizon: RGB
        var ground: RGB
        var sunColor: RGB
        var sunDirection: Vec3
        var sunSize: Float          // angular radius, radians
        var sunGlow: Float
        var cloudCoverage: Float    // 0 = clear, 1 = overcast
        var cloudSharpness: Float
        var cloudColor: RGB
        var cloudShadow: RGB
        var starDensity: Float
        var hazeStrength: Float

        static func named(_ name: String, sunDirection: Vec3) -> Preset {
            // Sun direction comes from the map so the skybox and the shadow-casting light
            // agree; nothing looks faker than a sun in the wrong half of the sky.
            let sun = (-sunDirection).normalized
            switch name {
            case "sky_desert_noon":
                return Preset(zenith: RGB(hex: 0x2E6FB5), horizon: RGB(hex: 0xD9C39A),
                              ground: RGB(hex: 0x8A7350), sunColor: RGB(hex: 0xFFF4D0),
                              sunDirection: sun, sunSize: 0.035, sunGlow: 0.22,
                              cloudCoverage: 0.18, cloudSharpness: 2.4,
                              cloudColor: RGB(hex: 0xFFFBF2), cloudShadow: RGB(hex: 0xCBBBA0),
                              starDensity: 0, hazeStrength: 0.55)
            case "sky_overcast":
                return Preset(zenith: RGB(hex: 0x6B7683), horizon: RGB(hex: 0xAEB6BE),
                              ground: RGB(hex: 0x555C64), sunColor: RGB(hex: 0xC8CFD6),
                              sunDirection: sun, sunSize: 0.09, sunGlow: 0.5,
                              cloudCoverage: 0.85, cloudSharpness: 1.1,
                              cloudColor: RGB(hex: 0x98A1AA), cloudShadow: RGB(hex: 0x5D666F),
                              starDensity: 0, hazeStrength: 0.8)
            case "sky_night_city":
                return Preset(zenith: RGB(hex: 0x080C18), horizon: RGB(hex: 0x2A2340),
                              ground: RGB(hex: 0x0A0A12), sunColor: RGB(hex: 0xBFD4FF),
                              sunDirection: sun, sunSize: 0.02, sunGlow: 0.1,
                              cloudCoverage: 0.45, cloudSharpness: 1.4,
                              cloudColor: RGB(hex: 0x3A3350), cloudShadow: RGB(hex: 0x15121F),
                              starDensity: 0.55, hazeStrength: 0.35)
            case "sky_snow_storm":
                return Preset(zenith: RGB(hex: 0x8FA3B8), horizon: RGB(hex: 0xD6E2EC),
                              ground: RGB(hex: 0xBCCBD8), sunColor: RGB(hex: 0xF2F7FF),
                              sunDirection: sun, sunSize: 0.12, sunGlow: 0.6,
                              cloudCoverage: 0.92, cloudSharpness: 0.9,
                              cloudColor: RGB(hex: 0xE4EDF5), cloudShadow: RGB(hex: 0xA8BAC9),
                              starDensity: 0, hazeStrength: 0.95)
            case "sky_indoor":
                return Preset(zenith: RGB(hex: 0x22262C), horizon: RGB(hex: 0x2C3138),
                              ground: RGB(hex: 0x1A1D22), sunColor: RGB(hex: 0x3A4048),
                              sunDirection: sun, sunSize: 0.0, sunGlow: 0,
                              cloudCoverage: 0, cloudSharpness: 1,
                              cloudColor: RGB(hex: 0x2C3138), cloudShadow: RGB(hex: 0x22262C),
                              starDensity: 0, hazeStrength: 0.2)
            default:
                return Preset(zenith: RGB(hex: 0x3C7BC4), horizon: RGB(hex: 0xBFD4E8),
                              ground: RGB(hex: 0x6E7A85), sunColor: RGB(hex: 0xFFF6E0),
                              sunDirection: sun, sunSize: 0.04, sunGlow: 0.3,
                              cloudCoverage: 0.35, cloudSharpness: 1.8,
                              cloudColor: RGB(hex: 0xFFFFFF), cloudShadow: RGB(hex: 0xB4C0CC),
                              starDensity: 0, hazeStrength: 0.5)
            }
        }
    }

    static func resolution(for quality: GraphicsQuality) -> Int {
        switch quality {
        case .low: return 128
        case .medium: return 192
        case .high: return 256
        case .ultra: return 384
        }
    }

    /// Returns the six cube faces in SceneKit's order: +X, −X, +Y, −Y, +Z, −Z.
    static func makeCubeMap(preset: Preset, size: Int, seed: UInt32 = 0x5C4B) -> [UIImage] {
        (0..<6).compactMap { face in
            makeFace(face, preset: preset, size: size, seed: seed)
        }
    }

    private static func direction(face: Int, u: Float, v: Float) -> Vec3 {
        switch face {
        case 0: return Vec3(1, -v, -u)     // +X
        case 1: return Vec3(-1, -v, u)     // −X
        case 2: return Vec3(u, 1, v)       // +Y
        case 3: return Vec3(u, -1, -v)     // −Y
        case 4: return Vec3(u, -v, 1)      // +Z
        default: return Vec3(-u, -v, -1)   // −Z
        }
    }

    private static func makeFace(_ face: Int, preset: Preset, size: Int, seed: UInt32) -> UIImage? {
        var canvas = PixelCanvas(width: size, height: size)
        let inverse = 2 / Float(size)

        for y in 0..<size {
            let v = (Float(y) + 0.5) * inverse - 1
            for x in 0..<size {
                let u = (Float(x) + 0.5) * inverse - 1
                let direction = direction(face: face, u: u, v: v).normalized
                canvas.set(x: x, y: y, color: color(for: direction, preset: preset, seed: seed))
            }
        }
        return canvas.makeImage()
    }

    private static func color(for direction: Vec3, preset: Preset, seed: UInt32) -> RGB {
        let elevation = direction.y

        // ── Base gradient ──
        var color: RGB
        if elevation >= 0 {
            // Raising the blend to a power keeps the horizon band tight rather than
            // smearing the whole upper hemisphere.
            let t = pow(MathUtil.clamp(elevation, 0, 1), 0.45)
            color = preset.horizon.lerp(preset.zenith, t)
        } else {
            let t = pow(MathUtil.clamp(-elevation, 0, 1), 0.6)
            color = preset.horizon.lerp(preset.ground, t)
        }

        // ── Stars, behind everything else ──
        if preset.starDensity > 0 && elevation > -0.05 {
            color = color + starContribution(direction: direction, density: preset.starDensity,
                                             seed: seed)
        }

        // ── Sun disc and glow ──
        if preset.sunSize > 0 {
            let alignment = MathUtil.clamp(direction.dot(preset.sunDirection), -1, 1)
            let angle = acos(alignment)
            let disc = 1 - Noise.smoothstep(preset.sunSize * 0.8, preset.sunSize, angle)
            // Inverse-power falloff is a decent stand-in for Mie scattering and costs one pow.
            let glow = pow(MathUtil.clamp(alignment, 0, 1), 64) * preset.sunGlow
                + pow(MathUtil.clamp(alignment, 0, 1), 6) * preset.sunGlow * 0.25
            color = color + preset.sunColor.scaled(glow)
            color = color.lerp(preset.sunColor.scaled(1.6), disc)
        }

        // ── Clouds, projected onto a plane above the viewer ──
        if preset.cloudCoverage > 0 && elevation > 0.02 {
            // The projection maps a direction onto a flat cloud deck. The scale matters
            // more than anything else here: too small and the whole sky is one blob, too
            // large and the clouds turn to noise.
            let projection = 1 / Swift.max(elevation, 0.04)
            let px = direction.x * projection * 2.5
            let pz = direction.z * projection * 2.5
            let (wx, wy) = Noise.warp(px, pz, period: 512, strength: 0.9, seed: seed &+ 3)
            let density = Noise.fbm(wx, wy, period: 512, octaves: 5, gain: 0.55,
                                    basis: .gradient, seed: seed &+ 5)

            // fBm clusters tightly around 0.5, so coverage maps onto a threshold band
            // rather than onto `1 - coverage`, which would only ever produce clouds at
            // the extremes.
            let threshold = 0.68 - preset.cloudCoverage * 0.45
            var amount = Noise.smoothstep(threshold, threshold + 0.22 / preset.cloudSharpness,
                                          density)
            // Fade clouds out well before the horizon. The flat-deck projection stretches
            // toward the horizon until the high-frequency octaves turn to speckle, and
            // hiding that is cheaper than paying for a proper atmosphere.
            amount *= Noise.smoothstep(0.06, 0.34, elevation)

            // Denser parts of the cloud are lit, thinner edges fall into shadow — enough
            // to read as volume without a second noise lookup.
            let lit = Noise.smoothstep(threshold, threshold + 0.34, density + 0.06)
            let cloud = preset.cloudShadow.lerp(preset.cloudColor, lit)
            color = color.lerp(cloud, amount)
        }

        // ── Horizon haze ──
        let haze = (1 - Noise.smoothstep(0, 0.35, abs(elevation))) * preset.hazeStrength
        color = color.lerp(preset.horizon, haze * 0.5)

        return color
    }

    private static func starContribution(direction: Vec3, density: Float, seed: UInt32) -> RGB {
        // Quantize the direction into a fine grid and place at most one star per cell.
        let scale: Float = 220
        let gx = Int(floor(direction.x * scale))
        let gy = Int(floor(direction.y * scale))
        let gz = Int(floor(direction.z * scale))
        let cellHash = Noise.hash(gx &+ gz &* 7919, gy, seed &+ 101)
        guard cellHash > 1 - density * 0.06 else { return .black }

        let brightness = Noise.hash(gx, gy &+ gz &* 31, seed &+ 211)
        // A few stars are notably brighter, which is what makes a star field read as one.
        let intensity = pow(brightness, 3) * 1.4 + 0.15
        let temperature = Noise.hash(gz, gx, seed &+ 307)
        let tint = RGB(1, 0.92 + temperature * 0.08, 0.85 + temperature * 0.15)
        return tint.scaled(intensity)
    }
}
