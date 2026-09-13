import Foundation

/// A player's collision volumes as seen by the ballistics pass. Built fresh each shot
/// (or rewound to a past tick for lag compensation).
public struct HitVolume: Sendable {
    public var player: PlayerID
    public var team: Team
    public var position: Vec3
    public var crouchScale: Float
    public var isAlive: Bool

    public init(player: PlayerID, team: Team, position: Vec3, crouchScale: Float, isAlive: Bool) {
        self.player = player; self.team = team; self.position = position
        self.crouchScale = crouchScale; self.isAlive = isAlive
    }

    public var bounds: AABB { HitboxLayout.bounds(at: position, crouchScale: crouchScale) }

    /// Returns the closest hitbox hit along the ray, if any.
    public func raycast(_ ray: Ray, maxDistance: Float) -> (t: Float, hitbox: HitboxKind)? {
        guard isAlive else { return nil }
        guard bounds.raycast(ray, maxDistance: maxDistance) != nil ||
              bounds.contains(ray.origin) else { return nil }

        var best: (Float, HitboxKind)?
        for def in HitboxLayout.standing {
            let box = def.box(at: position, crouchScale: crouchScale)
            guard let (t, _) = box.raycast(ray, maxDistance: maxDistance) else { continue }
            if best == nil || t < best!.0 { best = (t, def.kind) }
        }
        return best.map { (t: $0.0, hitbox: $0.1) }
    }
}

public struct ShotImpact: Sendable {
    public var position: Vec3
    public var normal: Vec3
    public var surface: SurfaceKind
    public var penetrated: Bool
}

public struct ShotHit: Sendable {
    public var victim: PlayerID
    public var hitbox: HitboxKind
    public var position: Vec3
    public var distance: Float
    public var penetratedSurfaces: Int
}

public struct ShotResult: Sendable {
    public var hits: [ShotHit] = []
    public var impacts: [ShotImpact] = []
    public var tracerEnd: Vec3 = .zero
}

/// Hitscan resolution with wall penetration. Projectiles (grenades, rockets) live in
/// `ProjectileSystem` instead; everything the guns fire is hitscan, which is what a
/// 64Hz mobile shooter can actually afford.
public enum BallisticsSystem {
    public static let maxPenetrations = 3

    public static func fireBullet(origin: Vec3,
                                  direction: Vec3,
                                  weapon: WeaponData,
                                  shooter: PlayerID,
                                  shooterTeam: Team,
                                  friendlyFire: Bool,
                                  world: CollisionWorld,
                                  targets: [HitVolume],
                                  maxDistance: Float? = nil) -> ShotResult {
        var result = ShotResult()
        var currentOrigin = origin
        var remaining = maxDistance ?? weapon.range
        var penetrationBudget = weapon.penetrationPower
        var surfacesCrossed = 0
        var alreadyHit = Set<PlayerID>()
        result.tracerEnd = origin + direction * remaining

        while remaining > 0.05 && surfacesCrossed <= maxPenetrations {
            let ray = Ray(origin: currentOrigin, direction: direction)
            let wallTrace = world.trace(from: currentOrigin,
                                        to: currentOrigin + direction * remaining,
                                        mask: [.bullets])
            let wallDistance = wallTrace.hit ? wallTrace.fraction * remaining : remaining

            // Closest player in front of the wall wins.
            var closestPlayer: (t: Float, hit: ShotHit)?
            for target in targets {
                guard target.player != shooter, target.isAlive else { continue }
                guard friendlyFire || target.team != shooterTeam || target.team == .none else { continue }
                guard !alreadyHit.contains(target.player) else { continue }
                guard let (t, hitbox) = target.raycast(ray, maxDistance: min(wallDistance, remaining)) else { continue }
                if closestPlayer == nil || t < closestPlayer!.t {
                    closestPlayer = (t, ShotHit(victim: target.player, hitbox: hitbox,
                                                position: ray.point(at: t),
                                                distance: origin.distance(to: ray.point(at: t)),
                                                penetratedSurfaces: surfacesCrossed))
                }
            }

            if let (t, hit) = closestPlayer {
                result.hits.append(hit)
                alreadyHit.insert(hit.victim)
                result.impacts.append(ShotImpact(position: hit.position, normal: -direction,
                                                 surface: .flesh, penetrated: false))
                // Bullets continue through bodies at a heavy cost (rewards lining enemies up).
                let bodyCost = SurfaceKind.flesh.penetrationCost
                penetrationBudget -= bodyCost
                if penetrationBudget <= 0 {
                    result.tracerEnd = hit.position
                    break
                }
                surfacesCrossed += 1
                let step = t + 0.6
                currentOrigin = ray.point(at: step)
                remaining -= step
                continue
            }

            guard wallTrace.hit else {
                result.tracerEnd = currentOrigin + direction * remaining
                break
            }

            // We hit geometry.
            let brush = world.brushes[wallTrace.brushIndex]
            let surface = wallTrace.surface
            result.impacts.append(ShotImpact(position: wallTrace.point, normal: wallTrace.normal,
                                             surface: surface,
                                             penetrated: penetrationBudget > surface.penetrationCost * brush.thickness))
            result.tracerEnd = wallTrace.point

            let cost = surface.penetrationCost * max(brush.thickness, 0.05)
            penetrationBudget -= cost
            if penetrationBudget <= 0 { break }

            surfacesCrossed += 1
            // Step past the brush and keep going.
            let exitPadding = brush.thickness + 0.08
            let advance = wallDistance + exitPadding
            guard advance < remaining else { break }
            currentOrigin = ray.point(at: advance)
            remaining -= advance
        }

        return result
    }

    /// Convenience for shotguns: fires `pelletsPerShot` bullets in one call.
    public static func fireSpread(origin: Vec3, direction: Vec3, spread: Float,
                                  weapon: WeaponData, shooter: PlayerID, shooterTeam: Team,
                                  friendlyFire: Bool, world: CollisionWorld, targets: [HitVolume],
                                  rng: inout DeterministicRandom) -> ShotResult {
        var combined = ShotResult()
        combined.tracerEnd = origin + direction * weapon.range
        for _ in 0..<max(1, weapon.pelletsPerShot) {
            let dir = RecoilSystem.spreadDirection(direction, spread: spread, rng: &rng)
            let r = fireBullet(origin: origin, direction: dir, weapon: weapon, shooter: shooter,
                               shooterTeam: shooterTeam, friendlyFire: friendlyFire,
                               world: world, targets: targets)
            combined.hits.append(contentsOf: r.hits)
            combined.impacts.append(contentsOf: r.impacts)
            combined.tracerEnd = r.tracerEnd
        }
        return combined
    }

    /// Melee uses a short sphere-cast-ish cone so back-stabs feel reliable on touch.
    public static func meleeSwing(origin: Vec3, direction: Vec3, weapon: WeaponData,
                                  shooter: PlayerID, shooterTeam: Team, friendlyFire: Bool,
                                  world: CollisionWorld, targets: [HitVolume]) -> ShotHit? {
        var best: (Float, ShotHit)?
        for target in targets {
            guard target.player != shooter, target.isAlive else { continue }
            guard friendlyFire || target.team != shooterTeam || target.team == .none else { continue }
            let centre = target.position + Vec3(0, 0.9 * target.crouchScale, 0)
            let distance = centre.distance(to: origin)
            guard distance <= weapon.range else { continue }
            guard Geometry.inCone(origin: origin, forward: direction,
                                  halfAngle: 0.6, target: centre) else { continue }
            guard world.hasLineOfSight(from: origin, to: centre) else { continue }
            // Behind the target = a much bigger hit.
            let hitbox: HitboxKind = distance < weapon.range * 0.6 ? .chest : .arm
            let hit = ShotHit(victim: target.player, hitbox: hitbox, position: centre,
                              distance: distance, penetratedSurfaces: 0)
            if best == nil || distance < best!.0 { best = (distance, hit) }
        }
        return best?.1
    }

    /// True when the attack came from behind — used for the melee back-stab bonus.
    public static func isBackstab(attackerPosition: Vec3, victimPosition: Vec3, victimYaw: Float) -> Bool {
        let victimForward = ViewAngles(pitch: 0, yaw: victimYaw).groundForward
        let toAttacker = (attackerPosition - victimPosition).flattened.normalized
        return victimForward.dot(toAttacker) < -0.25
    }
}
