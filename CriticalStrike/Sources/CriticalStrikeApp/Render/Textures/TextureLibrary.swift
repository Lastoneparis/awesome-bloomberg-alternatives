import Foundation
import UIKit
import CriticalStrikeCore

/// Owns every generated image: surfaces, skins, sprites, decals and skyboxes.
///
/// Generation is deterministic, so the results are cached to disk as PNGs and a second
/// launch pays nothing. The first launch generates everything in parallel during the
/// loading screen — which is exactly the moment a game is allowed to spend CPU.
final class TextureLibrary: @unchecked Sendable {
    /// Bump to invalidate every cached image on disk after changing a generator.
    static let generationVersion = 1

    let quality: GraphicsQuality
    private let surfaceSize: Int
    private let skinSize: Int
    private let spriteSize: Int
    private let decalSize: Int
    private let skySize: Int

    private var surfaceCache: [SurfaceKind: TextureSet] = [:]
    private var skinCache: [String: TextureSet] = [:]
    private var spriteCache: [SpriteKind: UIImage] = [:]
    private var decalCache: [DecalKind: UIImage] = [:]
    private var skyCache: [String: [UIImage]] = [:]
    private let lock = NSLock()

    private let diskCacheURL: URL?
    /// Disk caching is skipped on low-end devices: the PNG round trip costs more there
    /// than regenerating at 256².
    private let usesDiskCache: Bool

    init(quality: GraphicsQuality) {
        self.quality = quality
        self.surfaceSize = SurfaceTextureFactory.resolution(for: quality)
        self.skinSize = SkinTextureFactory.resolution(for: quality)
        self.spriteSize = SpriteFactory.spriteResolution(for: quality)
        self.decalSize = SpriteFactory.decalResolution(for: quality)
        self.skySize = SkyTextureFactory.resolution(for: quality)
        self.usesDiskCache = quality != .low

        let directory = TextureLibrary.cacheDirectory
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        self.diskCacheURL = directory
    }

    static var cacheDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CriticalStrike", isDirectory: true)
            .appendingPathComponent("Textures", isDirectory: true)
            .appendingPathComponent("v\(TextureLibrary.generationVersion)", isDirectory: true)
    }

    // MARK: - Accessors

    func surfaceTextures(_ surface: SurfaceKind) -> TextureSet {
        lock.lock()
        if let cached = surfaceCache[surface] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let key = "surface_\(surface.rawValue)"
        let set = loadOrMake(key: key, size: surfaceSize) {
            SurfaceTextureFactory.make(surface: surface, size: self.surfaceSize)
        }
        lock.lock()
        surfaceCache[surface] = set
        lock.unlock()
        return set
    }

    func skinTextures(pattern: SkinPattern, tint: RGB) -> TextureSet {
        // Quantize the tint into the key so near-identical skins share one texture set.
        let tintKey = Int(tint.r * 31) * 1024 + Int(tint.g * 31) * 32 + Int(tint.b * 31)
        let key = "skin_\(pattern.rawValue)_\(tintKey)"
        lock.lock()
        if let cached = skinCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let set = loadOrMake(key: key, size: skinSize) {
            SkinTextureFactory.make(pattern: pattern, tint: tint, size: self.skinSize)
        }
        lock.lock()
        skinCache[key] = set
        lock.unlock()
        return set
    }

    func sprite(_ kind: SpriteKind) -> UIImage? {
        lock.lock()
        if let cached = spriteCache[kind] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let image = loadOrMakeImage(key: "sprite_\(kind.rawValue)", size: spriteSize) {
            SpriteFactory.sprite(kind, size: self.spriteSize)
        }
        if let image {
            lock.lock()
            spriteCache[kind] = image
            lock.unlock()
        }
        return image
    }

    func decal(_ kind: DecalKind) -> UIImage? {
        lock.lock()
        if let cached = decalCache[kind] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let image = loadOrMakeImage(key: "decal_\(kind.rawValue)", size: decalSize) {
            SpriteFactory.decal(kind, size: self.decalSize)
        }
        if let image {
            lock.lock()
            decalCache[kind] = image
            lock.unlock()
        }
        return image
    }

    func skyCubeMap(for environment: MapEnvironment) -> [UIImage] {
        let key = "sky_\(environment.skyName)_\(Int(environment.sunDirection.x * 10))"
            + "_\(Int(environment.sunDirection.y * 10))_\(Int(environment.sunDirection.z * 10))"
        lock.lock()
        if let cached = skyCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // All six faces come from one generation pass — evaluating the sky function per
        // face independently would cost six times as much for the same result.
        var faces: [UIImage] = []
        if usesDiskCache {
            let cached = (0..<6).compactMap { readImage(key: "\(key)_f\($0)", size: skySize) }
            if cached.count == 6 { faces = cached }
        }
        if faces.isEmpty {
            let preset = SkyTextureFactory.Preset.named(environment.skyName,
                                                        sunDirection: environment.sunDirection)
            faces = SkyTextureFactory.makeCubeMap(preset: preset, size: skySize)
            if usesDiskCache {
                for (index, face) in faces.enumerated() {
                    write(face, key: "\(key)_f\(index)", size: skySize)
                }
            }
        }
        lock.lock()
        skyCache[key] = faces
        lock.unlock()
        return faces
    }

    // MARK: - Warm up

    /// Generates everything a match needs, in parallel, reporting progress 0…1.
    /// Called from the loading screen; by the time the first frame renders, every
    /// material already has its images.
    func warmUp(map: MapData, loadout: Loadout, colorBlind: ColorBlindMode = .none,
                progress: @escaping (Double) -> Void) async {
        // Only the surfaces the map actually uses — no point generating grass for an
        // indoor arena.
        var surfaces = Set(map.brushes.filter { !$0.isClip }.map(\.surface))
        surfaces.formUnion(map.props.map(\.surface))
        surfaces.insert(.flesh)

        var skins: [(SkinPattern, RGB)] = [loadout.primary, loadout.secondary, loadout.melee]
            .map { build in
                let cosmetic = build.skin.flatMap(CosmeticDatabase.cosmetic)
                return (SkinPattern.pattern(for: cosmetic),
                        RGB(hex: cosmetic?.tintHex ?? 0x2E3238))
            }
        // Operator fatigues use the same generator, and they are needed the moment the
        // first player spawns — generating them then would hitch the opening seconds.
        for team in [Team.strike, Team.shield] {
            skins.append((.urbanCamo, RGB(hex: colorBlind.teamColor(team)).scaled(0.55)))
        }

        let totalSteps = surfaces.count + skins.count + SpriteKind.allCases.count
            + DecalKind.allCases.count + 6
        let counter = ProgressCounter(total: totalSteps, report: progress)

        await withTaskGroup(of: Void.self) { group in
            for surface in surfaces {
                group.addTask { [self] in
                    _ = surfaceTextures(surface)
                    await counter.advance()
                }
            }
            for (pattern, tint) in skins {
                group.addTask { [self] in
                    _ = skinTextures(pattern: pattern, tint: tint)
                    await counter.advance()
                }
            }
            for kind in SpriteKind.allCases {
                group.addTask { [self] in
                    _ = sprite(kind)
                    await counter.advance()
                }
            }
            for kind in DecalKind.allCases {
                group.addTask { [self] in
                    _ = decal(kind)
                    await counter.advance()
                }
            }
            group.addTask { [self] in
                _ = skyCubeMap(for: map.environment)
                for _ in 0..<6 { await counter.advance() }
            }
        }
        progress(1)
    }

    /// Serialises progress updates without a lock on the hot path.
    private actor ProgressCounter {
        private var completed = 0
        private let total: Int
        private let report: (Double) -> Void

        init(total: Int, report: @escaping (Double) -> Void) {
            self.total = Swift.max(1, total)
            self.report = report
        }

        func advance() {
            completed += 1
            report(Double(completed) / Double(total))
        }
    }

    // MARK: - Disk cache

    private func loadOrMake(key: String, size: Int,
                            generator: () -> TextureSet) -> TextureSet {
        if usesDiskCache,
           let albedo = readImage(key: "\(key)_albedo", size: size) {
            // All maps of a set are written together, so one hit means the set is present.
            return TextureSet(albedo: albedo,
                              normal: readImage(key: "\(key)_normal", size: size),
                              roughness: readImage(key: "\(key)_rough", size: size),
                              occlusion: readImage(key: "\(key)_ao", size: size),
                              metalness: readImage(key: "\(key)_metal", size: size),
                              emission: readImage(key: "\(key)_emission", size: size))
        }
        let set = generator()
        if usesDiskCache {
            write(set.albedo, key: "\(key)_albedo", size: size)
            write(set.normal, key: "\(key)_normal", size: size)
            write(set.roughness, key: "\(key)_rough", size: size)
            write(set.occlusion, key: "\(key)_ao", size: size)
            write(set.metalness, key: "\(key)_metal", size: size)
            write(set.emission, key: "\(key)_emission", size: size)
        }
        return set
    }

    private func loadOrMakeImage(key: String, size: Int,
                                 generator: () -> UIImage?) -> UIImage? {
        if usesDiskCache, let cached = readImage(key: key, size: size) { return cached }
        let image = generator()
        if usesDiskCache { write(image, key: key, size: size) }
        return image
    }

    private func url(key: String, size: Int) -> URL? {
        diskCacheURL?.appendingPathComponent("\(key)@\(size).png")
    }

    private func readImage(key: String, size: Int) -> UIImage? {
        guard let url = url(key: key, size: size),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func write(_ image: UIImage?, key: String, size: Int) {
        guard let image, let url = url(key: key, size: size), let data = image.pngData() else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    /// Total bytes the texture cache occupies on disk, for the settings screen. Static so
    /// the UI can report it without spinning up a library.
    static func diskCacheSize() -> Int64 {
        guard let directory = cacheDirectory,
              let contents = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return contents.reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    static func clearDiskCache() {
        guard let directory = cacheDirectory else { return }
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
