import Foundation
import SceneKit
import UIKit
import CriticalStrikeCore

/// Owns the SceneKit scene and turns simulation state into pixels.
///
/// The renderer is strictly a consumer: it never writes to the simulation. Each frame it
/// reads the local player's predicted state plus the interpolated snapshot of everyone
/// else, then updates nodes. That one-way flow is what keeps rendering, prediction and
/// the authoritative server from fighting each other.
final class GameRenderer: NSObject {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private(set) var viewModel: WeaponViewModel
    private(set) var effects: EffectsSystem

    private let materials: MaterialLibrary
    private let worldRoot = SCNNode()
    private let dynamicRoot = SCNNode()
    private var characters: [PlayerID: CharacterNode] = [:]
    private var pickupNodes: [EntityID: SCNNode] = [:]
    private var objectiveNodes: [Int: SCNNode] = [:]
    private var spawnMarkers: SCNNode?

    private var map: MapData
    private var settings: GameSettings
    private var quality: GraphicsQuality
    private var localPlayerID: PlayerID = .none
    private var localTeam: Team = .none

    // Camera state
    private var cameraShake = Vec3.zero
    private var cameraShakeVelocity = Vec3.zero
    private var currentFOV: Float = 78
    private var targetFOV: Float = 78
    private var deathCameraTarget: Vec3?

    // Dynamic resolution
    private var frameTimeAverage: Double = 1.0 / 60
    private var currentRenderScale: Float = 1
    private weak var sceneView: SCNView?

    init(map: MapData, settings: GameSettings) {
        self.map = map
        self.settings = settings
        self.quality = settings.quality
        self.materials = MaterialLibrary(quality: settings.quality)
        self.viewModel = WeaponViewModel(materials: materials)
        self.effects = EffectsSystem(root: dynamicRoot, materials: materials, quality: settings.quality)
        super.init()
        buildScene()
    }

    // MARK: - Scene construction

    private func buildScene() {
        scene.rootNode.addChildNode(worldRoot)
        scene.rootNode.addChildNode(dynamicRoot)

        let built = MapBuilder.build(map: map, materials: materials, quality: quality)
        worldRoot.addChildNode(built.root)
        objectiveNodes = built.objectiveNodes
        spawnMarkers = built.spawnMarkers

        // Environment
        scene.background.contents = skyColor()
        scene.lightingEnvironment.contents = skyColor()
        scene.lightingEnvironment.intensity = 1.1
        if quality != .low {
            scene.fogColor = UIColor(hex: map.environment.fogColorHex)
            scene.fogStartDistance = CGFloat(map.environment.fogStart)
            scene.fogEndDistance = CGFloat(map.environment.fogEnd)
            scene.fogDensityExponent = CGFloat(map.environment.fogDensity)
        }

        // Static geometry never moves, so let SceneKit skip its transform updates.
        worldRoot.enumerateChildNodes { node, _ in
            node.movabilityHint = .fixed
        }

        // Camera
        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(settings.fieldOfView)
        camera.zNear = 0.03
        camera.zFar = 400
        camera.wantsHDR = quality == .high || quality == .ultra
        camera.wantsExposureAdaptation = false
        camera.bloomThreshold = CGFloat(map.environment.bloomThreshold)
        camera.bloomIntensity = quality.bloomEnabled ? 0.55 : 0
        camera.bloomBlurRadius = 12
        camera.screenSpaceAmbientOcclusionIntensity = quality.ambientOcclusionEnabled ? 0.6 : 0
        camera.screenSpaceAmbientOcclusionRadius = 1.2
        camera.motionBlurIntensity = quality.motionBlurEnabled ? 0.35 : 0
        camera.colorFringeStrength = quality == .ultra ? 0.4 : 0
        camera.vignettingIntensity = 0.25
        camera.vignettingPower = 1.2
        cameraNode.camera = camera
        cameraNode.name = "camera"
        scene.rootNode.addChildNode(cameraNode)
        cameraNode.addChildNode(viewModel.root)

        // Physics is only used for casings and ragdolls; the gameplay simulation has its
        // own collision and never consults SceneKit.
        scene.physicsWorld.gravity = SCNVector3(0, -MovementSystem.gravity, 0)
        scene.physicsWorld.speed = 1
    }

    private func skyColor() -> UIColor {
        UIColor(hex: map.environment.fogColorHex).darkened(by: 0.85)
    }

    func attach(to view: SCNView) {
        sceneView = view
        view.scene = scene
        view.pointOfView = cameraNode
        view.antialiasingMode = quality.antialiasingSamples >= 4 ? .multisampling4X
            : (quality.antialiasingSamples >= 2 ? .multisampling2X : .none)
        view.preferredFramesPerSecond = settings.frameRateCap.rawValue
        view.rendersContinuously = true
        view.isJitteringEnabled = false
        view.autoenablesDefaultLighting = false
        view.backgroundColor = skyColor()
        view.contentScaleFactor = UIScreen.main.scale * CGFloat(quality.renderScale)
    }

    func applySettings(_ settings: GameSettings) {
        let qualityChanged = settings.quality != self.settings.quality
        self.settings = settings
        quality = settings.quality
        cameraNode.camera?.fieldOfView = CGFloat(settings.fieldOfView)
        cameraNode.camera?.bloomIntensity = quality.bloomEnabled ? 0.55 : 0
        cameraNode.camera?.motionBlurIntensity = quality.motionBlurEnabled ? 0.35 : 0
        cameraNode.camera?.screenSpaceAmbientOcclusionIntensity =
            quality.ambientOcclusionEnabled ? 0.6 : 0
        effects.setQuality(quality)
        sceneView?.preferredFramesPerSecond = settings.frameRateCap.rawValue
        if qualityChanged {
            Log.info("Graphics quality → \(quality.rawValue)", category: "render")
        }
    }

    func setLocalPlayer(_ id: PlayerID, team: Team) {
        localPlayerID = id
        localTeam = team
    }

    func showSpawnMarkers(_ show: Bool) {
        spawnMarkers?.isHidden = !show
    }

    // MARK: - Per-frame

    /// Called once per rendered frame with the local player's predicted state.
    func updateCamera(player: PlayerState, renderPosition: Vec3, deltaTime: Float) {
        let eye = renderPosition + Vec3(0, player.stance.eyeHeight, 0)

        // Camera shake decays as a damped spring so hits and explosions read as impacts
        // rather than as a stutter.
        cameraShakeVelocity = MathUtil.dampVec(cameraShakeVelocity, .zero, halfLife: 0.09, dt: deltaTime)
        cameraShake = MathUtil.dampVec(cameraShake + cameraShakeVelocity * deltaTime, .zero,
                                       halfLife: 0.12, dt: deltaTime)

        cameraNode.position = SCNVector3(eye.x + cameraShake.x,
                                         eye.y + cameraShake.y,
                                         eye.z + cameraShake.z)

        // Recoil punch is visual only and never affects where the bullet goes.
        let pitch = player.angles.pitch + player.recoilPunch.pitch + cameraShake.y * 0.02
        let yaw = player.angles.yaw + player.recoilPunch.yaw
        let roll = player.recoilPunch.roll * 0.02 + leanRoll(for: player)
        cameraNode.eulerAngles = SCNVector3(pitch, yaw, roll)

        // FOV: widens slightly when sprinting, narrows to the weapon's zoom when aiming.
        let weapon = player.activeWeapon
        let zoom = player.scopeLevel > 0 && !weapon.scopeLevels.isEmpty
            ? weapon.scopeLevels[min(player.scopeLevel, weapon.scopeLevels.count - 1)]
            : weapon.adsZoom
        let sprinting = player.velocity.horizontalLength > MovementSystem.runSpeed * 1.05
        let base = settings.fieldOfView * (sprinting ? 1.06 : 1.0)
        targetFOV = base / MathUtil.lerp(1, zoom, player.adsProgress)
        currentFOV = MathUtil.damp(currentFOV, targetFOV, halfLife: 0.045, dt: deltaTime)
        cameraNode.camera?.fieldOfView = CGFloat(currentFOV)

        // A scoped weapon hides the viewmodel entirely and shows the scope overlay instead.
        let fullyScoped = player.adsProgress > 0.92 && !weapon.scopeLevels.isEmpty
        viewModel.setHidden(!player.isAlive || fullyScoped)

        if player.isAlive {
            viewModel.update(WeaponViewModel.Input(
                yaw: player.angles.yaw, pitch: player.angles.pitch,
                velocity: player.velocity, onGround: player.onGround,
                adsProgress: player.adsProgress, isSprinting: sprinting,
                isReloading: player.action == .reloading,
                reloadProgress: player.actionTimer.progress,
                weapon: weapon, settings: settings), deltaTime: deltaTime)
        }
    }

    /// Third-person death camera: pulls back and looks at the killer.
    func updateDeathCamera(victimPosition: Vec3, killerPosition: Vec3?, deltaTime: Float) {
        let target = killerPosition ?? (victimPosition + Vec3(0, 3, 4))
        deathCameraTarget = target
        let desired = victimPosition + Vec3(0, 2.2, 0) + (victimPosition - target).normalized * 3.2
        let current = Vec3(cameraNode.position.x, cameraNode.position.y, cameraNode.position.z)
        let smoothed = MathUtil.dampVec(current, desired, halfLife: 0.25, dt: deltaTime)
        cameraNode.position = SCNVector3(smoothed.x, smoothed.y, smoothed.z)
        let angles = ViewAngles.looking(from: smoothed, at: target + Vec3(0, 1.2, 0))
        cameraNode.eulerAngles = SCNVector3(angles.pitch, angles.yaw, 0)
        viewModel.setHidden(true)
    }

    private func leanRoll(for player: PlayerState) -> Float {
        // A touch of roll when strafing sells the movement without costing readability.
        let right = player.angles.right
        let lateral = player.velocity.dot(right) / MovementSystem.runSpeed
        return -MathUtil.clamp(lateral, -1, 1) * 0.022
    }

    func addCameraShake(intensity: Float, direction: Vec3 = Vec3(0, 1, 0)) {
        let scaled = intensity * settings.screenShake
        guard scaled > 0.001 else { return }
        cameraShakeVelocity += direction.normalized * scaled
            + Vec3(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) * scaled * 0.4
    }

    // MARK: - Remote players

    func syncPlayers(snapshot: WorldSnapshot, names: [PlayerID: String], deltaTime: Float,
                     weaponBuilds: [PlayerID: WeaponBuild]) {
        var seen = Set<PlayerID>()
        for player in snapshot.players where player.id != localPlayerID {
            seen.insert(player.id)
            let node = characters[player.id] ?? {
                let created = CharacterNode(id: player.id, team: player.team, materials: materials,
                                            colorBlind: settings.colorBlindMode,
                                            showNameplate: true,
                                            name: names[player.id] ?? "Operator")
                characters[player.id] = created
                dynamicRoot.addChildNode(created.root)
                return created
            }()

            let weaponModel = weaponBuilds[player.id].map { build in
                WeaponViewModel.buildModel(for: build.resolved(), materials: materials,
                                           skin: build.skin.flatMap(CosmeticDatabase.cosmetic))
            }
            node.apply(snapshot: player, localTeam: localTeam, deltaTime: deltaTime,
                       weaponModel: weaponModel)
        }

        // Retire characters for players who left.
        for (id, node) in characters where !seen.contains(id) {
            node.remove()
            characters[id] = nil
        }
    }

    func playerDied(_ id: PlayerID, impulse: Vec3) {
        characters[id]?.playDeath(impulse: impulse, quality: quality)
        characters[id] = nil
    }

    func removePlayer(_ id: PlayerID) {
        characters[id]?.remove()
        characters[id] = nil
    }

    // MARK: - Pickups

    func syncPickups(_ pickups: [PickupInstance]) {
        var seen = Set<EntityID>()
        for pickup in pickups where pickup.isActive {
            seen.insert(pickup.entity)
            if pickupNodes[pickup.entity] == nil {
                let node = makePickupNode(pickup)
                pickupNodes[pickup.entity] = node
                dynamicRoot.addChildNode(node)
            }
            pickupNodes[pickup.entity]?.position = SCNVector3(pickup.position.x,
                                                              pickup.position.y + 0.4,
                                                              pickup.position.z)
        }
        for (entity, node) in pickupNodes where !seen.contains(entity) {
            node.removeFromParentNode()
            pickupNodes[entity] = nil
        }
    }

    private func makePickupNode(_ pickup: PickupInstance) -> SCNNode {
        let node = SCNNode()
        let color: UInt32
        switch pickup.kind {
        case .health: color = 0x4CAF50
        case .armor: color = 0x2EC4F1
        case .ammo: color = 0xFFB300
        case .bomb: color = 0xFF3D71
        case .defuseKit: color = 0x64D2FF
        case .powerupDamage: color = 0xFF6B35
        case .powerupSpeed: color = 0xC792EA
        case .powerupShield: color = 0x7FB2FF
        case .weapon: color = 0xBFC6CC
        }
        let box = SCNBox(width: 0.3, height: 0.3, length: 0.3, chamferRadius: 0.06)
        box.firstMaterial = materials.emissiveMaterial(color: UIColor(hex: color), intensity: 0.7)
        node.addChildNode(SCNNode(geometry: box))

        // Slow spin plus a hover so pickups catch the eye without a UI marker.
        node.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 3.5)))
        node.runAction(.repeatForever(.sequence([
            .moveBy(x: 0, y: 0.12, z: 0, duration: 0.9),
            .moveBy(x: 0, y: -0.12, z: 0, duration: 0.9)
        ])))

        // Glow so it stays readable in a dark corner.
        let glow = SCNLight()
        glow.type = .omni
        glow.color = UIColor(hex: color)
        glow.intensity = 250
        glow.attenuationEndDistance = 3.5
        let glowNode = SCNNode()
        glowNode.light = glow
        node.addChildNode(glowNode)
        return node
    }

    // MARK: - Projectiles

    func syncProjectiles(_ projectiles: [ProjectileSnapshot]) {
        for projectile in projectiles {
            effects.updateGrenade(entity: projectile.entity, position: projectile.position)
        }
    }

    // MARK: - Objectives

    func setObjectiveHighlighted(_ index: Int, highlighted: Bool) {
        guard let node = objectiveNodes[index] else { return }
        node.removeAllActions()
        if highlighted {
            node.runAction(.repeatForever(.sequence([
                .fadeOpacity(to: 0.4, duration: 0.6),
                .fadeOpacity(to: 1.0, duration: 0.6)
            ])))
        } else {
            node.opacity = 0.75
        }
    }

    // MARK: - Dynamic resolution

    /// Keeps the frame rate at the cap by trading resolution rather than frames. Runs on a
    /// long average so it never oscillates visibly, and backs off hard when the device is
    /// thermally throttled.
    func updateDynamicResolution(frameTime: Double) {
        guard settings.dynamicResolution, let view = sceneView else { return }
        frameTimeAverage = frameTimeAverage * 0.95 + frameTime * 0.05
        let target = 1.0 / Double(settings.frameRateCap.rawValue)

        var desired = currentRenderScale
        if frameTimeAverage > target * 1.18 {
            desired -= 0.04
        } else if frameTimeAverage < target * 0.88 {
            desired += 0.02
        }
        if DeviceCapabilities.thermalState == .serious { desired = min(desired, 0.75) }
        if DeviceCapabilities.thermalState == .critical { desired = min(desired, 0.6) }

        let clamped = MathUtil.clamp(desired, 0.55, 1.0)
        guard abs(clamped - currentRenderScale) > 0.015 else { return }
        currentRenderScale = clamped
        view.contentScaleFactor = UIScreen.main.scale * CGFloat(clamped * quality.renderScale)
    }

    var renderScale: Float { currentRenderScale }

    // MARK: - Teardown

    func reset() {
        for (_, node) in characters { node.remove() }
        characters.removeAll()
        for (_, node) in pickupNodes { node.removeFromParentNode() }
        pickupNodes.removeAll()
        effects.reset()
    }
}
