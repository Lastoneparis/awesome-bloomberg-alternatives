import Foundation
import SceneKit
import SwiftUI
import Combine
import CriticalStrikeCore

/// One match, from loading to results.
///
/// `GameSession` is the only object that touches both the simulation and the renderer.
/// It drives the fixed-step simulation from SceneKit's render loop, drains the event bus
/// into audio/haptics/effects, and publishes just enough state for the HUD to draw.
/// Publishing is throttled deliberately — a SwiftUI HUD that re-renders 120 times a second
/// costs more than the 3D scene does.
@MainActor
final class GameSession: NSObject, ObservableObject {
    // MARK: Published HUD state
    @Published private(set) var hud = HUDState()
    @Published private(set) var killFeed: [KillFeedEntry] = []
    @Published private(set) var scoreboard: [PlayerResult] = []
    @Published private(set) var isPaused = false
    @Published private(set) var showScoreboard = false
    @Published private(set) var showBuyMenu = false
    @Published private(set) var damageIndicators: [DamageIndicator] = []
    @Published private(set) var floatingDamage: [FloatingDamage] = []

    // MARK: Configuration
    let mode: GameModeData
    let map: MapData
    let offline: Bool
    private(set) var localPlayerID: PlayerID = .none

    // MARK: Systems
    private(set) var renderer: GameRenderer
    let controls = TouchControls()
    private let audio: AudioEngine
    private let haptics: HapticsService
    private let missionTracker: MissionTracker
    private var server: GameServer?
    private var client: GameClientSession?
    private var sim: MatchSimulation
    private var botDirector: BotDirector
    private let aimAssist = AimAssist()

    // MARK: Loop
    private var clock = GameClock()
    private var lastFrameTime: TimeInterval = 0
    private var hudUpdateAccumulator: Float = 0
    private var settings: GameSettings
    private var screenSize = CGSize(width: 844, height: 390)

    // MARK: Stats for the results screen
    private(set) var shotsFired = 0
    private(set) var shotsHit = 0
    private(set) var killsByWeapon: [WeaponID: Int] = [:]

    var onProgress: ((Double) -> Void)?
    var onMatchEnded: ((MatchResult) -> Void)?

    private var playerNames: [PlayerID: String] = [:]
    private var weaponBuilds: [PlayerID: WeaponBuild] = [:]
    private var lastLocalSnapshotPosition = Vec3.zero

    init(profile: PlayerProfile, mode modeKind: GameModeKind, mapID: MapID, offline: Bool,
         audio: AudioEngine, haptics: HapticsService, missionTracker: MissionTracker) {
        self.mode = GameModeDatabase.mode(modeKind)
        self.map = MapDatabase.mapOrDefault(mapID)
        self.offline = offline
        self.audio = audio
        self.haptics = haptics
        self.missionTracker = missionTracker
        self.settings = profile.settings

        let server = GameServer(map: map, mode: self.mode,
                                botDifficulty: profile.settings.preferredBotDifficulty,
                                seed: UInt64(abs(profile.accountID.hashValue)) | 1)
        self.server = server
        self.sim = server.sim
        self.botDirector = server.botDirector
        self.renderer = GameRenderer(map: map, settings: profile.settings)
        super.init()

        controls.settings = profile.settings
        let loadout = profile.validatedLoadout
        localPlayerID = sim.addPlayer(name: profile.displayName,
                                      team: self.mode.kind.isTeamBased ? .strike : .none,
                                      isBot: false, loadout: loadout)
        sim.localPlayer = localPlayerID
        weaponBuilds[localPlayerID] = loadout.primary
        playerNames[localPlayerID] = profile.displayName

        server.onMatchEnded = { [weak self] result in
            Task { @MainActor in self?.handleMatchEnded(result) }
        }
    }

    // MARK: - Setup

    func prepare() async {
        onProgress?(0.1)
        // Fill the roster.
        botDirector.fillMatch(sim)
        for player in sim.allPlayers() {
            playerNames[player.id] = player.name
            weaponBuilds[player.id] = player.loadout.primary
        }
        onProgress?(0.45)

        audio.preload(for: map, loadout: sim.player(localPlayerID)?.loadout ?? Loadout.starter())
        onProgress?(0.7)

        renderer.setLocalPlayer(localPlayerID, team: sim.player(localPlayerID)?.team ?? .none)
        renderer.showSpawnMarkers(true)
        onProgress?(0.9)

        // Subscribe to simulation events.
        sim.events.subscribe { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        onProgress?(1.0)
    }

    func begin() {
        audio.playMusic(map.environment.musicTrack)
        audio.playSpatial(map.environment.ambienceLoop, at: .zero, volume: 0.35)
        if let player = sim.player(localPlayerID) {
            controls.setAngles(yaw: player.angles.yaw, pitch: player.angles.pitch)
        }
        isPaused = false
    }

    func pause() { isPaused = true }
    func resume() { isPaused = false; lastFrameTime = 0 }

    func end() {
        isPaused = true
        renderer.reset()
        client?.disconnect()
        server = nil
        client = nil
    }

    func applySettings(_ settings: GameSettings) {
        self.settings = settings
        controls.settings = settings
        renderer.applySettings(settings)
    }

    func setScreenSize(_ size: CGSize) { screenSize = size }

    func attach(to view: SCNView) {
        renderer.attach(to: view)
        view.delegate = self
    }

    // MARK: - Frame

    private func step(deltaTime: Float) {
        guard !isPaused else { return }
        guard var player = sim.player(localPlayerID) else { return }

        // 1. Aim assist target (needs the pre-input player state).
        let candidates = sim.hitVolumes(excluding: localPlayerID)
        let target = aimAssist.findTarget(from: player, candidates: candidates, world: sim.world,
                                          level: settings.aimAssist,
                                          screenHeightPoints: Float(screenSize.height),
                                          verticalFOV: Float(renderer.cameraNode.camera?.fieldOfView ?? 78)
                                              * MathUtil.deg2rad)

        // 2. Build and submit the local command.
        let command = controls.buildCommand(deltaTime: deltaTime, player: player, assistTarget: target)
        sim.setInput(command, for: localPlayerID)

        // 3. Advance the authoritative simulation in fixed steps.
        let steps = clock.advance(deltaTime: deltaTime)
        for _ in 0..<steps {
            clock.consumeTick()
            botDirector.step(sim: sim, dt: GameClock.tickInterval)
            sim.step(deltaTime: GameClock.tickInterval)
        }
        if steps == 0 { return }

        // 4. Render.
        player = sim.player(localPlayerID) ?? player
        if player.isAlive {
            renderer.updateCamera(player: player, renderPosition: player.position, deltaTime: deltaTime)
        } else {
            let killer = player.lastAttacker.isValid ? sim.player(player.lastAttacker)?.position : nil
            renderer.updateDeathCamera(victimPosition: player.position, killerPosition: killer,
                                       deltaTime: deltaTime)
        }

        let snapshot = WorldSnapshot(from: sim)
        renderer.syncPlayers(snapshot: snapshot, names: playerNames, deltaTime: deltaTime,
                             weaponBuilds: weaponBuilds)
        renderer.syncPickups(sim.pickups)
        renderer.syncProjectiles(snapshot.projectiles)
        renderer.showSpawnMarkers(sim.state.phase == .warmup || sim.state.phase == .freezeTime)

        // 5. Listener for spatial audio.
        let eye = player.eyePosition
        audio.updateListener(position: eye, forward: player.angles.forward, up: Vec3.up)

        // 6. Throttled HUD publish (20Hz is plenty for numbers that change this slowly).
        hudUpdateAccumulator += deltaTime
        if hudUpdateAccumulator > 0.05 {
            hudUpdateAccumulator = 0
            publishHUD(player: player, assistTarget: target)
        }
        decayIndicators(deltaTime: deltaTime)
    }

    // MARK: - HUD

    private func publishHUD(player: PlayerState, assistTarget: AimAssist.Target?) {
        let slot = player.slots[player.activeSlot]
        let weapon = player.activeWeapon
        let objective = sim.currentRules.objectiveSummary(sim: sim)

        hud = HUDState(
            health: player.health,
            maxHealth: player.maxHealth,
            armor: player.armor,
            maxArmor: player.maxArmor,
            ammoInMagazine: slot?.ammoInMagazine ?? 0,
            reserveAmmo: slot?.reserveAmmo ?? 0,
            magazineSize: weapon.magazineSize,
            weaponName: weapon.name,
            weaponID: weapon.id,
            crosshairKind: weapon.crosshairKind,
            spread: RecoilSystem.effectiveSpread(player: player, weapon: weapon),
            adsProgress: player.adsProgress,
            scopeLevel: player.scopeLevel,
            isScoped: player.adsProgress > 0.92 && !weapon.scopeLevels.isEmpty,
            isReloading: player.action == .reloading,
            reloadProgress: player.actionTimer.progress,
            isAlive: player.isAlive,
            respawnSeconds: player.respawnTimer.remaining,
            lethalCount: player.lethalCount,
            tacticalCount: player.tacticalCount,
            lethalID: player.lethalID,
            tacticalID: player.tacticalID,
            flashAmount: player.flashAmount,
            stunAmount: player.stunAmount,
            lowHealthPulse: player.health < player.maxHealth * 0.3,
            isBurning: sim.time < player.burningUntil,
            hasTargetUnderCrosshair: assistTarget?.isUnderCrosshair ?? false,
            strikeScore: sim.state.score(.strike),
            shieldScore: sim.state.score(.shield),
            scoreLimit: mode.scoreLimit,
            round: sim.state.round,
            phase: sim.state.phase,
            phaseTimeRemaining: sim.state.phaseTimer.remaining,
            matchTimeRemaining: sim.state.matchTimer.remaining,
            objectiveHeadline: objective.headline,
            objectiveDetail: objective.detail,
            strikeObjectiveProgress: objective.strikeProgress,
            shieldObjectiveProgress: objective.shieldProgress,
            bombPlanted: sim.state.bomb.isPlanted && !sim.state.bomb.isDefused,
            bombTimeRemaining: sim.state.bomb.timer.remaining,
            plantProgress: player.plantProgress,
            defuseProgress: player.defuseProgress,
            canPlant: canPlant(player: player),
            canDefuse: canDefuse(player: player),
            money: player.money,
            killStreak: player.currentStreak,
            kills: player.kills,
            deaths: player.deaths,
            team: player.team,
            callout: map.callout(at: player.position),
            connectionQuality: client?.connectionQuality ?? .excellent,
            teammates: teammateMarkers(for: player),
            minimapEnemies: minimapEnemies(for: player)
        )
        killFeed = sim.killFeed
        if showScoreboard {
            scoreboard = sim.buildResult(winner: .none).scoreboard
        }
    }

    private func canPlant(player: PlayerState) -> Bool {
        guard mode.kind.isRoundBased, player.hasBomb, !sim.state.bomb.isPlanted else { return false }
        return map.bombSites.contains { $0.contains(player.position) }
    }

    private func canDefuse(player: PlayerState) -> Bool {
        guard sim.state.bomb.isPlanted, !sim.state.bomb.isDefused,
              player.team == .shield else { return false }
        return player.position.distance(to: sim.state.bomb.position) < 2.2
    }

    private func teammateMarkers(for player: PlayerState) -> [MinimapMarker] {
        sim.allPlayers().filter { $0.id != player.id && $0.team == player.team && $0.isAlive }
            .map { MinimapMarker(id: $0.id, position: $0.position, yaw: $0.angles.yaw,
                                 team: $0.team, isEnemy: false, name: $0.name) }
    }

    /// Enemies appear on the minimap only when they make noise — gunfire without a
    /// suppressor, or sprinting within earshot. That is the whole information game.
    private func minimapEnemies(for player: PlayerState) -> [MinimapMarker] {
        guard settings.showMinimap else { return [] }
        var markers: [MinimapMarker] = []
        for enemy in sim.allPlayers() where enemy.team != player.team && enemy.isAlive {
            if mode.minimapShowsEnemies {
                markers.append(MinimapMarker(id: enemy.id, position: enemy.position,
                                             yaw: enemy.angles.yaw, team: enemy.team,
                                             isEnemy: true, name: ""))
                continue
            }
            guard !enemy.perks.silentOnMinimap else { continue }
            let firedRecently = sim.time - enemy.lastFireTime < 2.0
            let loudness = weaponBuilds[enemy.id]?.loudness ?? 1
            if firedRecently && loudness > 0.5 {
                markers.append(MinimapMarker(id: enemy.id, position: enemy.lastNoisePosition == .zero
                                                ? enemy.position : enemy.position,
                                             yaw: enemy.angles.yaw, team: enemy.team,
                                             isEnemy: true, name: ""))
            }
        }
        return markers
    }

    private func decayIndicators(deltaTime: Float) {
        let now = sim.time
        damageIndicators.removeAll { now - $0.timestamp > 2.0 }
        floatingDamage.removeAll { now - $0.timestamp > 1.1 }
    }

    // MARK: - Events

    private func handle(_ event: GameEvent) {
        switch event {
        case let .weaponFired(player, weaponID, origin, _, _):
            let weapon = WeaponDatabase.weaponOrDefault(weaponID)
            if player == localPlayerID {
                shotsFired += 1
                renderer.effects.muzzleFlash(at: renderer.viewModel.muzzleNode, weapon: weapon)
                renderer.effects.ejectShell(from: renderer.viewModel.ejectNode, weapon: weapon)
                renderer.viewModel.applyRecoilKick(weapon: weapon,
                                                   aiming: sim.player(localPlayerID)?.isAiming ?? false)
                renderer.addCameraShake(intensity: weapon.recoilVertical * 1.4)
                haptics.weaponFire(recoil: weapon.recoilVertical)
                audio.playUI(weapon.fireSound, volume: 0.9)
            } else {
                audio.playSpatial(weapon.fireSound, at: origin)
            }

        case let .bulletTracer(from, to, weaponID):
            renderer.effects.tracer(from: from, to: to,
                                    weapon: WeaponDatabase.weaponOrDefault(weaponID),
                                    isLocalPlayer: false)

        case let .bulletImpact(position, normal, surface, penetrated):
            renderer.effects.bulletImpact(position: position, normal: normal,
                                          surface: surface, penetrated: penetrated)
            audio.playSpatial(surface.impactEffect, at: position, volume: 0.55)

        case let .playerDamaged(victim, attacker, amount, hitbox, position):
            if victim == localPlayerID {
                haptics.tookDamage(amount: amount)
                renderer.addCameraShake(intensity: min(0.35, amount * 0.004))
                if let attackerState = sim.player(attacker) {
                    damageIndicators.append(DamageIndicator(
                        direction: directionAngle(from: sim.player(localPlayerID)?.position ?? .zero,
                                                  to: attackerState.position,
                                                  viewYaw: sim.player(localPlayerID)?.angles.yaw ?? 0),
                        amount: amount, timestamp: sim.time))
                }
                audio.playUI("sfx_take_damage", volume: 0.8)
            } else if attacker == localPlayerID {
                shotsHit += 1
                haptics.hitMarker(headshot: hitbox.isHead)
                audio.playUI(hitbox.isHead ? "sfx_headshot" : "sfx_hitmarker")
                hud.hitMarkerTimestamp = sim.time
                hud.lastHitWasHeadshot = hitbox.isHead
                if settings.showDamageNumbers {
                    floatingDamage.append(FloatingDamage(amount: amount, headshot: hitbox.isHead,
                                                         worldPosition: position, timestamp: sim.time))
                }
                renderer.effects.bloodSpray(position: position,
                                            direction: (position - (sim.player(localPlayerID)?.eyePosition ?? .zero)).normalized,
                                            amount: amount, showBlood: settings.showBlood)
            }

        case let .playerDied(victim, killer, weaponID, headshot, _):
            let impulse = (sim.player(victim)?.velocity ?? .zero) * 30 + Vec3(0, 60, 0)
            renderer.playerDied(victim, impulse: impulse)
            missionTracker.handle(event, localPlayer: localPlayerID)
            if killer == localPlayerID {
                killsByWeapon[weaponID, default: 0] += 1
                haptics.kill()
                audio.playUI(headshot ? "sfx_kill_headshot" : "sfx_kill")
                hud.killConfirmTimestamp = sim.time
            }
            if victim == localPlayerID {
                haptics.death()
                audio.playUI("sfx_death")
            }

        case let .grenadeThrown(_, kind, entity, origin, _):
            renderer.effects.spawnGrenade(entity: entity, kind: kind, position: origin)
            audio.playSpatial("sfx_grenade_throw", at: origin, volume: 0.7)

        case let .grenadeBounced(_, position, surface):
            audio.playSpatial("sfx_grenade_bounce", at: position,
                              volume: 0.5 * surface.footstepVolume)

        case let .grenadeDetonated(entity, kind, position):
            renderer.effects.removeGrenade(entity: entity)
            if kind != .smoke && kind != .decoy {
                renderer.effects.explosion(position: position,
                                           radius: GrenadeDatabase.grenade(kind: kind).outerRadius,
                                           kind: kind)
                audio.playSpatial(kind == .flash ? "sfx_flash" : "sfx_explosion", at: position)
                if let player = sim.player(localPlayerID) {
                    let distance = player.position.distance(to: position)
                    let intensity = MathUtil.clamp(1 - distance / 18, 0, 1)
                    renderer.addCameraShake(intensity: intensity * 1.4)
                    haptics.explosion(distanceScale: intensity)
                }
            }

        case let .smokeStarted(entity, position, radius, duration):
            renderer.effects.startSmoke(entity: entity, position: position,
                                        radius: radius, duration: duration)
            audio.playSpatial("sfx_smoke", at: position)

        case let .fireStarted(entity, position, radius, duration):
            renderer.effects.startFire(entity: entity, position: position,
                                       radius: radius, duration: duration)
            audio.playSpatial("sfx_fire_loop", at: position)

        case let .footstep(player, position, surface, loud):
            guard player != localPlayerID else {
                audio.playUI(surface.footstepSound, volume: 0.25)
                return
            }
            audio.playSpatial(surface.footstepSound, at: position,
                              volume: (loud ? 1.0 : 0.65) * surface.footstepVolume)

        case let .flashed(player, intensity, _):
            if player == localPlayerID {
                audio.playUI("sfx_flash_ring", volume: intensity)
                haptics.explosion(distanceScale: intensity * 0.5)
            }

        case let .playerSpawned(player, _, team):
            if player == localPlayerID {
                renderer.setLocalPlayer(localPlayerID, team: team)
                if let state = sim.player(localPlayerID) {
                    controls.setAngles(yaw: state.angles.yaw, pitch: state.angles.pitch)
                    if let build = weaponBuilds[localPlayerID] {
                        renderer.viewModel.equip(build: build,
                                                 skin: build.skin.flatMap(CosmeticDatabase.cosmetic))
                    }
                }
            }

        case let .weaponSwitched(player, weaponID, _):
            guard player == localPlayerID else { return }
            var build = weaponBuilds[player] ?? WeaponBuild(weapon: weaponID)
            if build.weapon != weaponID { build = WeaponBuild(weapon: weaponID) }
            weaponBuilds[player] = build
            renderer.viewModel.equip(build: build,
                                     skin: build.skin.flatMap(CosmeticDatabase.cosmetic))
            audio.playUI("sfx_weapon_swap", volume: 0.7)

        case let .weaponReloadStarted(player, weaponID, _):
            let weapon = WeaponDatabase.weaponOrDefault(weaponID)
            if player == localPlayerID {
                audio.playUI(weapon.reloadSound)
            } else if let other = sim.player(player) {
                audio.playSpatial(weapon.reloadSound, at: other.position, volume: 0.6)
            }

        case .weaponDryFire:
            audio.playUI("sfx_dryfire", volume: 0.6)

        case let .bombPlanted(_, _, position):
            audio.playSpatial("sfx_bomb_planted", at: position)
            audio.duckMusic(to: 0.3)
            missionTracker.handle(event, localPlayer: localPlayerID)

        case .bombDefused:
            audio.playUI("sfx_bomb_defused")
            missionTracker.handle(event, localPlayer: localPlayerID)

        case let .bombExploded(position):
            renderer.effects.explosion(position: position, radius: 30, kind: .frag)
            renderer.addCameraShake(intensity: 3)
            audio.playSpatial("sfx_bomb_explode", at: position)

        case let .killStreak(player, count):
            if player == localPlayerID {
                audio.playUI("sfx_streak_\(min(count, 5))")
                hud.streakBanner = "\(count) KILL STREAK"
                hud.streakBannerTimestamp = sim.time
            }
            missionTracker.handle(event, localPlayer: localPlayerID)

        case let .firstBlood(player):
            hud.announcement = player == localPlayerID ? "FIRST BLOOD" : ""
            hud.announcementTimestamp = sim.time
            audio.playUI("sfx_first_blood")

        case let .roundStarted(round):
            hud.announcement = "ROUND \(round)"
            hud.announcementTimestamp = sim.time
            audio.playUI("sfx_round_start")

        case let .roundEnded(winner, _):
            let localTeam = sim.player(localPlayerID)?.team ?? .none
            hud.announcement = winner == localTeam ? "ROUND WON" : "ROUND LOST"
            hud.announcementTimestamp = sim.time
            audio.playUI(winner == localTeam ? "sfx_round_win" : "sfx_round_loss")

        case let .objectiveCaptured(_, team, by):
            if by.contains(localPlayerID) { audio.playUI("sfx_objective_captured") }
            let localTeam = sim.player(localPlayerID)?.team ?? .none
            hud.announcement = team == localTeam ? "OBJECTIVE SECURED" : "OBJECTIVE LOST"
            hud.announcementTimestamp = sim.time
            missionTracker.handle(event, localPlayer: localPlayerID)

        case let .pickupCollected(player, entity, kind):
            guard player == localPlayerID else { return }
            renderer.effects.removeVolume(entity: entity)
            audio.playUI("sfx_pickup")
            hud.announcement = kind.displayName.uppercased()
            hud.announcementTimestamp = sim.time

        case let .playerJoined(player, name, _, _):
            playerNames[player] = name

        case let .playerLeft(player):
            renderer.removePlayer(player)
            playerNames[player] = nil

        case let .matchEnded(result):
            handleMatchEnded(result)

        default:
            missionTracker.handle(event, localPlayer: localPlayerID)
        }
    }

    private func directionAngle(from: Vec3, to: Vec3, viewYaw: Float) -> Float {
        let toAttacker = (to - from).flattened
        guard toAttacker.lengthSquared > 0.01 else { return 0 }
        let worldAngle = atan2(-toAttacker.x, -toAttacker.z)
        return MathUtil.wrapAngle(worldAngle - viewYaw)
    }

    private func handleMatchEnded(_ result: MatchResult) {
        guard !isPaused else { return }
        isPaused = true
        onMatchEnded?(result)
    }

    // MARK: - UI actions

    func toggleScoreboard(_ show: Bool) {
        showScoreboard = show
        if show { scoreboard = sim.buildResult(winner: .none).scoreboard }
    }

    func toggleBuyMenu() {
        guard mode.usesBuyMenu else { return }
        showBuyMenu.toggle()
    }

    func buy(weapon: WeaponID) {
        guard sim.buy(localPlayerID, weapon: weapon) else {
            audio.playUI("sfx_error")
            return
        }
        weaponBuilds[localPlayerID] = WeaponBuild(weapon: weapon)
        audio.playUI("sfx_purchase")
    }

    func buy(grenade: ContentID) {
        guard sim.buyEquipment(localPlayerID, grenade: grenade) else {
            audio.playUI("sfx_error")
            return
        }
        audio.playUI("sfx_purchase")
    }

    func buyArmor(helmet: Bool) {
        guard sim.buyArmor(localPlayerID, withHelmet: helmet) else {
            audio.playUI("sfx_error")
            return
        }
        audio.playUI("sfx_purchase")
    }

    func sendPing(kind: PingKind) {
        guard let player = sim.player(localPlayerID) else { return }
        // Ping whatever the player is looking at, clamped to a sensible range.
        let trace = sim.world.trace(from: player.eyePosition,
                                    to: player.eyePosition + player.angles.forward * 60,
                                    mask: .solid)
        let position = trace.hit ? trace.point : player.eyePosition + player.angles.forward * 40
        sim.events.emit(.ping(player: localPlayerID, position: position, kind: kind))
        audio.playUI("sfx_ping")
    }

    func sendChat(_ text: String, teamOnly: Bool) {
        client?.sendChat(text, teamOnly: teamOnly)
        sim.events.emit(.chat(player: localPlayerID, message: ChatFilter.sanitize(text),
                              teamOnly: teamOnly))
    }

    var localPlayerState: PlayerState? { sim.player(localPlayerID) }
    var simulation: MatchSimulation { sim }
}

// MARK: - Render loop

extension GameSession: SCNSceneRendererDelegate {
    nonisolated func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        Task { @MainActor in
            let delta: Float
            if lastFrameTime == 0 {
                delta = Float(GameClock.tickInterval)
            } else {
                delta = Float(min(time - lastFrameTime, 0.1))
            }
            lastFrameTime = time
            self.renderer.updateDynamicResolution(frameTime: Double(delta))
            step(deltaTime: delta)
        }
    }
}
