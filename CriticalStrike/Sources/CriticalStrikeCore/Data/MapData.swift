import Foundation

/// Level geometry is brush-based (axis-aligned boxes). It keeps collision trivially fast on
/// mobile, lets the renderer batch by material, and makes maps authorable in plain Swift.
public struct MapBrush: Codable, Sendable {
    public var box: AABB
    public var surface: SurfaceKind
    public var material: String
    public var isClip: Bool          // invisible collision volume (player clip / skybox wall)
    public var isBreakable: Bool
    public var blocksBullets: Bool
    public var blocksVision: Bool
    public var thickness: Float      // used by penetration math

    public init(box: AABB, surface: SurfaceKind = .concrete, material: String = "",
                isClip: Bool = false, isBreakable: Bool = false,
                blocksBullets: Bool = true, blocksVision: Bool = true, thickness: Float? = nil) {
        self.box = box; self.surface = surface
        self.material = material.isEmpty ? "mat_\(String(describing: surface))" : material
        self.isClip = isClip; self.isBreakable = isBreakable
        self.blocksBullets = blocksBullets; self.blocksVision = blocksVision
        let s = box.size
        self.thickness = thickness ?? Swift.min(Swift.min(s.x, s.y), s.z)
    }
}

public struct MapProp: Codable, Sendable {
    public var name: String
    public var position: Vec3
    public var yaw: Float
    public var scale: Float
    public var collides: Bool
    public var surface: SurfaceKind

    public init(name: String, position: Vec3, yaw: Float = 0, scale: Float = 1,
                collides: Bool = false, surface: SurfaceKind = .metal) {
        self.name = name; self.position = position; self.yaw = yaw; self.scale = scale
        self.collides = collides; self.surface = surface
    }
}

public enum MapLightKind: String, Codable, Sendable { case omni, spot, directional, area }

public struct MapLight: Codable, Sendable {
    public var kind: MapLightKind
    public var position: Vec3
    public var direction: Vec3
    public var colorHex: UInt32
    public var intensity: Float
    public var range: Float
    public var spotAngle: Float
    public var castsShadows: Bool

    public init(kind: MapLightKind, position: Vec3, direction: Vec3 = Vec3(0, -1, 0),
                colorHex: UInt32 = 0xFFF4E2, intensity: Float = 800, range: Float = 18,
                spotAngle: Float = 70, castsShadows: Bool = false) {
        self.kind = kind; self.position = position; self.direction = direction
        self.colorHex = colorHex; self.intensity = intensity; self.range = range
        self.spotAngle = spotAngle; self.castsShadows = castsShadows
    }
}

public struct SpawnPoint: Codable, Sendable {
    public var position: Vec3
    public var yaw: Float
    public var team: Team
    public var priority: Int      // higher = preferred at round start

    public init(position: Vec3, yaw: Float = 0, team: Team = .none, priority: Int = 0) {
        self.position = position; self.yaw = yaw; self.team = team; self.priority = priority
    }
}

public struct ObjectiveZone: Codable, Sendable {
    public var index: Int
    public var name: String
    public var center: Vec3
    public var radius: Float
    public var height: Float

    public init(index: Int, name: String, center: Vec3, radius: Float, height: Float = 3.5) {
        self.index = index; self.name = name; self.center = center
        self.radius = radius; self.height = height
    }

    public func contains(_ p: Vec3) -> Bool {
        let d = (p - center).flattened
        return d.lengthSquared <= radius * radius && p.y >= center.y - 1.5 && p.y <= center.y + height
    }
}

public struct NavNode: Codable, Sendable {
    public var id: Int
    public var position: Vec3
    public var radius: Float
    public var links: [Int]
    public var isCover: Bool
    public var isSniperPerch: Bool
    public var objectiveIndex: Int?   // nav nodes near a bomb site / capture point
    public var callout: String

    public init(id: Int, position: Vec3, radius: Float = 1.2, links: [Int] = [],
                isCover: Bool = false, isSniperPerch: Bool = false,
                objectiveIndex: Int? = nil, callout: String = "") {
        self.id = id; self.position = position; self.radius = radius; self.links = links
        self.isCover = isCover; self.isSniperPerch = isSniperPerch
        self.objectiveIndex = objectiveIndex; self.callout = callout
    }
}

public struct PickupSpawn: Codable, Sendable {
    public var kind: PickupKind
    public var position: Vec3
    public var weapon: WeaponID?

    public init(kind: PickupKind, position: Vec3, weapon: WeaponID? = nil) {
        self.kind = kind; self.position = position; self.weapon = weapon
    }
}

public struct Callout: Codable, Sendable {
    public var name: String
    public var box: AABB
    public init(name: String, box: AABB) { self.name = name; self.box = box }
}

public struct MapEnvironment: Codable, Sendable {
    public var skyName: String
    public var ambientColorHex: UInt32
    public var ambientIntensity: Float
    public var fogColorHex: UInt32
    public var fogStart: Float
    public var fogEnd: Float
    public var fogDensity: Float
    public var sunDirection: Vec3
    public var sunColorHex: UInt32
    public var sunIntensity: Float
    public var bloomThreshold: Float
    public var musicTrack: String
    public var ambienceLoop: String

    public init(skyName: String = "sky_day", ambientColorHex: UInt32 = 0x5A6472,
                ambientIntensity: Float = 260, fogColorHex: UInt32 = 0xAEB8C4,
                fogStart: Float = 40, fogEnd: Float = 180, fogDensity: Float = 0.6,
                sunDirection: Vec3 = Vec3(-0.4, -0.85, -0.35), sunColorHex: UInt32 = 0xFFF0D8,
                sunIntensity: Float = 1400, bloomThreshold: Float = 0.82,
                musicTrack: String = "mus_combat_a", ambienceLoop: String = "amb_wind") {
        self.skyName = skyName; self.ambientColorHex = ambientColorHex
        self.ambientIntensity = ambientIntensity; self.fogColorHex = fogColorHex
        self.fogStart = fogStart; self.fogEnd = fogEnd; self.fogDensity = fogDensity
        self.sunDirection = sunDirection; self.sunColorHex = sunColorHex
        self.sunIntensity = sunIntensity; self.bloomThreshold = bloomThreshold
        self.musicTrack = musicTrack; self.ambienceLoop = ambienceLoop
    }
}

public struct MapData: Codable, Identifiable, Sendable {
    public var id: MapID
    public var name: String
    public var summary: String
    public var previewImage: String
    public var bounds: AABB
    public var environment: MapEnvironment
    public var brushes: [MapBrush]
    public var props: [MapProp]
    public var lights: [MapLight]
    public var spawns: [SpawnPoint]
    public var bombSites: [ObjectiveZone]
    public var capturePoints: [ObjectiveZone]
    public var hardpoints: [ObjectiveZone]
    public var navNodes: [NavNode]
    public var pickups: [PickupSpawn]
    public var callouts: [Callout]
    public var supportedModes: [GameModeKind]
    public var recommendedPlayers: ClosedRange<Int>

    public init(id: MapID, name: String, summary: String, previewImage: String = "",
                bounds: AABB, environment: MapEnvironment = MapEnvironment(),
                brushes: [MapBrush] = [], props: [MapProp] = [], lights: [MapLight] = [],
                spawns: [SpawnPoint] = [], bombSites: [ObjectiveZone] = [],
                capturePoints: [ObjectiveZone] = [], hardpoints: [ObjectiveZone] = [],
                navNodes: [NavNode] = [], pickups: [PickupSpawn] = [], callouts: [Callout] = [],
                supportedModes: [GameModeKind] = GameModeKind.allCases,
                recommendedPlayers: ClosedRange<Int> = 6...10) {
        self.id = id; self.name = name; self.summary = summary
        self.previewImage = previewImage.isEmpty ? "img_map_\(id.value)" : previewImage
        self.bounds = bounds; self.environment = environment
        self.brushes = brushes; self.props = props; self.lights = lights; self.spawns = spawns
        self.bombSites = bombSites; self.capturePoints = capturePoints; self.hardpoints = hardpoints
        self.navNodes = navNodes; self.pickups = pickups; self.callouts = callouts
        self.supportedModes = supportedModes; self.recommendedPlayers = recommendedPlayers
    }

    public func spawns(for team: Team) -> [SpawnPoint] {
        let matching = spawns.filter { $0.team == team }
        return matching.isEmpty ? spawns : matching
    }

    public func callout(at p: Vec3) -> String {
        callouts.first { $0.box.contains(p) }?.name ?? ""
    }

    /// Minimap extents in world units (XZ).
    public var minimapSize: (width: Float, depth: Float) {
        (bounds.size.x, bounds.size.z)
    }

    public func supports(_ mode: GameModeKind) -> Bool {
        supportedModes.contains(mode)
    }
}

extension ClosedRange: @retroactive Codable where Bound: Codable {
    private enum CodingKeys: String, CodingKey { case lower, upper }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let lo = try c.decode(Bound.self, forKey: .lower)
        let hi = try c.decode(Bound.self, forKey: .upper)
        self = lo...hi
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(lowerBound, forKey: .lower)
        try c.encode(upperBound, forKey: .upper)
    }
}
