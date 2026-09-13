import Foundation
import SceneKit
import UIKit
import CriticalStrikeCore

/// A remote player's body.
///
/// The character is assembled from primitives and animated procedurally: there are no
/// rigged assets, so limb motion is driven by the player's own velocity and stance. That
/// keeps the download small and — more importantly for a shooter — makes the visual pose
/// derive directly from the same state the hitboxes use, so what you see is what you hit.
final class CharacterNode {
    let root = SCNNode()
    let id: PlayerID

    private let bodyNode = SCNNode()
    private let headNode = SCNNode()
    private let leftArm = SCNNode()
    private let rightArm = SCNNode()
    private let leftLeg = SCNNode()
    private let rightLeg = SCNNode()
    private let weaponNode = SCNNode()
    private let nameplate = SCNNode()
    private let outlineNode = SCNNode()

    private var walkCycle: Float = 0
    private var currentStance: Stance = .standing
    private var team: Team = .none
    private var isRagdoll = false

    init(id: PlayerID, team: Team, materials: MaterialLibrary, colorBlind: ColorBlindMode,
         showNameplate: Bool, name: String) {
        self.id = id
        self.team = team
        root.name = "player_\(id.rawValue)"

        let bodyMaterial = materials.characterMaterial(team: team, colorBlind: colorBlind)
        let accentMaterial = materials.characterMaterial(team: team, colorBlind: colorBlind, accent: true)

        // Torso
        let torso = SCNBox(width: 0.52, height: 0.68, length: 0.32, chamferRadius: 0.08)
        torso.firstMaterial = bodyMaterial
        bodyNode.geometry = torso
        bodyNode.position = SCNVector3(0, 1.1, 0)
        root.addChildNode(bodyNode)

        // Chest rig — the accent colour, so teams read instantly at distance.
        let rig = SCNBox(width: 0.46, height: 0.28, length: 0.36, chamferRadius: 0.05)
        rig.firstMaterial = accentMaterial
        let rigNode = SCNNode(geometry: rig)
        rigNode.position = SCNVector3(0, 0.12, 0)
        bodyNode.addChildNode(rigNode)

        // Head + helmet
        let head = SCNBox(width: 0.26, height: 0.26, length: 0.26, chamferRadius: 0.08)
        head.firstMaterial = bodyMaterial
        headNode.geometry = head
        headNode.position = SCNVector3(0, 1.68, 0)
        root.addChildNode(headNode)

        let visor = SCNBox(width: 0.2, height: 0.08, length: 0.04, chamferRadius: 0.02)
        visor.firstMaterial = materials.emissiveMaterial(
            color: UIColor(hex: colorBlind.teamColor(team)), intensity: 0.5)
        let visorNode = SCNNode(geometry: visor)
        visorNode.position = SCNVector3(0, 0.01, -0.14)
        headNode.addChildNode(visorNode)

        // Limbs. Pivots sit at the joint so rotation looks like a swing, not a slide.
        func limb(width: CGFloat, height: CGFloat, at position: SCNVector3,
                  material: SCNMaterial) -> SCNNode {
            let geometry = SCNBox(width: width, height: height, length: width, chamferRadius: 0.05)
            geometry.firstMaterial = material
            let node = SCNNode(geometry: geometry)
            node.pivot = SCNMatrix4MakeTranslation(0, Float(height / 2), 0)
            node.position = position
            return node
        }

        let arm = limb(width: 0.17, height: 0.6, at: SCNVector3(-0.35, 1.44, 0), material: bodyMaterial)
        leftArm.addChildNode(arm)
        leftArm.position = SCNVector3(0, 0, 0)
        root.addChildNode(leftArm)

        let arm2 = limb(width: 0.17, height: 0.6, at: SCNVector3(0.35, 1.44, 0), material: bodyMaterial)
        rightArm.addChildNode(arm2)
        root.addChildNode(rightArm)

        let leg = limb(width: 0.2, height: 0.78, at: SCNVector3(-0.15, 0.78, 0), material: bodyMaterial)
        leftLeg.addChildNode(leg)
        root.addChildNode(leftLeg)

        let leg2 = limb(width: 0.2, height: 0.78, at: SCNVector3(0.15, 0.78, 0), material: bodyMaterial)
        rightLeg.addChildNode(leg2)
        root.addChildNode(rightLeg)

        // Weapon held in the right hand.
        weaponNode.position = SCNVector3(0.28, 1.28, -0.34)
        root.addChildNode(weaponNode)

        // Team outline: a slightly larger, back-face-only shell. This is what makes a
        // teammate readable against a busy background without a wallhack-style overlay.
        let outline = SCNBox(width: 0.58, height: 1.76, length: 0.4, chamferRadius: 0.12)
        let outlineMaterial = SCNMaterial()
        outlineMaterial.lightingModel = .constant
        outlineMaterial.diffuse.contents = UIColor(hex: colorBlind.teamColor(team)).withAlphaComponent(0.22)
        outlineMaterial.cullMode = .front
        outlineMaterial.writesToDepthBuffer = false
        outline.firstMaterial = outlineMaterial
        outlineNode.geometry = outline
        outlineNode.position = SCNVector3(0, 0.9, 0)
        outlineNode.isHidden = true
        root.addChildNode(outlineNode)

        if showNameplate {
            buildNameplate(name: name, colorBlind: colorBlind)
        }
    }

    private func buildNameplate(name: String, colorBlind: ColorBlindMode) {
        let text = SCNText(string: name, extrusionDepth: 0)
        text.font = UIFont.systemFont(ofSize: 3, weight: .bold)
        text.flatness = 0.1
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor(hex: colorBlind.teamColor(team))
        material.writesToDepthBuffer = false
        // Drawn after the world so a teammate's name is never buried inside geometry.
        material.readsFromDepthBuffer = false
        text.firstMaterial = material

        let textNode = SCNNode(geometry: text)
        let (minBounds, maxBounds) = text.boundingBox
        textNode.pivot = SCNMatrix4MakeTranslation((maxBounds.x - minBounds.x) / 2 + minBounds.x, 0, 0)
        textNode.scale = SCNVector3(0.045, 0.045, 0.045)
        nameplate.addChildNode(textNode)
        nameplate.position = SCNVector3(0, 2.05, 0)
        nameplate.constraints = [SCNBillboardConstraint()]
        nameplate.renderingOrder = 100
        root.addChildNode(nameplate)
    }

    // MARK: - Per-frame update

    func apply(snapshot: PlayerSnapshot, localTeam: Team, deltaTime: Float,
               weaponModel: SCNNode?) {
        guard !isRagdoll else { return }
        root.isHidden = !snapshot.isAlive
        guard snapshot.isAlive else { return }

        root.position = SCNVector3(snapshot.position.x, snapshot.position.y, snapshot.position.z)
        root.eulerAngles = SCNVector3(0, snapshot.yaw, 0)

        // Stance: crouching squashes the whole body rather than re-posing it, which is
        // exactly what the crouch hitbox scale does.
        let targetScale = snapshot.stance.heightScale
        let currentScale = root.scale.y
        let smoothed = MathUtil.damp(currentScale, targetScale, halfLife: 0.06, dt: deltaTime)
        root.scale = SCNVector3(1, smoothed, 1)

        // Head tracks pitch so you can tell where someone is looking.
        headNode.eulerAngles = SCNVector3(-snapshot.pitch * 0.7, 0, 0)

        // Walk cycle driven by actual horizontal speed.
        let speed = snapshot.velocity.horizontalLength
        let cadence = MathUtil.clamp(speed / MovementSystem.runSpeed, 0, 1.6)
        walkCycle += deltaTime * cadence * 9
        let swing = sin(walkCycle) * 0.5 * cadence
        leftLeg.eulerAngles = SCNVector3(swing, 0, 0)
        rightLeg.eulerAngles = SCNVector3(-swing, 0, 0)
        leftArm.eulerAngles = SCNVector3(-swing * 0.55, 0, 0)

        // The gun arm points down the aim direction instead of swinging.
        rightArm.eulerAngles = SCNVector3(-snapshot.pitch - 1.35, 0, 0)
        weaponNode.eulerAngles = SCNVector3(-snapshot.pitch, 0, 0)
        if snapshot.isAiming {
            weaponNode.position = SCNVector3(0.06, 1.44, -0.4)
        } else {
            weaponNode.position = SCNVector3(0.28, 1.28, -0.34)
        }

        // Teammates get the outline and the nameplate; enemies get neither.
        let isTeammate = localTeam != .none && snapshot.team == localTeam
        outlineNode.isHidden = !isTeammate
        nameplate.isHidden = !isTeammate

        if let weaponModel, weaponNode.childNodes.first?.name != weaponModel.name {
            weaponNode.childNodes.forEach { $0.removeFromParentNode() }
            weaponNode.addChildNode(weaponModel)
        }
    }

    // MARK: - Death

    /// Converts the character into a physics-driven ragdoll. Cheaper and far more robust
    /// than a jointed ragdoll: one dynamic body carrying the whole mesh, launched along
    /// the killing blow.
    func playDeath(impulse: Vec3, quality: GraphicsQuality) {
        guard !isRagdoll else { return }
        isRagdoll = true
        nameplate.isHidden = true
        outlineNode.isHidden = true

        guard quality.ragdollsEnabled else {
            root.runAction(.sequence([
                .wait(duration: 0.2),
                .fadeOut(duration: 0.6),
                .removeFromParentNode()
            ]))
            return
        }

        let shape = SCNPhysicsShape(geometry: SCNBox(width: 0.5, height: 1.7, length: 0.4,
                                                     chamferRadius: 0.1), options: nil)
        let body = SCNPhysicsBody(type: .dynamic, shape: shape)
        body.mass = 70
        body.friction = 0.7
        body.restitution = 0.05
        body.angularDamping = 0.4
        body.categoryBitMask = PhysicsCategory.ragdoll
        body.collisionBitMask = PhysicsCategory.world
        body.contactTestBitMask = 0
        root.physicsBody = body
        root.physicsBody?.applyForce(SCNVector3(impulse.x, impulse.y + 2, impulse.z), asImpulse: true)
        root.physicsBody?.applyTorque(SCNVector4(Float.random(in: -1...1), Float.random(in: -1...1),
                                                 Float.random(in: -1...1), 2.5), asImpulse: true)

        // Bodies linger briefly, then dissolve — long enough to read the kill, short
        // enough to keep the scene graph small.
        root.runAction(.sequence([
            .wait(duration: 6),
            .fadeOut(duration: 1.2),
            .removeFromParentNode()
        ]))
    }

    func remove() {
        root.removeAllActions()
        root.removeFromParentNode()
    }
}

enum PhysicsCategory {
    static let world: Int = 1 << 0
    static let player: Int = 1 << 1
    static let projectile: Int = 1 << 2
    static let ragdoll: Int = 1 << 3
    static let pickup: Int = 1 << 4
}
