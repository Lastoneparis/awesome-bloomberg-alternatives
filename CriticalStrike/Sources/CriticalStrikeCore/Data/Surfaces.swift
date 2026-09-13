import Foundation

/// Surface material — drives impact VFX, footstep audio, and bullet penetration.
public enum SurfaceKind: UInt8, Codable, CaseIterable, Sendable {
    case concrete = 0, metal, wood, dirt, sand, grass, water, glass, fabric, flesh, plastic, tile

    /// How much penetration power the bullet loses crossing one unit of this material.
    public var penetrationCost: Float {
        switch self {
        case .concrete: return 2.4
        case .metal: return 3.0
        case .wood: return 1.0
        case .dirt: return 1.8
        case .sand: return 2.0
        case .grass: return 0.6
        case .water: return 1.4
        case .glass: return 0.25
        case .fabric: return 0.3
        case .flesh: return 0.9
        case .plastic: return 0.7
        case .tile: return 1.6
        }
    }

    /// Extra damage reduction applied on top of the weapon's own penetration scale.
    public var penetrationDamageLoss: Float {
        switch self {
        case .metal, .concrete: return 0.35
        case .glass, .fabric: return 0.05
        default: return 0.18
        }
    }

    public var isSoft: Bool {
        switch self { case .fabric, .grass, .flesh, .water: return true; default: return false }
    }

    public var breaksOnHit: Bool { self == .glass }

    public var footstepVolume: Float {
        switch self {
        case .metal, .tile: return 1.15
        case .concrete: return 1.0
        case .wood: return 0.95
        case .water: return 1.2
        case .grass, .dirt, .sand: return 0.7
        case .fabric: return 0.45
        default: return 0.9
        }
    }

    public var impactEffect: String { "fx_impact_\(String(describing: self))" }
    public var impactSound: String { "sfx_impact_\(String(describing: self))" }
    public var footstepSound: String { "sfx_step_\(String(describing: self))" }
    public var decalName: String { self == .glass ? "decal_glass" : "decal_bullet_\(String(describing: self))" }
}

/// Which part of the body a bullet struck.
public enum HitboxKind: UInt8, Codable, CaseIterable, Sendable {
    case head = 0, neck, chest, stomach, arm, leg, foot

    public var damageMultiplier: Float {
        switch self {
        case .head: return 1.0     // the weapon's own headshotMultiplier is applied separately
        case .neck: return 1.5
        case .chest: return 1.0
        case .stomach: return 1.18
        case .arm: return 0.78
        case .leg: return 0.72
        case .foot: return 0.62
        }
    }

    /// Armor only covers the torso and head (with a helmet).
    public var isArmorCovered: Bool {
        switch self { case .chest, .stomach, .neck: return true; default: return false }
    }

    public var isHead: Bool { self == .head }

    /// Leg hits slow the target briefly — a small but meaningful skill reward.
    public var appliesSlow: Bool {
        switch self { case .leg, .foot: return true; default: return false }
    }

    public var displayName: String {
        ["Head", "Neck", "Chest", "Stomach", "Arm", "Leg", "Foot"][Int(rawValue)]
    }
}

/// Capsule/box hitboxes attached to the player's local space. Y is measured from the feet.
public struct HitboxDefinition: Sendable {
    public let kind: HitboxKind
    public let center: Vec3
    public let size: Vec3

    public init(kind: HitboxKind, center: Vec3, size: Vec3) {
        self.kind = kind; self.center = center; self.size = size
    }

    public func box(at position: Vec3, crouchScale: Float) -> AABB {
        let c = Vec3(center.x, center.y * crouchScale, center.z)
        let s = Vec3(size.x, size.y * crouchScale, size.z)
        return AABB(center: position + c, size: s)
    }
}

public enum HitboxLayout {
    /// A 1.8m tall operator. Head is deliberately generous-but-fair (0.26m cube):
    /// big enough for touch aim, small enough that body shots remain the default.
    public static let standing: [HitboxDefinition] = [
        HitboxDefinition(kind: .head,    center: Vec3(0, 1.68, 0), size: Vec3(0.26, 0.26, 0.26)),
        HitboxDefinition(kind: .neck,    center: Vec3(0, 1.50, 0), size: Vec3(0.20, 0.12, 0.20)),
        HitboxDefinition(kind: .chest,   center: Vec3(0, 1.27, 0), size: Vec3(0.52, 0.40, 0.32)),
        HitboxDefinition(kind: .stomach, center: Vec3(0, 0.95, 0), size: Vec3(0.46, 0.28, 0.30)),
        HitboxDefinition(kind: .arm,     center: Vec3(-0.36, 1.20, 0), size: Vec3(0.18, 0.62, 0.20)),
        HitboxDefinition(kind: .arm,     center: Vec3(0.36, 1.20, 0), size: Vec3(0.18, 0.62, 0.20)),
        HitboxDefinition(kind: .leg,     center: Vec3(-0.16, 0.50, 0), size: Vec3(0.22, 0.62, 0.24)),
        HitboxDefinition(kind: .leg,     center: Vec3(0.16, 0.50, 0), size: Vec3(0.22, 0.62, 0.24)),
        HitboxDefinition(kind: .foot,    center: Vec3(-0.16, 0.10, 0.03), size: Vec3(0.20, 0.20, 0.32)),
        HitboxDefinition(kind: .foot,    center: Vec3(0.16, 0.10, 0.03), size: Vec3(0.20, 0.20, 0.32))
    ]

    /// Cheap broadphase box so we can reject most players before testing 10 hitboxes.
    public static func bounds(at position: Vec3, crouchScale: Float) -> AABB {
        AABB(min: position + Vec3(-0.5, 0, -0.5),
             max: position + Vec3(0.5, 1.85 * crouchScale, 0.5))
    }
}
