import Foundation

public struct Projectile: Sendable {
    public var entity: EntityID
    public var owner: PlayerID
    public var team: Team
    public var grenadeID: ContentID
    public var kind: GrenadeKind
    public var position: Vec3
    public var velocity: Vec3
    public var fuse: Countdown
    public var bounces: Int
    public var stuck: Bool

    public var data: GrenadeData { GrenadeDatabase.grenade(grenadeID) ?? GrenadeDatabase.grenade(kind: kind) }
}

/// A lingering area effect left behind by a grenade (smoke cloud, fire pool, decoy).
public struct AreaEffect: Sendable {
    public var entity: EntityID
    public var owner: PlayerID
    public var team: Team
    public var kind: GrenadeKind
    public var position: Vec3
    public var radius: Float
    public var timer: Countdown
    public var lastTickDamage: Float

    public var blocksVision: Bool { kind == .smoke }
    public var burns: Bool { kind == .molotov }

    public func contains(_ p: Vec3) -> Bool {
        let d = p - position
        // Smoke and fire are squat cylinders, not spheres.
        return d.flattened.lengthSquared <= radius * radius && d.y > -1.5 && d.y < radius * 0.9
    }
}

/// What a detonation wants the match to do. The projectile system never touches players.
public struct ExplosionEvent: Sendable {
    public var entity: EntityID
    public var owner: PlayerID
    public var team: Team
    public var kind: GrenadeKind
    public var position: Vec3
    public var data: GrenadeData
}

public final class ProjectileSystem {
    public private(set) var projectiles: [Projectile] = []
    public private(set) var areaEffects: [AreaEffect] = []
    private var nextEntityRaw: UInt16 = 1000

    public init() {}

    private func allocateEntity() -> EntityID {
        nextEntityRaw = nextEntityRaw &+ 1
        if nextEntityRaw < 1000 { nextEntityRaw = 1000 }
        return EntityID(rawValue: nextEntityRaw)
    }

    public func reset() {
        projectiles.removeAll(keepingCapacity: true)
        areaEffects.removeAll(keepingCapacity: true)
    }

    @discardableResult
    public func spawn(owner: PlayerID, team: Team, grenadeID: ContentID, kind: GrenadeKind,
                      origin: Vec3, velocity: Vec3, events: EventBus) -> EntityID {
        let data = GrenadeDatabase.grenade(grenadeID) ?? GrenadeDatabase.grenade(kind: kind)
        let entity = allocateEntity()
        var fuse = Countdown()
        fuse.start(data.fuseTime)
        projectiles.append(Projectile(entity: entity, owner: owner, team: team,
                                      grenadeID: grenadeID, kind: kind, position: origin,
                                      velocity: velocity, fuse: fuse, bounces: 0, stuck: false))
        events.emit(.grenadeThrown(player: owner, kind: kind, entity: entity,
                                   origin: origin, velocity: velocity))
        return entity
    }

    /// Integrates projectiles and returns the detonations for the match to resolve.
    public func step(dt: Float, world: CollisionWorld, events: EventBus) -> [ExplosionEvent] {
        var explosions: [ExplosionEvent] = []
        var survivors: [Projectile] = []
        survivors.reserveCapacity(projectiles.count)

        for stored in projectiles {
            var p = stored
            let data = p.data
            var detonate = false

            if !p.stuck {
                p.velocity.y -= MovementSystem.gravity * dt * 0.85   // grenades feel better slightly floaty
                let delta = p.velocity * dt
                let trace = world.trace(from: p.position, to: p.position + delta, mask: .solid)
                if trace.hit {
                    let contact = trace.point + trace.normal * 0.06
                    if data.detonateOnImpact {
                        p.position = contact
                        detonate = true
                    } else {
                        p.position = contact
                        let into = p.velocity.dot(trace.normal)
                        p.velocity = (p.velocity - trace.normal * (2 * into)) * data.bounciness
                        // Tangential friction so grenades stop rolling forever.
                        let normalComponent = trace.normal * p.velocity.dot(trace.normal)
                        let tangent = p.velocity - normalComponent
                        p.velocity = normalComponent + tangent * (1 - data.friction * 0.5)
                        p.bounces += 1
                        if p.velocity.lengthSquared < 0.35 && trace.normal.y > 0.6 {
                            p.velocity = .zero
                            p.stuck = true
                        }
                        events.emit(.grenadeBounced(entity: p.entity, position: contact,
                                                    surface: trace.surface))
                    }
                } else {
                    p.position += delta
                }
            }

            if p.fuse.tick(dt) { detonate = true }

            if detonate {
                events.emit(.grenadeDetonated(entity: p.entity, kind: p.kind, position: p.position))
                explosions.append(ExplosionEvent(entity: p.entity, owner: p.owner, team: p.team,
                                                 kind: p.kind, position: p.position, data: data))
                spawnAreaEffect(for: p, data: data, events: events)
            } else {
                survivors.append(p)
            }
        }
        projectiles = survivors
        stepAreaEffects(dt: dt)
        return explosions
    }

    private func spawnAreaEffect(for p: Projectile, data: GrenadeData, events: EventBus) {
        guard data.effectDuration > 0, data.effectRadius > 0 else { return }
        switch p.kind {
        case .smoke:
            var timer = Countdown(); timer.start(data.effectDuration)
            areaEffects.append(AreaEffect(entity: p.entity, owner: p.owner, team: p.team,
                                          kind: .smoke, position: p.position,
                                          radius: data.effectRadius, timer: timer, lastTickDamage: 0))
            events.emit(.smokeStarted(entity: p.entity, position: p.position,
                                      radius: data.effectRadius, duration: data.effectDuration))
        case .molotov:
            var timer = Countdown(); timer.start(data.effectDuration)
            areaEffects.append(AreaEffect(entity: p.entity, owner: p.owner, team: p.team,
                                          kind: .molotov, position: p.position,
                                          radius: data.effectRadius, timer: timer, lastTickDamage: 0))
            events.emit(.fireStarted(entity: p.entity, position: p.position,
                                     radius: data.effectRadius, duration: data.effectDuration))
        case .decoy:
            var timer = Countdown(); timer.start(data.effectDuration)
            areaEffects.append(AreaEffect(entity: p.entity, owner: p.owner, team: p.team,
                                          kind: .decoy, position: p.position,
                                          radius: data.effectRadius, timer: timer, lastTickDamage: 0))
        default:
            break
        }
    }

    private func stepAreaEffects(dt: Float) {
        var survivors: [AreaEffect] = []
        survivors.reserveCapacity(areaEffects.count)
        for stored in areaEffects {
            var e = stored
            e.lastTickDamage = max(0, e.lastTickDamage - dt)
            if !e.timer.tick(dt) { survivors.append(e) }
        }
        areaEffects = survivors
    }

    /// True when a sightline passes through any smoke cloud.
    public func smokeBlocks(from: Vec3, to: Vec3) -> Bool {
        for e in areaEffects where e.blocksVision {
            if Geometry.distancePointToSegment(e.position + Vec3(0, e.radius * 0.4, 0), from, to)
                < e.radius * 0.85 {
                return true
            }
        }
        return false
    }

    public func fires(overlapping p: Vec3) -> [AreaEffect] {
        areaEffects.filter { $0.burns && $0.contains(p) }
    }

    public func isInSmoke(_ p: Vec3) -> Bool {
        areaEffects.contains { $0.blocksVision && $0.contains(p) }
    }

    /// Decoys fake gunfire to pull bots and players; the AI treats these as noise sources.
    public func decoyNoiseSources() -> [(position: Vec3, team: Team)] {
        areaEffects.filter { $0.kind == .decoy }.map { ($0.position, $0.team) }
    }

    public func removeEffects(ownedBy player: PlayerID) {
        areaEffects.removeAll { $0.owner == player && $0.kind == .decoy }
    }
}
