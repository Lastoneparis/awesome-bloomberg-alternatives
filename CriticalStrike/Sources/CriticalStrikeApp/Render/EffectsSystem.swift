import Foundation
import QuartzCore
import SceneKit
import UIKit
import CriticalStrikeCore

/// Every transient visual in the world: muzzle flashes, tracers, impacts, decals, blood,
/// explosions, smoke volumes and fire.
///
/// Everything is pooled and budgeted. A firefight can easily ask for 40 effects a second,
/// and allocating SCNNodes at that rate is the fastest way to make a mobile game stutter,
/// so nodes are recycled and the oldest decals are retired once the quality budget is hit.
final class EffectsSystem {
    private let root: SCNNode
    private let materials: MaterialLibrary
    private var quality: GraphicsQuality

    private var tracerPool: [SCNNode] = []
    private var nextTracer = 0
    private var decals: [SCNNode] = []
    private var smokeVolumes: [EntityID: SCNNode] = [:]
    private var fireVolumes: [EntityID: SCNNode] = [:]
    private var grenadeNodes: [EntityID: SCNNode] = [:]

    private let tracerPoolSize = 24

    init(root: SCNNode, materials: MaterialLibrary, quality: GraphicsQuality) {
        self.root = root
        self.materials = materials
        self.quality = quality
        buildTracerPool()
    }

    func setQuality(_ quality: GraphicsQuality) {
        self.quality = quality
        trimDecals()
    }

    // MARK: - Muzzle flash

    /// Attached to the weapon's muzzle point so it tracks the gun through recoil.
    func muzzleFlash(at node: SCNNode, weapon: WeaponData) {
        let scale = CGFloat(weapon.muzzleFlashScale)
        let flash = SCNNode()

        // Core: a generated flash sprite, so the edge falls off instead of ending in a
        // hard square the way an untextured plane does.
        let plane = SCNPlane(width: 0.26 * scale, height: 0.26 * scale)
        plane.firstMaterial = materials.spriteMaterial(.muzzleCore,
                                                       tint: UIColor(hex: weapon.tracerColorHex))
        let planeNode = SCNNode(geometry: plane)
        planeNode.constraints = [SCNBillboardConstraint()]
        planeNode.eulerAngles.z = Float.random(in: 0...(2 * .pi))
        flash.addChildNode(planeNode)

        // Star flare, rotated randomly so consecutive shots never look identical.
        let flare = SCNPlane(width: 0.62 * scale, height: 0.62 * scale)
        flare.firstMaterial = materials.spriteMaterial(.muzzleStar,
                                                       tint: UIColor(hex: weapon.tracerColorHex))
        let flareNode = SCNNode(geometry: flare)
        flareNode.constraints = [SCNBillboardConstraint()]
        flareNode.eulerAngles.z = Float.random(in: 0...(2 * .pi))
        flareNode.opacity = CGFloat(0.6 + scale * 0.2)
        flash.addChildNode(flareNode)

        // A real light so the flash bounces off nearby geometry — the single biggest
        // "this looks like a real game" upgrade for the cost.
        if quality != .low {
            let light = SCNLight()
            light.type = .omni
            light.color = UIColor(hex: weapon.tracerColorHex)
            light.intensity = 1400 * scale
            light.attenuationEndDistance = 7
            let lightNode = SCNNode()
            lightNode.light = light
            flash.addChildNode(lightNode)
        }

        node.addChildNode(flash)
        flash.runAction(.sequence([
            .group([.scale(to: 1.35, duration: 0.03), .fadeOpacity(to: 1, duration: 0.01)]),
            .fadeOut(duration: 0.05),
            .removeFromParentNode()
        ]))
    }

    /// Ejected casing that bounces once and fades. Purely cosmetic, but its absence is
    /// noticeable.
    func ejectShell(from node: SCNNode, weapon: WeaponData) {
        guard quality != .low, weapon.weaponClass != .melee else { return }
        let shell = SCNNode(geometry: SCNCylinder(radius: 0.005, height: 0.018))
        shell.geometry?.firstMaterial = materials.partMaterial(
            for: .metal, tint: UIColor(hex: 0xC9A227))
        shell.worldPosition = node.presentation.worldPosition
        shell.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        root.addChildNode(shell)

        let right = node.presentation.worldRight
        let velocity = SCNVector3(right.x * 1.6 + Float.random(in: -0.3...0.3),
                                  1.4 + Float.random(in: -0.2...0.4),
                                  right.z * 1.6 + Float.random(in: -0.3...0.3))
        let body = SCNPhysicsBody(type: .dynamic,
                                  shape: SCNPhysicsShape(geometry: shell.geometry!, options: nil))
        body.mass = 0.01
        body.restitution = 0.35
        body.categoryBitMask = PhysicsCategory.projectile
        body.collisionBitMask = PhysicsCategory.world
        shell.physicsBody = body
        shell.physicsBody?.applyForce(velocity, asImpulse: true)
        shell.runAction(.sequence([.wait(duration: 2.5), .fadeOut(duration: 0.4), .removeFromParentNode()]))
    }

    // MARK: - Tracers

    private func buildTracerPool() {
        for _ in 0..<tracerPoolSize {
            // A quad whose local +Y runs along the beam. `freeAxes: .Y` then spins it
            // about the beam to face the camera, which is how every engine draws a
            // tracer — a solid box reads as a stick from the side and vanishes head on.
            let plane = SCNPlane(width: 0.05, height: 1)
            let node = SCNNode(geometry: plane)
            let billboard = SCNBillboardConstraint()
            billboard.freeAxes = .Y
            node.constraints = [billboard]
            node.isHidden = true
            node.castsShadow = false
            root.addChildNode(node)
            tracerPool.append(node)
        }
    }

    /// Bullets are hitscan, but a visible streak is what lets players read where fire is
    /// coming from — so every shot draws one, stretched between muzzle and impact.
    func tracer(from: Vec3, to: Vec3, weapon: WeaponData, isLocalPlayer: Bool) {
        let distance = from.distance(to: to)
        guard distance > 0.5 else { return }
        let node = tracerPool[nextTracer % tracerPool.count]
        nextTracer += 1
        node.removeAllActions()

        node.geometry?.firstMaterial = materials.spriteMaterial(
            .tracerSegment, tint: UIColor(hex: weapon.tracerColorHex))
        // The quad is 1m tall, so scaling Y by the distance stretches it along the beam.
        node.scale = SCNVector3(isLocalPlayer ? 0.7 : 1.0, distance, 1)
        let midpoint = from.lerp(to, 0.5)
        node.position = SCNVector3(midpoint.x, midpoint.y, midpoint.z)
        node.look(at: SCNVector3(to.x, to.y, to.z), up: SCNVector3(0, 1, 0),
                  localFront: SCNVector3(0, 1, 0))
        node.isHidden = false
        node.opacity = isLocalPlayer ? 0.75 : 1

        node.runAction(.sequence([
            .fadeOpacity(to: 0, duration: isLocalPlayer ? 0.045 : 0.08),
            .run { $0.isHidden = true }
        ]))
    }

    // MARK: - Impacts

    func bulletImpact(position: Vec3, normal: Vec3, surface: SurfaceKind, penetrated: Bool) {
        spawnImpactParticles(position: position, normal: normal, surface: surface)
        if !penetrated { spawnDecal(position: position, normal: normal, surface: surface) }
        if surface.breaksOnHit { spawnGlassShards(position: position, normal: normal) }
    }

    private func spawnImpactParticles(position: Vec3, normal: Vec3, surface: SurfaceKind) {
        guard quality != .low else { return }
        let system = SCNParticleSystem()
        system.birthRate = CGFloat(quality == .ultra ? 40 : 22)
        system.emissionDuration = 0.02
        system.loops = false
        system.particleLifeSpan = 0.45
        system.particleLifeSpanVariation = 0.25
        system.particleVelocity = 3.2
        system.particleVelocityVariation = 2.0
        system.spreadingAngle = 42
        system.particleSize = 0.018
        system.particleSizeVariation = 0.012
        system.acceleration = SCNVector3(0, -8, 0)
        system.particleColor = impactColor(for: surface)
        system.particleColorVariation = SCNVector4(0.05, 0.05, 0.05, 0)
        system.blendMode = surface == .flesh ? .alpha : .additive
        system.isAffectedByGravity = true
        system.particleImage = materials.spriteImage(surface == .flesh ? .bloodDroplet : .spark)

        let node = SCNNode()
        node.position = SCNVector3(position.x, position.y, position.z)
        node.look(at: SCNVector3(position.x + normal.x, position.y + normal.y, position.z + normal.z))
        node.addParticleSystem(system)
        root.addChildNode(node)
        node.runAction(.sequence([.wait(duration: 1.2), .removeFromParentNode()]))

        // Dust puff for hard surfaces.
        if surface != .flesh && quality != .medium {
            let dust = SCNParticleSystem()
            dust.birthRate = 8
            dust.emissionDuration = 0.05
            dust.loops = false
            dust.particleLifeSpan = 0.9
            dust.particleVelocity = 0.6
            dust.spreadingAngle = 80
            dust.particleSize = 0.09
            dust.particleSizeVariation = 0.05
            dust.particleColor = impactColor(for: surface).withAlphaComponent(0.35)
            dust.blendMode = .alpha
            dust.particleImage = materials.spriteImage(.dustPuff)
            node.addParticleSystem(dust)
        }
    }

    private func impactColor(for surface: SurfaceKind) -> UIColor {
        switch surface {
        case .flesh: return UIColor(hex: 0xA81E20)
        case .metal: return UIColor(hex: 0xFFD27F)
        case .wood: return UIColor(hex: 0x8A6238)
        case .glass: return UIColor(hex: 0xBFE0EA)
        case .sand, .dirt: return UIColor(hex: 0xC8AE7D)
        case .grass: return UIColor(hex: 0x5E7F45)
        case .water: return UIColor(hex: 0x7FB6D8)
        default: return UIColor(hex: 0xB8B4AC)
        }
    }

    private func spawnDecal(position: Vec3, normal: Vec3, surface: SurfaceKind) {
        guard quality.maxDecals > 0, surface != .flesh, surface != .water else { return }
        let size = CGFloat.random(in: 0.08...0.14)
        let plane = SCNPlane(width: size, height: size)
        plane.firstMaterial = materials.decalMaterial(surface: surface)
        let node = SCNNode(geometry: plane)
        // Offset along the normal so the decal never z-fights with the wall.
        let offset = position + normal * 0.006
        node.position = SCNVector3(offset.x, offset.y, offset.z)
        node.look(at: SCNVector3(offset.x + normal.x, offset.y + normal.y, offset.z + normal.z))
        node.eulerAngles.z = Float.random(in: 0...(2 * .pi))
        node.castsShadow = false
        node.renderingOrder = 10
        root.addChildNode(node)
        decals.append(node)
        trimDecals()
    }

    private func trimDecals() {
        let budget = quality.maxDecals
        while decals.count > budget {
            let oldest = decals.removeFirst()
            oldest.runAction(.sequence([.fadeOut(duration: 0.3), .removeFromParentNode()]))
        }
    }

    private func spawnGlassShards(position: Vec3, normal: Vec3) {
        guard quality != .low else { return }
        let system = SCNParticleSystem()
        system.birthRate = 30
        system.emissionDuration = 0.05
        system.loops = false
        system.particleLifeSpan = 1.4
        system.particleVelocity = 2.4
        system.particleVelocityVariation = 1.6
        system.spreadingAngle = 55
        system.particleSize = 0.03
        system.particleColor = UIColor(hex: 0xBFE0EA, alpha: 0.85)
        system.isAffectedByGravity = true
        system.blendMode = .alpha
        system.particleImage = materials.spriteImage(.glowDot)
        let node = SCNNode()
        node.position = SCNVector3(position.x, position.y, position.z)
        node.look(at: SCNVector3(position.x + normal.x, position.y + normal.y, position.z + normal.z))
        node.addParticleSystem(system)
        root.addChildNode(node)
        node.runAction(.sequence([.wait(duration: 2), .removeFromParentNode()]))
    }

    func bloodSpray(position: Vec3, direction: Vec3, amount: Float, showBlood: Bool) {
        guard showBlood, quality != .low else { return }
        let system = SCNParticleSystem()
        system.birthRate = CGFloat(18 + amount * 0.5)
        system.emissionDuration = 0.04
        system.loops = false
        system.particleLifeSpan = 0.6
        system.particleVelocity = 2.6
        system.particleVelocityVariation = 1.8
        system.spreadingAngle = 38
        system.particleSize = 0.024
        system.particleColor = UIColor(hex: 0x8E1519)
        system.isAffectedByGravity = true
        system.blendMode = .alpha
        system.particleImage = materials.spriteImage(.bloodDroplet)

        let node = SCNNode()
        node.position = SCNVector3(position.x, position.y, position.z)
        node.look(at: SCNVector3(position.x + direction.x, position.y + direction.y,
                                 position.z + direction.z))
        node.addParticleSystem(system)
        root.addChildNode(node)
        node.runAction(.sequence([.wait(duration: 1.2), .removeFromParentNode()]))
    }

    // MARK: - Grenades

    func spawnGrenade(entity: EntityID, kind: GrenadeKind, position: Vec3) {
        let node = SCNNode(geometry: SCNSphere(radius: 0.055))
        let color: UInt32
        switch kind {
        case .frag, .impact: color = 0x3E4A32
        case .flash, .stun: color = 0xC9CBD0
        case .smoke: color = 0x5A6472
        case .molotov: color = 0xB05A22
        case .decoy: color = 0x7A6A9A
        }
        // A thrown grenade travels, so it takes the part material: world-space variation
        // on a moving object shifts its tone as it flies.
        node.geometry?.firstMaterial = materials.partMaterial(for: .metal,
                                                              tint: UIColor(hex: color))
        node.position = SCNVector3(position.x, position.y, position.z)

        // Blinking fuse light so a live grenade at your feet is unmissable.
        if kind == .frag || kind == .impact {
            let indicator = SCNNode(geometry: SCNSphere(radius: 0.02))
            indicator.geometry?.firstMaterial = materials.emissiveMaterial(color: .red, intensity: 1)
            indicator.position = SCNVector3(0, 0.05, 0)
            indicator.runAction(.repeatForever(.sequence([
                .fadeOpacity(to: 0.15, duration: 0.18),
                .fadeOpacity(to: 1, duration: 0.18)
            ])))
            node.addChildNode(indicator)
        }
        root.addChildNode(node)
        grenadeNodes[entity] = node
    }

    func updateGrenade(entity: EntityID, position: Vec3) {
        grenadeNodes[entity]?.position = SCNVector3(position.x, position.y, position.z)
    }

    func removeGrenade(entity: EntityID) {
        grenadeNodes[entity]?.removeFromParentNode()
        grenadeNodes[entity] = nil
    }

    // MARK: - Explosions

    func explosion(position: Vec3, radius: Float, kind: GrenadeKind) {
        removeGrenadeIfPresent(at: position)

        let node = SCNNode()
        node.position = SCNVector3(position.x, position.y, position.z)
        root.addChildNode(node)

        // Flash of light.
        let light = SCNLight()
        light.type = .omni
        light.color = kind == .flash ? UIColor.white : UIColor(hex: 0xFFB05A)
        light.intensity = 6000
        light.attenuationEndDistance = CGFloat(radius * 2.5)
        let lightNode = SCNNode()
        lightNode.light = light
        node.addChildNode(lightNode)
        lightNode.runAction(.sequence([
            .customAction(duration: 0.35) { n, elapsed in
                n.light?.intensity = 6000 * (1 - CGFloat(elapsed / 0.35))
            },
            .removeFromParentNode()
        ]))

        guard kind != .flash && kind != .smoke else {
            node.runAction(.sequence([.wait(duration: 0.5), .removeFromParentNode()]))
            return
        }

        // Fireball.
        let fire = SCNParticleSystem()
        fire.birthRate = CGFloat(quality == .low ? 60 : 220)
        fire.emissionDuration = 0.08
        fire.loops = false
        fire.particleLifeSpan = 0.7
        fire.particleLifeSpanVariation = 0.3
        fire.particleVelocity = CGFloat(radius * 2.2)
        fire.particleVelocityVariation = CGFloat(radius)
        fire.spreadingAngle = 180
        fire.particleSize = CGFloat(radius * 0.18)
        fire.particleSizeVariation = CGFloat(radius * 0.1)
        fire.particleColor = UIColor(hex: 0xFF8A2B)
        fire.particleColorVariation = SCNVector4(0.1, 0.1, 0, 0)
        fire.blendMode = .additive
        fire.isAffectedByGravity = false
        fire.particleImage = materials.spriteImage(.ember)
        node.addParticleSystem(fire)

        // Smoke that lingers after the fireball.
        let smoke = SCNParticleSystem()
        smoke.birthRate = CGFloat(quality == .low ? 20 : 70)
        smoke.emissionDuration = 0.25
        smoke.loops = false
        smoke.particleLifeSpan = 2.4
        smoke.particleVelocity = CGFloat(radius * 0.6)
        smoke.spreadingAngle = 160
        smoke.particleSize = CGFloat(radius * 0.35)
        smoke.particleSizeVariation = CGFloat(radius * 0.15)
        smoke.particleColor = UIColor(white: 0.22, alpha: 0.55)
        smoke.blendMode = .alpha
        smoke.acceleration = SCNVector3(0, 1.1, 0)
        smoke.particleImage = materials.spriteImage(.smokePuff)
        smoke.sortingMode = .distance
        node.addParticleSystem(smoke)

        // Debris.
        if quality != .low {
            let debris = SCNParticleSystem()
            debris.birthRate = 45
            debris.emissionDuration = 0.05
            debris.loops = false
            debris.particleLifeSpan = 1.6
            debris.particleVelocity = CGFloat(radius * 2.8)
            debris.particleVelocityVariation = CGFloat(radius)
            debris.spreadingAngle = 180
            debris.particleSize = 0.03
            debris.particleColor = UIColor(hex: 0x6B6157)
            debris.isAffectedByGravity = true
            debris.particleImage = materials.spriteImage(.dustPuff)
            node.addParticleSystem(debris)
        }

        node.runAction(.sequence([.wait(duration: 3.2), .removeFromParentNode()]))
    }

    private func removeGrenadeIfPresent(at position: Vec3) {
        for (entity, node) in grenadeNodes {
            let p = Vec3(node.position.x, node.position.y, node.position.z)
            if p.distance(to: position) < 1.0 {
                node.removeFromParentNode()
                grenadeNodes[entity] = nil
            }
        }
    }

    // MARK: - Volumes

    /// Smoke has to be a real volume, not a billboard: players hide inside it, and the
    /// simulation already treats it as vision-blocking, so the visual must agree.
    func startSmoke(entity: EntityID, position: Vec3, radius: Float, duration: Float) {
        let node = SCNNode()
        node.position = SCNVector3(position.x, position.y + radius * 0.35, position.z)

        let system = SCNParticleSystem()
        system.birthRate = CGFloat(quality == .low ? 30 : 110)
        system.emissionDuration = CGFloat(duration * 0.85)
        system.loops = false
        system.particleLifeSpan = 4.5
        system.particleLifeSpanVariation = 1.5
        system.particleVelocity = 0.35
        system.particleVelocityVariation = 0.3
        system.spreadingAngle = 180
        system.emitterShape = SCNSphere(radius: CGFloat(radius * 0.7))
        system.birthLocation = .volume
        system.particleSize = CGFloat(radius * 0.55)
        system.particleSizeVariation = CGFloat(radius * 0.2)
        system.particleColor = UIColor(white: 0.78, alpha: 0.75)
        system.blendMode = .alpha
        system.sortingMode = .distance
        system.acceleration = SCNVector3(0, 0.08, 0)
        system.particleImage = materials.spriteImage(.smokePuff)
        // Rotating puffs stop the cloud reading as a cluster of identical billboards.
        system.particleAngleVariation = 180
        system.particleAngularVelocity = 12
        system.particleAngularVelocityVariation = 24
        // Opacity over a particle's lifetime is a property controller, not a scalar: this
        // ramps each puff in and back out so the cloud neither pops nor ends abruptly.
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0.0, 0.9, 0.9, 0.0]
        opacity.keyTimes = [0.0, 0.12, 0.75, 1.0]
        opacity.duration = 1
        let controller = SCNParticlePropertyController(animation: opacity)
        system.propertyControllers = [.opacity: controller]
        node.addParticleSystem(system)

        root.addChildNode(node)
        smokeVolumes[entity] = node
        node.runAction(.sequence([
            .wait(duration: TimeInterval(duration)),
            .fadeOut(duration: 1.2),
            .removeFromParentNode()
        ]))
    }

    func startFire(entity: EntityID, position: Vec3, radius: Float, duration: Float) {
        let node = SCNNode()
        node.position = SCNVector3(position.x, position.y + 0.1, position.z)

        let system = SCNParticleSystem()
        system.birthRate = CGFloat(quality == .low ? 40 : 150)
        system.emissionDuration = CGFloat(duration)
        system.loops = false
        system.particleLifeSpan = 1.1
        system.particleVelocity = 1.6
        system.spreadingAngle = 25
        system.emitterShape = SCNCylinder(radius: CGFloat(radius), height: 0.1)
        system.birthLocation = .volume
        system.particleSize = CGFloat(radius * 0.3)
        system.particleColor = UIColor(hex: 0xFF7A1F)
        system.particleColorVariation = SCNVector4(0.08, 0.15, 0, 0)
        system.blendMode = .additive
        system.acceleration = SCNVector3(0, 2.2, 0)
        system.particleImage = materials.spriteImage(.ember)
        system.particleAngleVariation = 180
        system.particleAngularVelocity = 30
        node.addParticleSystem(system)

        let light = SCNLight()
        light.type = .omni
        light.color = UIColor(hex: 0xFF8A3A)
        light.intensity = 900
        light.attenuationEndDistance = CGFloat(radius * 3)
        let lightNode = SCNNode()
        lightNode.light = light
        // Flicker — a static fire light looks wrong immediately.
        lightNode.runAction(.repeatForever(.sequence([
            .customAction(duration: 0.12) { n, _ in n.light?.intensity = CGFloat.random(in: 600...1100) },
            .wait(duration: 0.06)
        ])))
        node.addChildNode(lightNode)

        root.addChildNode(node)
        fireVolumes[entity] = node
        node.runAction(.sequence([
            .wait(duration: TimeInterval(duration)),
            .fadeOut(duration: 0.8),
            .removeFromParentNode()
        ]))
    }

    func removeVolume(entity: EntityID) {
        smokeVolumes[entity]?.removeFromParentNode()
        smokeVolumes[entity] = nil
        fireVolumes[entity]?.removeFromParentNode()
        fireVolumes[entity] = nil
    }

    // MARK: - Bookkeeping

    func reset() {
        for node in decals { node.removeFromParentNode() }
        decals.removeAll()
        for (_, node) in smokeVolumes { node.removeFromParentNode() }
        smokeVolumes.removeAll()
        for (_, node) in fireVolumes { node.removeFromParentNode() }
        fireVolumes.removeAll()
        for (_, node) in grenadeNodes { node.removeFromParentNode() }
        grenadeNodes.removeAll()
    }
}

extension SCNNode {
    /// World-space right vector, used for shell ejection.
    var worldRight: SCNVector3 {
        let transform = worldTransform
        return SCNVector3(transform.m11, transform.m12, transform.m13)
    }
}
