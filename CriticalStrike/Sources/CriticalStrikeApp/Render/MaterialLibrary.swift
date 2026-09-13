import Foundation
import SceneKit
import UIKit
import CriticalStrikeCore

/// Builds SceneKit materials from the generated texture sets.
///
/// The game ships no bitmap art. Every material here is assembled from images that
/// `TextureLibrary` synthesised at load time: albedo, tangent-space normal, roughness,
/// ambient occlusion, metalness and emission. Because all six maps derive from one shared
/// height field per surface, the lighting agrees with the visible detail — which is what
/// separates a procedural material from noise with a bump map bolted on.
final class MaterialLibrary {
    private let textures: TextureLibrary
    private var cache: [String: SCNMaterial] = [:]
    private let quality: GraphicsQuality

    init(textures: TextureLibrary) {
        self.textures = textures
        self.quality = textures.quality
    }

    // MARK: - World surfaces

    func material(for surface: SurfaceKind, tintOverride: UIColor? = nil) -> SCNMaterial {
        let key = "surface_\(surface.rawValue)_\(tintOverride?.description ?? "-")"
        if let cached = cache[key] { return cached }

        let set = textures.surfaceTextures(surface)
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.name = key

        material.diffuse.contents = set.albedo
        if let tintOverride {
            // Multiplying keeps the generated detail and only shifts the hue.
            material.multiply.contents = tintOverride
        }
        apply(set: set, to: material, defaultRoughness: defaultRoughness(for: surface),
              defaultMetalness: defaultMetalness(for: surface))
        configureSampling(material)
        applyMacroVariation(to: material, surface: surface)

        switch surface {
        case .glass:
            material.transparency = 0.34
            material.transparencyMode = .dualLayer
            material.blendMode = .alpha
            material.writesToDepthBuffer = false
            material.isDoubleSided = true
        case .water:
            material.transparency = 0.72
            material.blendMode = .alpha
            material.isDoubleSided = true
        case .flesh:
            // A little forward scatter stops skin reading as painted plastic.
            material.emission.contents = UIColor(red: 0.18, green: 0.04, blue: 0.04, alpha: 1)
            material.emission.intensity = 0.12
        default:
            break
        }

        cache[key] = material
        return material
    }

    /// Materials are shared, so per-brush texture scale is applied to the node's geometry
    /// rather than here. This returns the repeat count that keeps texel density constant.
    static func textureScale(forSize size: Vec3, metresPerTile: Float = 2.5) -> (Float, Float) {
        let width = max(max(size.x, size.z), 0.1)
        let height = max(size.y, 0.1)
        return (width / metresPerTile, height / metresPerTile)
    }

    private func defaultRoughness(for surface: SurfaceKind) -> Float {
        switch surface {
        case .metal: return 0.35
        case .glass: return 0.05
        case .water: return 0.06
        case .tile: return 0.25
        case .plastic: return 0.5
        case .flesh: return 0.65
        default: return 0.9
        }
    }

    private func defaultMetalness(for surface: SurfaceKind) -> Float {
        switch surface {
        case .metal: return 0.9
        case .tile: return 0.05
        default: return 0
        }
    }

    // MARK: - Weapons

    func weaponMaterial(build: WeaponBuild) -> SCNMaterial {
        let cosmetic = build.skin.flatMap(CosmeticDatabase.cosmetic)
        return weaponMaterial(skin: cosmetic)
    }

    func weaponMaterial(skin: CosmeticData?) -> SCNMaterial {
        let pattern = SkinPattern.pattern(for: skin)
        let tint = RGB(hex: skin?.tintHex ?? 0x2E3238)
        let key = "weapon_\(pattern.rawValue)_\(skin?.id.value ?? "default")"
        if let cached = cache[key] { return cached }

        let set = textures.skinTextures(pattern: pattern, tint: tint)
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.name = key
        material.diffuse.contents = set.albedo
        apply(set: set, to: material,
              defaultRoughness: pattern.isMetal ? 0.25 : 0.55,
              defaultMetalness: pattern.isMetal ? 0.9 : 0.1)
        configureSampling(material, repeats: false)

        if pattern.isEmissive, let emission = set.emission {
            material.emission.contents = emission
            material.emission.intensity = skin?.rarity == .mythic ? 1.4 : 1.0
        }
        if pattern == .phantomGlass {
            material.transparency = 0.8
            material.blendMode = .alpha
        }

        cache[key] = material
        return material
    }

    // MARK: - Characters

    /// Operator fatigues: the same camo generator as weapon skins, tinted to the team so
    /// the two sides are readable at a glance without flat colour blocks.
    func characterMaterial(team: Team, colorBlind: ColorBlindMode, accent: Bool = false) -> SCNMaterial {
        let key = "char_\(team.rawValue)_\(colorBlind.rawValue)_\(accent)"
        if let cached = cache[key] { return cached }

        let teamColor = RGB(hex: colorBlind.teamColor(team))
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.name = key

        if accent {
            // Webbing and chest rig: flat team colour, slightly emissive so it reads in
            // shadow, which is where most of a firefight happens.
            material.diffuse.contents = teamColor.uiColor
            material.emission.contents = teamColor.scaled(0.35).uiColor
            material.roughness.contents = NSNumber(value: 0.55)
            material.metalness.contents = NSNumber(value: 0.15)
        } else {
            let set = textures.skinTextures(pattern: .urbanCamo, tint: teamColor.scaled(0.55))
            material.diffuse.contents = set.albedo
            apply(set: set, to: material, defaultRoughness: 0.85, defaultMetalness: 0)
            configureSampling(material, repeats: false)
        }

        cache[key] = material
        return material
    }

    // MARK: - Effects

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

    /// Bullet holes and splatter. The decal image already carries its own alpha shape, so
    /// the material only has to stay out of the depth buffer's way.
    func decalMaterial(surface: SurfaceKind) -> SCNMaterial {
        let kind = DecalKind.forSurface(surface)
        let key = "decal_\(kind.rawValue)"
        if let cached = cache[key] { return cached }

        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = textures.decal(kind)
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.diffuse.mipFilter = .linear
        cache[key] = material
        return material
    }

    func spriteImage(_ kind: SpriteKind) -> UIImage? {
        textures.sprite(kind)
    }

    /// A billboard material for a generated sprite. Additive for anything hot (muzzle
    /// flashes, tracers, sparks); alpha for anything that occludes (smoke, blood).
    func spriteMaterial(_ kind: SpriteKind, tint: UIColor, additive: Bool = true) -> SCNMaterial {
        let key = "sprite_\(kind.rawValue)_\(tint.description)_\(additive)"
        if let cached = cache[key] { return cached }
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = textures.sprite(kind)
        material.multiply.contents = tint
        material.blendMode = additive ? .add : .alpha
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.isDoubleSided = true
        material.diffuse.mipFilter = .linear
        cache[key] = material
        return material
    }

    func skyCubeMap(for environment: MapEnvironment) -> [UIImage] {
        textures.skyCubeMap(for: environment)
    }

    // MARK: - Macro variation

    /// Breaks up texture tiling at a scale no tile can reach.
    ///
    /// Surface textures repeat every 2.5 metres so that texel density stays constant, which
    /// means a long wall shows the same tile a dozen times and the eye locks onto the grid
    /// however good the tile is. This multiplies the albedo by a large, soft variation map
    /// sampled in *world* space — so the pattern is continuous across brush boundaries and
    /// takes tens of metres to repeat — and nudges roughness the same way, which is what
    /// makes the light move across a wall instead of sitting flat on it.
    ///
    /// One extra texture fetch per fragment, shared by every world material.
    private static let macroVariationModifier = """
    uniform sampler2D macroVariationTexture;
    uniform float macroVariationStrength;
    uniform float macroVariationScale;

    vec3 macroWorldPosition = (u_inverseViewTransform * vec4(_surface.position, 1.0)).xyz;
    vec2 macroCoord = macroWorldPosition.xz * macroVariationScale
                    + vec2(macroWorldPosition.y * macroVariationScale * 0.6);
    float macroValue = texture2D(macroVariationTexture, macroCoord).r - 0.5;
    _surface.diffuse.rgb *= clamp(1.0 + macroValue * 2.0 * macroVariationStrength, 0.0, 2.0);
    _surface.roughness = clamp(_surface.roughness - macroValue * 0.18, 0.03, 1.0);
    """

    private func applyMacroVariation(to material: SCNMaterial, surface: SurfaceKind) {
        // Skipped on the low tier, where the extra fetch is not worth it, and on the
        // transparent surfaces, where modulating albedo reads as dirt on the glass.
        guard quality != .low, surface != .glass, surface != .water,
              let image = textures.macroVariation() else { return }

        let property = SCNMaterialProperty(contents: image)
        property.wrapS = .repeat
        property.wrapT = .repeat
        property.mipFilter = .linear
        property.minificationFilter = .linear
        property.magnificationFilter = .linear

        // The modifier goes on first: the uniform keys only exist once SceneKit has
        // parsed the snippet that declares them.
        material.shaderModifiers = [.surface: MaterialLibrary.macroVariationModifier]
        material.setValue(property, forKey: "macroVariationTexture")
        material.setValue(NSNumber(value: macroStrength(for: surface)),
                          forKey: "macroVariationStrength")
        // One repeat per ~55 metres, which is wider than any map, so the variation map
        // itself never visibly tiles.
        material.setValue(NSNumber(value: Float(0.018)), forKey: "macroVariationScale")
    }

    /// How much drift each surface tolerates. Ground surfaces take the most — real dirt
    /// and grass are never one tone — while manufactured surfaces take very little,
    /// because uneven paint on a plastic crate reads as a rendering bug.
    private func macroStrength(for surface: SurfaceKind) -> Float {
        switch surface {
        case .dirt, .grass, .sand: return 0.22
        case .concrete, .wood: return 0.18
        case .metal, .tile: return 0.10
        case .plastic, .fabric: return 0.07
        default: return 0.12
        }
    }

    // MARK: - Shared setup

    private func apply(set: TextureSet, to material: SCNMaterial,
                       defaultRoughness: Float, defaultMetalness: Float) {
        if let normal = set.normal, quality != .low {
            material.normal.contents = normal
            material.normal.intensity = quality == .ultra ? 1.0 : 0.8
        }
        if let roughness = set.roughness {
            material.roughness.contents = roughness
        } else {
            material.roughness.contents = NSNumber(value: defaultRoughness)
        }
        if let metalness = set.metalness {
            material.metalness.contents = metalness
        } else {
            material.metalness.contents = NSNumber(value: defaultMetalness)
        }
        // Baked occlusion only affects ambient light, so it deepens crevices without
        // fighting the dynamic lights.
        if let occlusion = set.occlusion, quality != .low {
            material.ambientOcclusion.contents = occlusion
        }
    }

    private func configureSampling(_ material: SCNMaterial, repeats: Bool = true) {
        for property in [material.diffuse, material.normal, material.roughness,
                         material.metalness, material.ambientOcclusion, material.emission,
                         material.multiply] {
            if repeats {
                property.wrapS = .repeat
                property.wrapT = .repeat
            }
            property.mipFilter = .linear
            property.minificationFilter = .linear
            property.magnificationFilter = .linear
            // Anisotropy is what keeps a floor from turning to mush at grazing angles —
            // by far the best quality-per-millisecond setting on a mobile GPU.
            property.maxAnisotropy = quality == .low ? 1 : (quality == .ultra ? 8 : 4)
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
