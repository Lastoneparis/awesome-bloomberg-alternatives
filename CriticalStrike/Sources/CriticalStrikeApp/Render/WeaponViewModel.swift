import Foundation
import SceneKit
import UIKit
import CriticalStrikeCore

/// The first-person weapon.
///
/// This is the single most important object for how the game *feels*. Everything here is
/// procedural and frame-rate independent: sway lags the camera, bob follows movement,
/// ADS is a spring between two anchor transforms, and recoil is an impulse that decays.
/// None of it touches the simulation — the weapon you see is a presentation of the state
/// the server already agreed on.
final class WeaponViewModel {
    let root = SCNNode()          // attached to the camera
    private let rigNode = SCNNode()   // sway + bob + recoil
    private let modelNode = SCNNode() // the gun itself
    private let muzzlePoint = SCNNode()
    private let ejectPoint = SCNNode()

    private var currentWeaponID: WeaponID?
    private var materials: MaterialLibrary

    // Animation state
    private var swayOffset = Vec3.zero
    private var swayRotation = Vec3.zero
    private var bobPhase: Float = 0
    private var bobAmount = Vec3.zero
    private var recoilOffset = Vec3.zero
    private var recoilRotation = Vec3.zero
    private var adsBlend: Float = 0
    private var lastYaw: Float = 0
    private var lastPitch: Float = 0
    private var reloadProgress: Float = 0
    private var isReloading = false
    private var jumpOffset: Float = 0

    // Anchors
    private static let hipPosition = Vec3(0.19, -0.175, -0.34)
    private static let hipRotation = Vec3(0, -0.06, 0)
    private static let adsPosition = Vec3(0, -0.075, -0.22)
    private static let adsRotation = Vec3(0, 0, 0)
    private static let sprintPosition = Vec3(0.24, -0.24, -0.30)
    private static let sprintRotation = Vec3(-0.35, -0.55, 0.25)

    init(materials: MaterialLibrary) {
        self.materials = materials
        root.name = "viewmodel"
        root.addChildNode(rigNode)
        rigNode.addChildNode(modelNode)
        modelNode.addChildNode(muzzlePoint)
        modelNode.addChildNode(ejectPoint)
        // The viewmodel renders in its own pass so a long barrel never clips into a wall.
        root.renderingOrder = 50
    }

    var muzzleWorldPosition: SCNVector3 { muzzlePoint.presentation.worldPosition }
    var muzzleNode: SCNNode { muzzlePoint }
    var ejectNode: SCNNode { ejectPoint }

    // MARK: - Model

    func equip(build: WeaponBuild, skin: CosmeticData?) {
        let weapon = build.resolved()
        guard currentWeaponID != weapon.id else { return }
        currentWeaponID = weapon.id
        modelNode.childNodes.forEach { node in
            if node !== muzzlePoint && node !== ejectPoint { node.removeFromParentNode() }
        }
        let model = WeaponViewModel.buildModel(for: weapon, materials: materials, skin: skin)
        for attachment in WeaponViewModel.attachmentNodes(for: build, materials: materials) {
            model.addChildNode(attachment)
        }
        modelNode.addChildNode(model)
        muzzlePoint.position = SCNVector3(0, 0.012, -Float(WeaponViewModel.barrelLength(for: weapon)))
        ejectPoint.position = SCNVector3(0.045, 0.02, -0.05)

        // Draw animation: the weapon swings up into frame.
        rigNode.position = SCNVector3(0, -0.35, 0.1)
        rigNode.eulerAngles = SCNVector3(-0.6, 0, 0)
        let draw = SCNAction.group([
            .move(to: SCNVector3Zero, duration: TimeInterval(weapon.drawTime)),
            .rotateTo(x: 0, y: 0, z: 0, duration: TimeInterval(weapon.drawTime))
        ])
        draw.timingMode = .easeOut
        rigNode.runAction(draw)
    }

    /// Weapons are built from primitives sized by class, so every gun in the roster has a
    /// distinct silhouette without a single imported mesh. Fitted attachments are added on
    /// top by `attachmentNodes`, so a player can tell what someone is running by looking.
    static func buildModel(for weapon: WeaponData, materials: MaterialLibrary,
                           skin: CosmeticData?) -> SCNNode {
        let node = SCNNode()
        node.name = weapon.id.value
        let body = materials.weaponMaterial(skin: skin)
        let dark = materials.material(for: .plastic, tintOverride: UIColor(white: 0.12, alpha: 1))

        func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ position: SCNVector3,
                 material: SCNMaterial, chamfer: CGFloat = 0.004) -> SCNNode {
            let geometry = SCNBox(width: w, height: h, length: l, chamferRadius: chamfer)
            geometry.firstMaterial = material
            let child = SCNNode(geometry: geometry)
            child.position = position
            return child
        }

        let barrel = barrelLength(for: weapon)

        switch weapon.weaponClass {
        case .assaultRifle, .lightMachineGun, .marksman:
            node.addChildNode(box(0.055, 0.075, 0.34, SCNVector3(0, 0, -0.02), material: body))
            node.addChildNode(box(0.03, 0.03, CGFloat(barrel) - 0.18,
                                  SCNVector3(0, 0.012, Float(-0.19 - (barrel - 0.18) / 2)), material: dark))
            node.addChildNode(box(0.045, 0.12, 0.07, SCNVector3(0, -0.085, 0.02), material: dark))  // grip
            node.addChildNode(box(0.05, 0.1, 0.09, SCNVector3(0, -0.055, -0.04), material: dark))   // magazine
            node.addChildNode(box(0.05, 0.06, 0.14, SCNVector3(0, 0.005, 0.15), material: body))    // stock
            node.addChildNode(box(0.02, 0.02, 0.02, SCNVector3(0, 0.055, -0.16), material: dark))   // front sight
            if weapon.weaponClass == .lightMachineGun {
                node.addChildNode(box(0.09, 0.13, 0.13, SCNVector3(0, -0.06, -0.02), material: body))
            }
        case .submachineGun:
            node.addChildNode(box(0.05, 0.07, 0.24, SCNVector3(0, 0, -0.01), material: body))
            node.addChildNode(box(0.026, 0.026, CGFloat(barrel) - 0.14,
                                  SCNVector3(0, 0.01, Float(-0.13 - (barrel - 0.14) / 2)), material: dark))
            node.addChildNode(box(0.04, 0.1, 0.06, SCNVector3(0, -0.07, 0.01), material: dark))
            node.addChildNode(box(0.035, 0.13, 0.05, SCNVector3(0, -0.075, -0.05), material: dark))
            node.addChildNode(box(0.035, 0.05, 0.1, SCNVector3(0, 0, 0.13), material: dark))
        case .sniperRifle:
            node.addChildNode(box(0.05, 0.07, 0.4, SCNVector3(0, 0, 0), material: body))
            node.addChildNode(box(0.024, 0.024, CGFloat(barrel) - 0.2,
                                  SCNVector3(0, 0.01, Float(-0.2 - (barrel - 0.2) / 2)), material: dark))
            node.addChildNode(box(0.045, 0.11, 0.07, SCNVector3(0, -0.08, 0.06), material: dark))
            node.addChildNode(box(0.05, 0.07, 0.18, SCNVector3(0, -0.01, 0.24), material: body))
            // Scope
            let scope = SCNCylinder(radius: 0.024, height: 0.22)
            scope.firstMaterial = dark
            let scopeNode = SCNNode(geometry: scope)
            scopeNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            scopeNode.position = SCNVector3(0, 0.062, -0.04)
            node.addChildNode(scopeNode)
            let lens = SCNCylinder(radius: 0.021, height: 0.005)
            lens.firstMaterial = materials.emissiveMaterial(color: UIColor(hex: 0x72D2FF), intensity: 0.4)
            let lensNode = SCNNode(geometry: lens)
            lensNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            lensNode.position = SCNVector3(0, 0.062, -0.152)
            node.addChildNode(lensNode)
        case .shotgun:
            node.addChildNode(box(0.06, 0.075, 0.3, SCNVector3(0, 0, -0.01), material: body))
            node.addChildNode(box(0.034, 0.034, CGFloat(barrel) - 0.16,
                                  SCNVector3(0, 0.014, Float(-0.16 - (barrel - 0.16) / 2)), material: dark))
            node.addChildNode(box(0.05, 0.04, 0.14, SCNVector3(0, -0.03, -0.14), material: dark)) // pump
            node.addChildNode(box(0.045, 0.11, 0.07, SCNVector3(0, -0.08, 0.05), material: dark))
            node.addChildNode(box(0.05, 0.075, 0.16, SCNVector3(0, -0.01, 0.22), material: body))
        case .pistol:
            node.addChildNode(box(0.035, 0.06, 0.17, SCNVector3(0, 0, -0.02), material: body))
            node.addChildNode(box(0.022, 0.022, CGFloat(barrel) - 0.08,
                                  SCNVector3(0, 0.006, Float(-0.09 - (barrel - 0.08) / 2)), material: dark))
            node.addChildNode(box(0.035, 0.105, 0.045, SCNVector3(0, -0.075, 0.03), material: dark))
        case .melee:
            let blade = SCNBox(width: 0.012, height: 0.045, length: 0.2, chamferRadius: 0.006)
            blade.firstMaterial = materials.weaponMaterial(skin: skin)
            let bladeNode = SCNNode(geometry: blade)
            bladeNode.position = SCNVector3(0, 0.01, -0.12)
            node.addChildNode(bladeNode)
            node.addChildNode(box(0.022, 0.03, 0.1, SCNVector3(0, 0, 0.01), material: dark))
        case .grenade, .special:
            let sphere = SCNSphere(radius: 0.04)
            sphere.firstMaterial = body
            node.addChildNode(SCNNode(geometry: sphere))
        }

        return node
    }

    static func attachmentNodes(for build: WeaponBuild, materials: MaterialLibrary) -> [SCNNode] {
        var nodes: [SCNNode] = []
        for id in build.normalizedAttachments {
            guard let attachment = AttachmentDatabase.attachment(id) else { continue }
            let material = materials.material(for: .plastic,
                                              tintOverride: UIColor(white: 0.1, alpha: 1))
            switch attachment.slot {
            case .optic:
                let geometry = SCNBox(width: 0.03, height: 0.035, length: 0.07, chamferRadius: 0.005)
                geometry.firstMaterial = material
                let node = SCNNode(geometry: geometry)
                node.position = SCNVector3(0, 0.062, -0.03)
                nodes.append(node)
            case .barrel:
                let geometry = SCNCylinder(radius: 0.021, height: 0.09)
                geometry.firstMaterial = material
                let node = SCNNode(geometry: geometry)
                node.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
                node.position = SCNVector3(0, 0.012, -0.30)
                nodes.append(node)
            case .laser:
                let geometry = SCNBox(width: 0.015, height: 0.015, length: 0.035, chamferRadius: 0.003)
                geometry.firstMaterial = materials.emissiveMaterial(color: .red, intensity: 0.8)
                let node = SCNNode(geometry: geometry)
                node.position = SCNVector3(0.03, -0.01, -0.18)
                nodes.append(node)
            case .grip:
                let geometry = SCNBox(width: 0.022, height: 0.06, length: 0.03, chamferRadius: 0.004)
                geometry.firstMaterial = material
                let node = SCNNode(geometry: geometry)
                node.position = SCNVector3(0, -0.055, -0.16)
                nodes.append(node)
            case .magazine:
                let geometry = SCNBox(width: 0.05, height: 0.13, length: 0.09, chamferRadius: 0.006)
                geometry.firstMaterial = material
                let node = SCNNode(geometry: geometry)
                node.position = SCNVector3(0, -0.07, -0.04)
                nodes.append(node)
            case .stock:
                let geometry = SCNBox(width: 0.05, height: 0.07, length: 0.16, chamferRadius: 0.008)
                geometry.firstMaterial = material
                let node = SCNNode(geometry: geometry)
                node.position = SCNVector3(0, 0, 0.17)
                nodes.append(node)
            }
        }
        return nodes
    }

    static func barrelLength(for weapon: WeaponData) -> CGFloat {
        switch weapon.weaponClass {
        case .sniperRifle: return 0.62
        case .lightMachineGun, .marksman: return 0.52
        case .assaultRifle: return 0.46
        case .shotgun: return 0.44
        case .submachineGun: return 0.32
        case .pistol: return 0.2
        case .melee: return 0.22
        default: return 0.3
        }
    }

    // MARK: - Per-frame

    struct Input {
        var yaw: Float
        var pitch: Float
        var velocity: Vec3
        var onGround: Bool
        var adsProgress: Float
        var isSprinting: Bool
        var isReloading: Bool
        var reloadProgress: Float
        var weapon: WeaponData
        var settings: GameSettings
    }

    func update(_ input: Input, deltaTime dt: Float) {
        adsBlend = input.adsProgress

        // ── Sway: the weapon lags behind camera rotation, weighted by the gun's mass ──
        let yawDelta = MathUtil.angleDelta(lastYaw, input.yaw)
        let pitchDelta = input.pitch - lastPitch
        lastYaw = input.yaw
        lastPitch = input.pitch

        let weightFactor = 1 / max(0.4, input.weapon.weight)
        let swayScale: Float = MathUtil.lerp(0.12, 0.035, adsBlend) * weightFactor
        let targetSway = Vec3(MathUtil.clamp(yawDelta * 6, -1, 1) * swayScale,
                              MathUtil.clamp(-pitchDelta * 6, -1, 1) * swayScale, 0)
        swayOffset = MathUtil.dampVec(swayOffset, targetSway, halfLife: 0.07, dt: dt)
        let targetSwayRotation = Vec3(MathUtil.clamp(pitchDelta * 5, -1, 1) * 0.25,
                                      MathUtil.clamp(yawDelta * 5, -1, 1) * 0.3,
                                      MathUtil.clamp(-yawDelta * 5, -1, 1) * 0.35)
        swayRotation = MathUtil.dampVec(swayRotation, targetSwayRotation, halfLife: 0.09, dt: dt)

        // ── Bob: tied to actual speed, damped hard while aiming ──
        let speed = input.velocity.horizontalLength
        let speedRatio = MathUtil.clamp(speed / MovementSystem.runSpeed, 0, 1.4)
        if input.onGround {
            bobPhase += dt * (5.5 + speedRatio * 6)
        }
        let bobScale = MathUtil.lerp(0.022, 0.004, adsBlend) * speedRatio
        let targetBob = Vec3(sin(bobPhase) * bobScale,
                             abs(cos(bobPhase * 2)) * bobScale * 0.6, 0)
        bobAmount = MathUtil.dampVec(bobAmount, targetBob, halfLife: 0.08, dt: dt)

        // ── Airborne: the gun drifts as the player leaves the ground ──
        let targetJump: Float = input.onGround ? 0 : MathUtil.clamp(-input.velocity.y * 0.01, -0.05, 0.05)
        jumpOffset = MathUtil.damp(jumpOffset, targetJump, halfLife: 0.12, dt: dt)

        // ── Recoil decay ──
        recoilOffset = MathUtil.dampVec(recoilOffset, .zero, halfLife: 0.055, dt: dt)
        recoilRotation = MathUtil.dampVec(recoilRotation, .zero, halfLife: 0.07, dt: dt)

        // ── Reload pose ──
        isReloading = input.isReloading
        reloadProgress = input.reloadProgress

        // ── Compose the final transform ──
        let sprintBlend: Float = input.isSprinting && adsBlend < 0.05 ? 1 : 0
        let basePosition = WeaponViewModel.hipPosition
            .lerp(WeaponViewModel.adsPosition, adsBlend)
            .lerp(WeaponViewModel.sprintPosition, sprintBlend * (1 - adsBlend))
        let baseRotation = WeaponViewModel.hipRotation
            .lerp(WeaponViewModel.adsRotation, adsBlend)
            .lerp(WeaponViewModel.sprintRotation, sprintBlend * (1 - adsBlend))

        var position = basePosition + swayOffset + bobAmount + recoilOffset
        position.y += jumpOffset
        var rotation = baseRotation + swayRotation + recoilRotation

        if isReloading {
            // Tilt the weapon down and rock it through the reload.
            let curve = sin(reloadProgress * .pi)
            position.y -= 0.09 * curve
            position.z += 0.03 * curve
            rotation.x += 0.5 * curve
            rotation.z += 0.25 * curve
        }

        rigNode.position = SCNVector3(position.x, position.y, position.z)
        rigNode.eulerAngles = SCNVector3(rotation.x, rotation.y, rotation.z)
    }

    /// Called once per shot. Kick is proportional to the weapon's recoil so a sniper
    /// slams and an SMG chatters.
    func applyRecoilKick(weapon: WeaponData, aiming: Bool) {
        let scale: Float = aiming ? 0.7 : 1.0
        let vertical = weapon.recoilVertical * 14 * scale
        let back = weapon.recoilVertical * 22 * scale
        recoilOffset += Vec3(Float.random(in: -0.004...0.004) * scale, vertical * 0.35, back)
        recoilRotation += Vec3(-vertical * 2.6,
                               Float.random(in: -0.5...0.5) * weapon.recoilHorizontal * 14,
                               Float.random(in: -0.6...0.6) * weapon.recoilHorizontal * 18)
    }

    func playInspect() {
        let inspect = SCNAction.sequence([
            .rotateBy(x: 0.3, y: -0.9, z: 0.4, duration: 0.55),
            .wait(duration: 0.3),
            .rotateBy(x: -0.3, y: 0.9, z: -0.4, duration: 0.5)
        ])
        inspect.timingMode = .easeInEaseOut
        modelNode.runAction(inspect)
    }

    func setHidden(_ hidden: Bool) { root.isHidden = hidden }
}
