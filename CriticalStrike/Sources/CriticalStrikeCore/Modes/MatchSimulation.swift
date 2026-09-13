import Foundation

public struct PickupInstance: Sendable {
    public var entity: EntityID
    public var kind: PickupKind
    public var position: Vec3
    public var weapon: WeaponID?
    public var ammo: Int
    public var respawnTimer: Countdown
    public var isActive: Bool
    public var droppedByPlayer: Bool
    public var dogTagOwner: PlayerID
    public var dogTagTeam: Team
}

/// The authoritative simulation. One instance runs on the host (a dedicated server, the
/// match host in a peer-hosted game, or locally for bot matches). Clients run the same
/// class for prediction. It owns no rendering, no I/O and no timers of its own —
/// `step(deltaTime:)` is the only way time moves.
public final class MatchSimulation {
    public let map: MapData
    public let world: CollisionWorld
    public let nav: NavGraph
    public let events: EventBus

    public internal(set) var state: MatchState
    public internal(set) var players: [PlayerID: PlayerState] = [:]
    public internal(set) var playerOrder: [PlayerID] = []
    public let projectiles = ProjectileSystem()
    public internal(set) var pickups: [PickupInstance] = []
    public internal(set) var killFeed: [KillFeedEntry] = []
    public internal(set) var time: Float = 0
    public internal(set) var tick: UInt32 = 0
    public internal(set) var xpAwards: [PlayerID: Int] = [:]

    public var rng: DeterministicRandom
    public var localPlayer: PlayerID = .none
    public var onMatchEnded: ((MatchResult) -> Void)?

    internal var rules: GameModeRules
    private var inputs: [PlayerID: InputCommand] = [:]
    private var nextPlayerRaw: UInt8 = 0
    private var nextPickupEntity: UInt16 = 1
    internal var shotsFired: [PlayerID: Int] = [:]
    internal var shotsHit: [PlayerID: Int] = [:]
    private var matchStartTime: Float = 0

    public init(map: MapData, mode: GameModeData, seed: UInt64 = 0x5C0FFEE, events: EventBus = EventBus()) {
        self.map = map
        self.world = CollisionWorld(map: map)
        self.nav = NavGraph(map: map, world: world)
        self.events = events
        self.state = MatchState(mode: mode, mapID: map.id)
        self.rng = DeterministicRandom(seed: seed)
        self.rules = GameModeRulesFactory.rules(for: mode.kind)
        setupPickups()
        state.captures = map.capturePoints.map { CaptureState(index: $0.index) }
        state.phaseTimer.start(max(0.5, mode.warmupSeconds))
        if mode.timeLimitSeconds > 0 { state.matchTimer.start(mode.timeLimitSeconds) }
    }

    // MARK: - Roster

    @discardableResult
    public func addPlayer(name: String, team: Team, isBot: Bool, loadout: Loadout) -> PlayerID {
        let id = PlayerID(rawValue: nextPlayerRaw)
        nextPlayerRaw = nextPlayerRaw &+ 1
        var player = PlayerState(id: id, name: name, team: team, isBot: isBot, loadout: loadout)
        player.giveLoadout(loadout, mode: state.mode)
        player.money = state.mode.startingMoney
        players[id] = player
        playerOrder.append(id)
        events.emit(.playerJoined(player: id, name: name, team: team, isBot: isBot))
        if state.mode.kind.allowsRespawn || state.phase == .warmup {
            respawn(id)
        }
        return id
    }

    public func removePlayer(_ id: PlayerID) {
        guard players[id] != nil else { return }
        players[id] = nil
        playerOrder.removeAll { $0 == id }
        inputs[id] = nil
        projectiles.removeEffects(ownedBy: id)
        events.emit(.playerLeft(player: id))
    }

    public func setTeam(_ id: PlayerID, team: Team) {
        guard var p = players[id] else { return }
        p.team = team
        players[id] = p
        events.emit(.teamChanged(player: id, team: team))
    }

    public func player(_ id: PlayerID) -> PlayerState? { players[id] }
    public func alivePlayers(team: Team) -> [PlayerState] {
        playerOrder.compactMap { players[$0] }.filter { $0.isAlive && $0.team == team }
    }
    public func allPlayers() -> [PlayerState] { playerOrder.compactMap { players[$0] } }
    public func teamCount(_ team: Team) -> Int { allPlayers().filter { $0.team == team }.count }

    public func setInput(_ command: InputCommand, for id: PlayerID) {
        inputs[id] = command.sanitized()
    }

    /// Direct mutation hook used by AI, mode rules and network application.
    public func mutatePlayer(_ id: PlayerID, _ body: (inout PlayerState) -> Void) {
        guard var p = players[id] else { return }
        body(&p)
        players[id] = p
    }

    // MARK: - Main loop

    public func step(deltaTime dt: Float) {
        time += dt
        tick &+= 1

        stepPhase(dt: dt)

        let movementCtx = MovementSystem.Context(world: world, now: time, events: events)
        let canAct = state.phase.allowsMovement

        for id in playerOrder {
            guard var player = players[id] else { continue }
            guard player.isAlive else {
                stepRespawn(&player, dt: dt)
                players[id] = player
                continue
            }

            var input = inputs[id] ?? InputCommand(tick: tick, deltaTime: dt)
            input.deltaTime = dt
            if !canAct {
                // Freeze time: players may look around and buy, not move or shoot.
                input.moveForward = 0
                input.moveRight = 0
                input.buttons = input.buttons.intersection([.aim, .reload, .swapWeapon])
            }

            player.isUsing = input.buttons.contains(.use)
            MovementSystem.step(player: &player, input: input, ctx: movementCtx)
            stepStatusEffects(&player, dt: dt)

            let targets = hitVolumes(excluding: id)
            let weaponCtx = WeaponStepContext(world: world, targets: targets, now: time,
                                              friendlyFire: state.mode.friendlyFire,
                                              events: events, mode: state.mode.kind)
            let before = player.slots[player.activeSlot]?.ammoInMagazine ?? 0
            let outcomes = WeaponSystem.step(player: &player, input: input, ctx: weaponCtx, rng: &rng)
            let after = player.slots[player.activeSlot]?.ammoInMagazine ?? 0
            if after < before { shotsFired[id, default: 0] += (before - after) }

            players[id] = player
            applyOutcomes(outcomes, from: id)
            checkPickups(for: id)
        }

        // Projectiles and lingering effects.
        let explosions = projectiles.step(dt: dt, world: world, events: events)
        for explosion in explosions { resolveExplosion(explosion) }
        applyAreaEffectDamage(dt: dt)
        stepPickupRespawns(dt: dt)

        rules.tick(sim: self, dt: dt)

        if state.phase == .live, let (winner, reason) = rules.checkRoundEnd(sim: self) {
            endRound(winner: winner, reason: reason)
        }
        trimKillFeed()
    }

    // MARK: - Phases

    private func stepPhase(dt: Float) {
        if state.mode.timeLimitSeconds > 0 && state.phase == .live {
            if state.matchTimer.tick(dt) {
                endMatchByTime()
                return
            }
        }

        guard state.phaseTimer.tick(dt) else {
            if state.phase == .warmup {
                let left = Int(ceil(state.phaseTimer.remaining))
                if left != lastWarmupSecond {
                    lastWarmupSecond = left
                    events.emit(.warmupTick(secondsLeft: left))
                }
            }
            return
        }

        switch state.phase {
        case .warmup:
            startMatch()
        case .freezeTime:
            state.phase = .live
            state.phaseTimer.start(state.mode.roundTimeSeconds)
            events.emit(.roundStarted(round: state.round))
        case .live:
            // Round timer expired.
            let (winner, reason) = rules.roundTimeExpired(sim: self)
            endRound(winner: winner, reason: reason)
        case .roundEnd:
            if let result = rules.checkMatchEnd(sim: self) {
                finishMatch(result)
            } else {
                beginRound()
            }
        case .intermission:
            beginRound()
        case .matchEnd:
            break
        }
    }

    private var lastWarmupSecond = -1

    public func startMatch() {
        matchStartTime = time
        state.round = 0
        state.scores = [.strike: 0, .shield: 0, .none: 0]
        state.roundWins = [.strike: 0, .shield: 0]
        state.firstBloodTaken = false
        events.emit(.matchStarted(mode: state.mode.kind, map: map.id))
        rules.matchStarted(sim: self)
        beginRound()
    }

    public func beginRound() {
        state.round += 1
        state.bomb = BombState()
        state.captures = map.capturePoints.map { CaptureState(index: $0.index) }
        projectiles.reset()
        resetPickups()

        for id in playerOrder {
            guard var p = players[id] else { continue }
            if state.mode.kind.isRoundBased {
                p.giveLoadout(p.loadout, mode: state.mode)
            }
            players[id] = p
            respawn(id, force: true)
        }
        rules.roundStarted(sim: self)

        if state.mode.freezeTimeSeconds > 0 {
            state.phase = .freezeTime
            state.phaseTimer.start(state.mode.freezeTimeSeconds)
        } else {
            state.phase = .live
            state.phaseTimer.start(state.mode.roundTimeSeconds > 0 ? state.mode.roundTimeSeconds : 3600)
            events.emit(.roundStarted(round: state.round))
        }
    }

    public func endRound(winner: Team, reason: RoundEndReason) {
        guard state.phase == .live || state.phase == .freezeTime else { return }
        state.phase = .roundEnd
        state.phaseTimer.start(5.0)
        if winner != .none {
            state.roundWins[winner, default: 0] += 1
            if state.mode.kind.isRoundBased { state.addScore(winner, 1) }
        }
        rules.roundEnded(sim: self, winner: winner, reason: reason)
        events.emit(.roundEnded(winner: winner, reason: reason))
        events.emit(.scoreChanged(strike: state.score(.strike), shield: state.score(.shield)))

        // Swap sides at halftime in round-based modes.
        if state.mode.kind.isRoundBased && !state.sidesSwapped
            && state.round == state.halftimeRound {
            swapSides()
        }
    }

    private func swapSides() {
        state.sidesSwapped = true
        for id in playerOrder {
            guard var p = players[id] else { continue }
            p.team = p.team.opponent
            players[id] = p
            events.emit(.teamChanged(player: id, team: p.team))
        }
        let strike = state.score(.strike)
        state.scores[.strike] = state.score(.shield)
        state.scores[.shield] = strike
        let wins = state.roundWins[.strike] ?? 0
        state.roundWins[.strike] = state.roundWins[.shield] ?? 0
        state.roundWins[.shield] = wins
        state.phase = .intermission
        state.phaseTimer.start(8)
    }

    private func endMatchByTime() {
        let winner = state.leadingTeam
        if state.isTied && state.mode.overtimeEnabled && state.mode.kind.isTeamBased {
            state.overtimeRound += 1
            state.matchTimer.start(120)
            state.phase = .roundEnd
            state.phaseTimer.start(4)
            return
        }
        finishMatch(buildResult(winner: winner))
    }

    public func finishMatch(_ result: MatchResult) {
        state.phase = .matchEnd
        state.phaseTimer.start(12)
        events.emit(.matchEnded(result: result))
        onMatchEnded?(result)
    }

    public func buildResult(winner: Team) -> MatchResult {
        var results: [PlayerResult] = []
        for id in playerOrder {
            guard let p = players[id] else { continue }
            let fired = Float(shotsFired[id] ?? 0)
            let hit = Float(shotsHit[id] ?? 0)
            results.append(PlayerResult(player: id, name: p.name, team: p.team, isBot: p.isBot,
                                        kills: p.kills, deaths: p.deaths, assists: p.assists,
                                        score: p.score, damage: p.damageDealt,
                                        headshots: p.headshots, bestStreak: p.bestStreak,
                                        xpEarned: xpAwards[id] ?? 0,
                                        accuracy: fired > 0 ? hit / fired : 0))
        }
        let mvp = results.max { a, b in a.score < b.score }?.player ?? .none
        results = results.map { r in
            var copy = r
            copy.mvp = r.player == mvp
            return copy
        }
        let localWon = players[localPlayer].map { winner == .none ? false : $0.team == winner } ?? false
        return MatchResult(mode: state.mode.kind, map: map.id, winner: winner,
                           localPlayerWon: localWon,
                           strikeScore: state.score(.strike), shieldScore: state.score(.shield),
                           durationSeconds: time - matchStartTime, results: results, mvp: mvp)
    }

    // MARK: - Spawning

    public func respawn(_ id: PlayerID, force: Bool = false) {
        guard var player = players[id] else { return }
        guard force || rules.canRespawn(sim: self, player: id) else { return }
        let spawn = selectSpawn(for: player)
        player.resetForRespawn(at: spawn, mode: state.mode, now: time)
        if state.mode.kind == .gunGame {
            let index = min(player.gunGameLevel, GameModeDatabase.gunGameLadder.count - 1)
            player.slots[.primary] = WeaponSlotState(build: WeaponBuild(weapon: GameModeDatabase.gunGameLadder[index]))
            player.activeSlot = .primary
        } else if state.mode.kind == .oneInTheChamber {
            var build = WeaponSlotState(build: WeaponBuild(weapon: "pst_magnum"))
            build.ammoInMagazine = 1
            build.reserveAmmo = 0
            player.slots[.primary] = build
            player.activeSlot = .primary
        }
        players[id] = player
        events.emit(.playerSpawned(player: id, position: spawn.position, team: player.team))
    }

    private func stepRespawn(_ player: inout PlayerState, dt: Float) {
        guard state.mode.kind.allowsRespawn, state.phase == .live || state.phase == .warmup else { return }
        if player.respawnTimer.tick(dt) {
            let id = player.id
            players[id] = player
            respawn(id)
            if let refreshed = players[id] { player = refreshed }
        }
    }

    /// Picks the spawn furthest from enemies but still near friends — the standard
    /// "don't spawn me in front of a rifle" heuristic.
    public func selectSpawn(for player: PlayerState) -> SpawnPoint {
        let candidates = map.spawns(for: player.team)
        guard !candidates.isEmpty else {
            return SpawnPoint(position: map.bounds.center, yaw: 0, team: player.team)
        }
        let enemies = allPlayers().filter { $0.isAlive && $0.team != player.team && $0.id != player.id }
        let friends = allPlayers().filter { $0.isAlive && $0.team == player.team && $0.id != player.id }

        var best = candidates[0]
        var bestScore = -Float.greatestFiniteMagnitude
        for spawn in candidates {
            var score = Float(spawn.priority) * 0.5
            var nearestEnemy = Float.greatestFiniteMagnitude
            for e in enemies {
                let d = e.position.distance(to: spawn.position)
                nearestEnemy = min(nearestEnemy, d)
                if world.hasLineOfSight(from: e.eyePosition, to: spawn.position + Vec3(0, 1.6, 0)) {
                    score -= 55   // never spawn in an enemy's sightline if avoidable
                }
            }
            if nearestEnemy < .greatestFiniteMagnitude {
                score += min(nearestEnemy, 45)
            } else {
                score += 45
            }
            if let nearestFriend = friends.map({ $0.position.distance(to: spawn.position) }).min() {
                score += max(0, 20 - nearestFriend) * 0.4
            }
            score += rng.unit() * 4     // break ties so spawns do not feel scripted
            if score > bestScore { bestScore = score; best = spawn }
        }
        return best
    }

    // MARK: - Hit volumes

    public func hitVolumes(excluding id: PlayerID) -> [HitVolume] {
        playerOrder.compactMap { pid -> HitVolume? in
            guard pid != id, let p = players[pid], p.isAlive else { return nil }
            return HitVolume(player: pid, team: p.team, position: p.position,
                             crouchScale: p.stance.heightScale, isAlive: true)
        }
    }

    // MARK: - Kill feed

    func pushKillFeed(_ entry: KillFeedEntry) {
        killFeed.append(entry)
        if killFeed.count > 12 { killFeed.removeFirst(killFeed.count - 12) }
    }

    private func trimKillFeed() {
        killFeed.removeAll { time - $0.timestamp > 7 }
    }

    func recordHit(_ shooter: PlayerID) { shotsHit[shooter, default: 0] += 1 }
    func awardXP(_ player: PlayerID, _ amount: Int, reason: String) {
        guard amount > 0 else { return }
        let scaled = Int(Float(amount) * state.mode.xpMultiplier)
        xpAwards[player, default: 0] += scaled
        events.emit(.xpAwarded(player: player, amount: scaled, reason: reason))
    }

    // MARK: - Pickups

    private func setupPickups() {
        pickups = map.pickups.enumerated().map { index, spawn in
            nextPickupEntity = nextPickupEntity &+ 1
            return PickupInstance(entity: EntityID(rawValue: 2000 + UInt16(index)),
                                  kind: spawn.kind, position: spawn.position,
                                  weapon: spawn.weapon, ammo: 0, respawnTimer: Countdown(),
                                  isActive: true, droppedByPlayer: false,
                                  dogTagOwner: .none, dogTagTeam: .none)
        }
    }

    private func resetPickups() {
        pickups.removeAll { $0.droppedByPlayer }
        for i in pickups.indices {
            pickups[i].isActive = true
            pickups[i].respawnTimer.stop()
        }
    }

    func spawnPickup(kind: PickupKind, at position: Vec3, weapon: WeaponID? = nil, ammo: Int = 0,
                     dogTagOwner: PlayerID = .none, dogTagTeam: Team = .none) {
        nextPickupEntity = nextPickupEntity &+ 1
        let entity = EntityID(rawValue: 3000 &+ nextPickupEntity)
        pickups.append(PickupInstance(entity: entity, kind: kind, position: position,
                                      weapon: weapon, ammo: ammo, respawnTimer: Countdown(),
                                      isActive: true, droppedByPlayer: true,
                                      dogTagOwner: dogTagOwner, dogTagTeam: dogTagTeam))
        events.emit(.pickupSpawned(entity: entity, position: position, kind: kind))
    }

    private func stepPickupRespawns(dt: Float) {
        for i in pickups.indices where !pickups[i].isActive {
            if pickups[i].respawnTimer.tick(dt) { pickups[i].isActive = true }
        }
    }

    private func checkPickups(for id: PlayerID) {
        guard var player = players[id], player.isAlive else { return }
        for i in pickups.indices {
            guard pickups[i].isActive else { continue }
            let d = pickups[i].position.distance(to: player.position + Vec3(0, 0.8, 0))
            guard d < 1.4 else { continue }
            guard rules.shouldCollect(sim: self, pickup: pickups[i], by: player) else { continue }
            if collect(pickup: pickups[i], player: &player) {
                let kind = pickups[i].kind
                events.emit(.pickupCollected(player: id, entity: pickups[i].entity, kind: kind))
                rules.pickupCollected(sim: self, pickup: pickups[i], by: id)
                if pickups[i].droppedByPlayer {
                    pickups.remove(at: i)
                } else {
                    pickups[i].isActive = false
                    pickups[i].respawnTimer.start(kind.respawnTime)
                }
                break
            }
        }
        players[id] = player
    }

    private func collect(pickup: PickupInstance, player: inout PlayerState) -> Bool {
        switch pickup.kind {
        case .health:
            guard player.health < player.maxHealth else { return false }
            let healed = min(50, player.maxHealth - player.health)
            player.health += healed
            events.emit(.playerHealed(player: player.id, amount: healed))
        case .armor:
            guard player.armor < player.maxArmor else { return false }
            player.armor = player.maxArmor
            player.hasHelmet = true
        case .ammo:
            var topped = false
            for slot in Array(player.slots.keys) {
                guard var s = player.slots[slot] else { continue }
                let w = s.resolvedWeapon
                if s.reserveAmmo < w.reserveAmmo {
                    s.reserveAmmo = w.reserveAmmo
                    player.slots[slot] = s
                    topped = true
                }
            }
            guard topped else { return false }
        case .weapon:
            guard let weaponID = pickup.weapon else { return false }
            let slot = WeaponDatabase.weaponOrDefault(weaponID).weaponClass.slot
            var s = WeaponSlotState(build: WeaponBuild(weapon: weaponID))
            if pickup.ammo > 0 { s.ammoInMagazine = pickup.ammo }
            player.slots[slot] = s
            player.activeSlot = slot
            player.action = .drawing
            player.actionTimer.start(0.4)
        case .bomb:
            player.hasBomb = true
            events.emit(.bombPickedUp(player: player.id))
        case .defuseKit:
            guard !player.hasDefuseKit else { return false }
            player.hasDefuseKit = true
        case .powerupDamage:
            player.doubleDamageUntil = time + PickupKind.powerupDamage.powerupDuration
        case .powerupSpeed:
            player.speedBoostUntil = time + PickupKind.powerupSpeed.powerupDuration
        case .powerupShield:
            player.overshieldUntil = time + PickupKind.powerupShield.powerupDuration
            player.armor = player.maxArmor
        }
        return true
    }

    // MARK: - Status effects

    private func stepStatusEffects(_ player: inout PlayerState, dt: Float) {
        // Flash fades on a curve: full blind, then a fast wash-out.
        if player.flashAmount > 0 {
            player.flashAmount = max(0, player.flashAmount - player.flashDecayRate * dt)
        }
        if player.stunAmount > 0 {
            player.stunAmount = max(0, player.stunAmount - dt * 0.6)
        }
        // Health regeneration.
        if state.mode.healthRegen && player.health < player.maxHealth {
            let delay = state.mode.regenDelay * player.perks.regenDelayScale
            if time - player.lastDamagedAt >= delay {
                let before = player.health
                player.health = min(player.maxHealth, player.health + state.mode.regenRate * dt)
                if Int(player.health) > Int(before) + 4 {
                    events.emit(.playerHealed(player: player.id, amount: player.health - before))
                }
            }
        }
        if projectiles.isInSmoke(player.eyePosition) { player.inSmokeUntil = time + 0.2 }
    }

    private func applyAreaEffectDamage(dt: Float) {
        for effect in projectiles.areaEffects where effect.burns {
            for id in playerOrder {
                guard let p = players[id], p.isAlive else { continue }
                guard effect.contains(p.position) else { continue }
                let sameTeam = p.team == effect.team && p.id != effect.owner
                let scale: Float = p.id == effect.owner ? 1.0 : (sameTeam ? 0.4 : 1.0)
                if sameTeam && !state.mode.friendlyFire { continue }
                let damage = 14 * dt * scale * (1 - p.perks.explosiveResistance)
                applyDamage(to: id, from: effect.owner, amount: damage, hitbox: .leg,
                            weapon: "nade_molotov", isExplosive: true, position: p.position)
                mutatePlayer(id) { $0.burningUntil = time + 0.6 }
            }
        }
    }

    // MARK: - Buy menu (round-based modes)

    @discardableResult
    public func buy(_ id: PlayerID, weapon weaponID: WeaponID) -> Bool {
        guard state.phase == .freezeTime || state.mode.kind == .zombies else { return false }
        guard var player = players[id], let weapon = WeaponDatabase.weapon(weaponID) else { return false }
        guard player.money >= weapon.buyCost else { return false }
        player.money -= weapon.buyCost
        let slot = weapon.weaponClass.slot
        player.slots[slot] = WeaponSlotState(build: WeaponBuild(weapon: weaponID),
                                             extraMagazines: player.perks.extraMagazines)
        player.activeSlot = slot
        players[id] = player
        return true
    }

    @discardableResult
    public func buyEquipment(_ id: PlayerID, grenade grenadeID: ContentID) -> Bool {
        guard state.phase == .freezeTime || state.mode.kind == .zombies else { return false }
        guard var player = players[id], let data = GrenadeDatabase.grenade(grenadeID) else { return false }
        guard player.money >= data.buyCost else { return false }
        if data.kind.slot == .lethal {
            guard player.lethalCount < data.maxCarried + player.perks.extraGrenades else { return false }
            player.lethalID = grenadeID
            player.lethalCount += 1
        } else {
            guard player.tacticalCount < data.maxCarried + player.perks.extraGrenades else { return false }
            player.tacticalID = grenadeID
            player.tacticalCount += 1
        }
        player.money -= data.buyCost
        players[id] = player
        return true
    }

    @discardableResult
    public func buyArmor(_ id: PlayerID, withHelmet: Bool) -> Bool {
        guard state.phase == .freezeTime else { return false }
        guard var player = players[id] else { return false }
        let cost = withHelmet ? 1000 : 650
        guard player.money >= cost, player.armor < player.maxArmor || (withHelmet && !player.hasHelmet) else {
            return false
        }
        player.money -= cost
        player.armor = player.maxArmor
        player.hasHelmet = withHelmet
        players[id] = player
        return true
    }

    func giveMoney(_ id: PlayerID, _ amount: Int) {
        mutatePlayer(id) { $0.money = min(16000, $0.money + amount) }
    }

    // MARK: - Rules access

    public var currentRules: GameModeRules { rules }
    public func replaceRules(_ newRules: GameModeRules) { rules = newRules }

    func setPhase(_ phase: MatchPhase, duration: Float) {
        state.phase = phase
        state.phaseTimer.start(duration)
    }

    func mutateState(_ body: (inout MatchState) -> Void) { body(&state) }
}
