import Foundation

public enum BotGoal: String, Sendable {
    case idle, patrol, engage, hunt, takeCover, reload, pushObjective, defendObjective,
         plantBomb, defuseBomb, collectItem, retreat, regroup
}

/// One bot's mind. Produces an `InputCommand` per tick — exactly the same interface a
/// human player uses, so bots are indistinguishable to the rest of the simulation and
/// can be swapped for a real player mid-match (backfill) without special casing.
public final class BotBrain {
    public let id: PlayerID
    public var difficulty: BotDifficulty
    public private(set) var goal: BotGoal = .idle

    private var profile: BotProfile
    private var rng: DeterministicRandom

    // Perception
    private var visibleEnemies: [PlayerID] = []
    private var target: PlayerID = .none
    private var targetFirstSeen: Float = 0
    private var targetLastSeen: Float = -999
    private var lastKnownPosition: Vec3 = .zero
    private var lastKnownVelocity: Vec3 = .zero
    private var heardPosition: Vec3?
    private var heardTime: Float = -999

    // Aim
    private var aimAngles = ViewAngles()
    private var aimError = Vec3.zero
    private var nextAimErrorRefresh: Float = 0
    private var triggerHeld = false
    private var burstTimer: Float = 0
    private var burstShotsLeft = 0

    // Navigation
    private var path: [Vec3] = []
    private var pathIndex = 0
    private var repathTimer: Float = 0
    private var destination: Vec3?
    private var stuckTimer: Float = 0
    private var lastPosition: Vec3 = .zero
    private var strafeDirection: Float = 1
    private var strafeTimer: Float = 0
    private var jumpCooldown: Float = 0
    private var grenadeCooldown: Float = 0

    public init(id: PlayerID, difficulty: BotDifficulty, seed: UInt64) {
        self.id = id
        self.difficulty = difficulty
        self.profile = difficulty.profile
        self.rng = DeterministicRandom(seed: seed)
    }

    public func setDifficulty(_ d: BotDifficulty) {
        difficulty = d
        profile = d.profile
    }

    // MARK: - Main entry point

    public func think(sim: MatchSimulation, dt: Float) -> InputCommand {
        guard let me = sim.player(id), me.isAlive else {
            return InputCommand(tick: sim.tick, deltaTime: dt)
        }
        repathTimer -= dt
        strafeTimer -= dt
        jumpCooldown -= dt
        grenadeCooldown -= dt
        burstTimer -= dt

        perceive(sim: sim, me: me)
        chooseGoal(sim: sim, me: me)

        var command = InputCommand(tick: sim.tick, deltaTime: dt, sequence: UInt16(sim.tick & 0xFFFF))
        steer(sim: sim, me: me, dt: dt, into: &command)
        aim(sim: sim, me: me, dt: dt, into: &command)
        useEquipment(sim: sim, me: me, into: &command)
        manageWeapon(sim: sim, me: me, into: &command)

        command.yaw = aimAngles.yaw
        command.pitch = aimAngles.pitch
        return command
    }

    // MARK: - Perception

    private func perceive(sim: MatchSimulation, me: PlayerState) {
        visibleEnemies.removeAll(keepingCapacity: true)
        let eye = me.eyePosition
        let forward = me.angles.forward
        let fovCos = cos(profile.fieldOfViewDegrees * 0.5 * MathUtil.deg2rad)

        var closest: (PlayerID, Float)?
        for enemy in sim.allPlayers() {
            guard enemy.isAlive, enemy.id != id else { continue }
            guard enemy.team != me.team || me.team == .none else { continue }
            let targetPoint = enemy.position + Vec3(0, 1.2, 0)
            let toTarget = targetPoint - eye
            let distance = toTarget.length
            guard distance < 130 else { continue }

            // Sound is checked even outside the view cone.
            let audible = MovementSystem.audibleRadius(of: enemy)
            if audible > 0 && distance < min(audible, profile.hearingRadius) {
                heardPosition = enemy.position
                heardTime = sim.time
            }
            if sim.time - enemy.lastFireTime < 0.4 && distance < profile.hearingRadius * 2.2 {
                heardPosition = enemy.position
                heardTime = sim.time
            }

            guard distance > 0.01, toTarget.normalized.dot(forward) >= fovCos else { continue }
            guard sim.world.hasLineOfSight(from: eye, to: targetPoint) else { continue }
            guard !sim.projectiles.smokeBlocks(from: eye, to: targetPoint) else { continue }
            // Being flashed genuinely blinds a bot too.
            guard me.flashAmount < 0.55 else { continue }

            visibleEnemies.append(enemy.id)
            if closest == nil || distance < closest!.1 { closest = (enemy.id, distance) }
        }

        // Decoy grenades pull bots exactly like real gunfire.
        for (position, team) in sim.projectiles.decoyNoiseSources() where team != me.team {
            if position.distance(to: me.position) < profile.hearingRadius * 2 {
                heardPosition = position
                heardTime = sim.time
            }
        }

        if let (best, _) = closest {
            if target != best {
                target = best
                targetFirstSeen = sim.time
            }
            targetLastSeen = sim.time
            if let t = sim.player(best) {
                lastKnownPosition = t.position
                lastKnownVelocity = t.velocity
            }
        } else if sim.time - targetLastSeen > profile.memoryDuration {
            target = .none
        }
    }

    // MARK: - Goal selection

    private func chooseGoal(sim: MatchSimulation, me: PlayerState) {
        let hasTarget = target.isValid && visibleEnemies.contains(target)
        let lowHealth = me.health < me.maxHealth * 0.3
        let slot = me.slots[me.activeSlot]
        let dry = (slot?.ammoInMagazine ?? 1) == 0 && (slot?.reserveAmmo ?? 0) > 0

        if dry {
            goal = .reload
            return
        }
        if hasTarget {
            goal = (lowHealth && rng.chance(profile.peekPatience)) ? .takeCover : .engage
            return
        }
        if sim.time - targetLastSeen < profile.memoryDuration && target.isValid {
            goal = .hunt
            return
        }
        if let heard = heardPosition, sim.time - heardTime < 5 {
            lastKnownPosition = heard
            goal = .hunt
            return
        }

        switch sim.state.mode.kind {
        case .bombDefusal, .searchAndRescue:
            goal = bombGoal(sim: sim, me: me)
        case .domination, .hardpoint:
            goal = objectiveGoal(sim: sim, me: me)
        default:
            goal = .patrol
        }
    }

    private func bombGoal(sim: MatchSimulation, me: PlayerState) -> BotGoal {
        let bomb = sim.state.bomb
        if me.team == .strike {
            if me.hasBomb { return bomb.isPlanted ? .defendObjective : .plantBomb }
            if bomb.isPlanted { return .defendObjective }
            return .pushObjective
        } else {
            if bomb.isPlanted { return .defuseBomb }
            return .defendObjective
        }
    }

    private func objectiveGoal(sim: MatchSimulation, me: PlayerState) -> BotGoal {
        if sim.state.mode.kind == .hardpoint { return .pushObjective }
        // Push an uncontrolled or enemy point; otherwise hold what we own.
        let ours = sim.state.captures.filter { $0.owner == me.team }.count
        return ours >= 2 ? .defendObjective : .pushObjective
    }

    // MARK: - Movement

    private func steer(sim: MatchSimulation, me: PlayerState, dt: Float, into command: inout InputCommand) {
        let desired = destinationForGoal(sim: sim, me: me)
        if let desired {
            let changed = destination.map { $0.distanceSquared(to: desired) > 9 } ?? true
            if changed || repathTimer <= 0 || path.isEmpty {
                destination = desired
                path = sim.nav.findPath(from: me.position, to: desired)
                pathIndex = 0
                repathTimer = rng.float(in: 0.6...1.2)
            }
        }

        // Stuck detection: bots that have not moved re-path and hop.
        if me.position.distance(to: lastPosition) < 0.12 && (goal != .engage || !visibleEnemies.isEmpty) {
            stuckTimer += dt
        } else {
            stuckTimer = 0
        }
        lastPosition = me.position
        if stuckTimer > 0.9 {
            stuckTimer = 0
            repathTimer = 0
            path.removeAll()
            if jumpCooldown <= 0 {
                command.buttons.insert(.jump)
                jumpCooldown = 1.2
            }
        }

        var moveTarget: Vec3?
        while pathIndex < path.count {
            let waypoint = path[pathIndex]
            if waypoint.flattened.distance(to: me.position.flattened) < 1.1 {
                pathIndex += 1
            } else {
                moveTarget = waypoint
                break
            }
        }
        if moveTarget == nil, let d = destination,
           d.flattened.distance(to: me.position.flattened) > 1.4 {
            moveTarget = d
        }

        if goal == .engage, let enemy = sim.player(target) {
            applyCombatMovement(sim: sim, me: me, enemy: enemy, moveTarget: moveTarget, into: &command)
            return
        }

        guard let moveTarget else { return }
        let toTarget = (moveTarget - me.position).flattened
        let local = worldToLocalMove(toTarget, yaw: me.angles.yaw)
        command.moveForward = local.forward
        command.moveRight = local.right
        // Sprint in the open when nothing is happening.
        if goal == .patrol || goal == .pushObjective || goal == .regroup {
            if toTarget.length > 6 && visibleEnemies.isEmpty { command.buttons.insert(.sprint) }
        }
        if goal == .plantBomb || goal == .defuseBomb {
            let objective = destination ?? moveTarget
            if objective.distance(to: me.position) < 2.0 { command.buttons.insert(.use) }
        }
    }

    private func applyCombatMovement(sim: MatchSimulation, me: PlayerState, enemy: PlayerState,
                                     moveTarget: Vec3?, into command: inout InputCommand) {
        let toEnemy = (enemy.position - me.position).flattened
        let distance = toEnemy.length
        var wish = Vec3.zero

        // Close the gap or back off toward the weapon's preferred range.
        let idealRange = min(profile.preferredRange, me.activeWeapon.falloffEnd * 0.7)
        if distance > idealRange * 1.25 {
            wish += toEnemy.normalized
        } else if distance < idealRange * 0.5 {
            wish -= toEnemy.normalized
        }

        // Strafe across the enemy's aim — the single most human-looking bot behaviour.
        if strafeTimer <= 0 {
            strafeDirection = rng.chance(0.5) ? 1 : -1
            strafeTimer = rng.float(in: 0.5...1.4)
        }
        let side = toEnemy.normalized.cross(Vec3.up).normalized
        wish += side * (strafeDirection * profile.strafeSkill)

        let local = worldToLocalMove(wish, yaw: me.angles.yaw)
        command.moveForward = local.forward
        command.moveRight = local.right

        // Crouch to steady a long shot.
        if distance > idealRange && rng.chance(profile.crouchSkill * 0.02) {
            command.buttons.insert(.crouch)
        }
        _ = moveTarget
    }

    private func destinationForGoal(sim: MatchSimulation, me: PlayerState) -> Vec3? {
        switch goal {
        case .engage:
            return nil
        case .hunt:
            return lastKnownPosition
        case .takeCover:
            return sim.nav.nearestCover(to: me.position, awayFrom: lastKnownPosition,
                                        searchRadius: 18, world: sim.world)
        case .plantBomb:
            let sites = sim.map.bombSites
            guard let site = sites.min(by: { $0.center.distance(to: me.position)
                                              < $1.center.distance(to: me.position) }) else { return nil }
            return site.center
        case .defuseBomb:
            return sim.state.bomb.isPlanted ? sim.state.bomb.position : nil
        case .pushObjective:
            return pushTarget(sim: sim, me: me)
        case .defendObjective:
            return defendTarget(sim: sim, me: me)
        case .patrol, .idle, .regroup, .collectItem, .retreat, .reload:
            if let d = destination, d.distance(to: me.position) > 2.5, !path.isEmpty { return d }
            return sim.nav.randomNode(rng: &rng)
        }
    }

    private func pushTarget(sim: MatchSimulation, me: PlayerState) -> Vec3? {
        switch sim.state.mode.kind {
        case .hardpoint:
            guard sim.map.hardpoints.indices.contains(sim.state.activeHardpoint) else { return nil }
            return sim.map.hardpoints[sim.state.activeHardpoint].center
        case .domination:
            let wanted = sim.state.captures.first { $0.owner != me.team }
            guard let wanted,
                  let zone = sim.map.capturePoints.first(where: { $0.index == wanted.index })
            else { return sim.map.capturePoints.first?.center }
            return zone.center
        case .bombDefusal, .searchAndRescue:
            return sim.map.bombSites.min { $0.center.distance(to: me.position)
                                         < $1.center.distance(to: me.position) }?.center
        default:
            return sim.nav.randomNode(rng: &rng)
        }
    }

    private func defendTarget(sim: MatchSimulation, me: PlayerState) -> Vec3? {
        switch sim.state.mode.kind {
        case .bombDefusal, .searchAndRescue:
            if sim.state.bomb.isPlanted { return sim.state.bomb.position }
            return sim.map.bombSites.randomElementDeterministic(&rng)?.center
        case .domination:
            let ours = sim.state.captures.filter { $0.owner == me.team }
            guard let pick = ours.randomElementDeterministic(&rng),
                  let zone = sim.map.capturePoints.first(where: { $0.index == pick.index })
            else { return nil }
            return zone.center
        default:
            return sim.nav.randomNode(rng: &rng)
        }
    }

    private func worldToLocalMove(_ world: Vec3, yaw: Float) -> (forward: Float, right: Float) {
        guard world.lengthSquared > 1e-5 else { return (0, 0) }
        let dir = world.normalized
        let angles = ViewAngles(pitch: 0, yaw: yaw)
        return (MathUtil.clamp(dir.dot(angles.groundForward), -1, 1),
                MathUtil.clamp(dir.dot(angles.right), -1, 1))
    }

    // MARK: - Aiming and firing

    private func aim(sim: MatchSimulation, me: PlayerState, dt: Float, into command: inout InputCommand) {
        var desired: ViewAngles

        if target.isValid, let enemy = sim.player(target), enemy.isAlive {
            let visible = visibleEnemies.contains(target)
            let aimPoint = predictedAimPoint(me: me, enemy: enemy, visible: visible)
            desired = ViewAngles.looking(from: me.eyePosition, at: aimPoint + currentAimError())
        } else if sim.time - heardTime < 4, let heard = heardPosition {
            desired = ViewAngles.looking(from: me.eyePosition, at: heard + Vec3(0, 1.2, 0))
        } else if pathIndex < path.count {
            // Look where we are going, one waypoint ahead so corners are pre-aimed.
            let lookIndex = min(pathIndex + 1, path.count - 1)
            desired = ViewAngles.looking(from: me.eyePosition, at: path[lookIndex] + Vec3(0, 1.5, 0))
        } else {
            desired = aimAngles
        }

        // Flashed bots flail.
        if me.flashAmount > 0.3 {
            desired.yaw += rng.signedUnit() * me.flashAmount * 0.6
            desired.pitch += rng.signedUnit() * me.flashAmount * 0.25
        }

        let slew = profile.aimSpeed * dt * (visibleEnemies.contains(target) ? 1.0 : 0.55)
        aimAngles.yaw = MathUtil.moveAngleTowards(aimAngles.yaw, desired.yaw, maxDelta: slew)
        aimAngles.pitch = MathUtil.moveTowards(aimAngles.pitch, desired.pitch, maxDelta: slew)
        // Permanent low-amplitude tremor.
        let jitter = profile.trackingJitter * MathUtil.deg2rad * 0.35
        aimAngles.yaw += rng.signedUnit() * jitter * dt * 8
        aimAngles.pitch += rng.signedUnit() * jitter * dt * 8
        aimAngles.clampPitch()

        // Counter recoil the way a decent player would.
        if triggerHeld {
            aimAngles.pitch -= me.recoilOffset.pitch * profile.burstDiscipline * dt * 6
        }

        decideFiring(sim: sim, me: me, dt: dt, into: &command)
    }

    private func predictedAimPoint(me: PlayerState, enemy: PlayerState, visible: Bool) -> Vec3 {
        let distance = me.position.distance(to: enemy.position)
        let weapon = me.activeWeapon
        // Aim for the head only as often as the difficulty allows.
        let wantsHead = rng.chance(profile.headshotPreference)
        let heightOffset: Float = wantsHead ? 1.62 : 1.15
        var point = (visible ? enemy.position : lastKnownPosition) + Vec3(0, heightOffset * enemy.stance.heightScale, 0)

        // Lead the target slightly; hitscan needs none, but it makes tracking look natural.
        let lead = MathUtil.clamp(distance / 90, 0, 0.25) * profile.accuracyOverDistance
        point += (visible ? enemy.velocity : lastKnownVelocity) * lead
        _ = weapon
        return point
    }

    private func currentAimError() -> Vec3 {
        aimError
    }

    private func refreshAimError(now: Float, distance: Float) {
        guard now >= nextAimErrorRefresh else { return }
        nextAimErrorRefresh = now + rng.float(in: 0.18...0.45)
        // Error grows with distance and shrinks with difficulty.
        let degrees = profile.aimErrorDegrees
            * MathUtil.lerp(1.0, 2.0 - profile.accuracyOverDistance, MathUtil.clamp(distance / 60, 0, 1))
        let radius = tan(degrees * MathUtil.deg2rad) * max(distance, 1)
        let (dx, dy) = rng.insideUnitDisk()
        aimError = Vec3(dx * radius, dy * radius * 0.6, 0)
    }

    private func decideFiring(sim: MatchSimulation, me: PlayerState, dt: Float,
                              into command: inout InputCommand) {
        guard target.isValid, visibleEnemies.contains(target), let enemy = sim.player(target) else {
            triggerHeld = false
            burstShotsLeft = 0
            return
        }
        let distance = me.position.distance(to: enemy.position)
        refreshAimError(now: sim.time, distance: distance)

        // Reaction delay from first acquisition.
        guard sim.time - targetFirstSeen >= profile.reactionTime else { return }

        let weapon = me.activeWeapon
        // Only shoot when actually pointed at the target, otherwise bots spray at walls.
        let toEnemy = (enemy.position + Vec3(0, 1.2, 0) - me.eyePosition).normalized
        let aimDot = aimAngles.forward.dot(toEnemy)
        let toleranceDegrees = MathUtil.lerp(9, 2.5, profile.accuracyOverDistance)
        guard aimDot > cos(toleranceDegrees * MathUtil.deg2rad) else { return }

        // Aim down sights when it helps.
        if weapon.weaponClass != .shotgun && weapon.weaponClass != .melee
            && distance > 8 && profile.burstDiscipline > 0.4 {
            command.buttons.insert(.aim)
        }

        switch weapon.fireMode {
        case .auto:
            // Burst control: fire in bursts sized by discipline, then let recoil settle.
            if burstShotsLeft <= 0 && burstTimer <= 0 {
                burstShotsLeft = max(2, Int((1 - profile.burstDiscipline) * 12 + 3))
                burstTimer = 0
            }
            if burstShotsLeft > 0 {
                command.buttons.insert(.fire)
                triggerHeld = true
                burstShotsLeft -= 1
                if burstShotsLeft == 0 {
                    burstTimer = MathUtil.lerp(0.12, 0.45, profile.burstDiscipline)
                }
            } else {
                triggerHeld = false
            }
        default:
            command.buttons.insert(.fire)
            triggerHeld = true
        }
        _ = dt
    }

    // MARK: - Equipment

    private func useEquipment(sim: MatchSimulation, me: PlayerState, into command: inout InputCommand) {
        guard grenadeCooldown <= 0, me.lethalCount > 0 || me.tacticalCount > 0 else { return }
        guard target.isValid, let enemy = sim.player(target) else { return }
        let distance = me.position.distance(to: enemy.position)
        guard distance > 8, distance < 32 else { return }
        guard rng.chance(profile.grenadeChance * 0.02) else { return }

        // Throw smoke/flash when pushing, frags when the target is holding still.
        if me.tacticalCount > 0 && (goal == .pushObjective || goal == .plantBomb) {
            command.buttons.insert(.tactical)
        } else if me.lethalCount > 0 {
            command.buttons.insert(.lethal)
        }
        grenadeCooldown = rng.float(in: 6...14)
    }

    private func manageWeapon(sim: MatchSimulation, me: PlayerState, into command: inout InputCommand) {
        guard let slot = me.slots[me.activeSlot] else { return }
        let weapon = slot.resolvedWeapon

        if slot.ammoInMagazine == 0 {
            if slot.reserveAmmo > 0 {
                command.buttons.insert(.reload)
            } else if me.slots[.secondary] != nil && me.activeSlot != .secondary {
                command.requestedSlot = .secondary
            } else if me.slots[.melee] != nil {
                command.requestedSlot = .melee
            }
            return
        }
        // Top up between fights, as a real player does.
        let magRatio = Float(slot.ammoInMagazine) / Float(max(weapon.magazineSize, 1))
        if visibleEnemies.isEmpty && magRatio < 0.45 && slot.reserveAmmo > 0
            && rng.chance(profile.reloadDiscipline * 0.08) {
            command.buttons.insert(.reload)
        }
        // Knife out when running a long way with nothing around.
        if visibleEnemies.isEmpty && goal == .patrol && me.activeSlot == .primary
            && rng.chance(0.0005) {
            command.requestedSlot = .melee
        } else if !visibleEnemies.isEmpty && me.activeSlot == .melee && me.slots[.primary] != nil {
            command.requestedSlot = .primary
        }
    }
}

extension Array {
    /// Deterministic replacement for `randomElement()` so bot behaviour replays identically.
    func randomElementDeterministic(_ rng: inout DeterministicRandom) -> Element? {
        isEmpty ? nil : self[rng.int(in: 0...(count - 1))]
    }
}
