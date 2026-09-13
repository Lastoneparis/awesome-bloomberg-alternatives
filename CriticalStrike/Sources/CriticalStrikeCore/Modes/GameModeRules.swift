import Foundation

/// Per-mode behaviour. Everything mode-specific lives behind this protocol so
/// `MatchSimulation` stays mode-agnostic and new modes are additive.
public protocol GameModeRules: AnyObject {
    var kind: GameModeKind { get }

    func matchStarted(sim: MatchSimulation)
    func roundStarted(sim: MatchSimulation)
    func roundEnded(sim: MatchSimulation, winner: Team, reason: RoundEndReason)
    func tick(sim: MatchSimulation, dt: Float)
    func playerKilled(sim: MatchSimulation, victim: PlayerID, killer: PlayerID,
                      weapon: WeaponID, headshot: Bool, position: Vec3)
    func checkRoundEnd(sim: MatchSimulation) -> (Team, RoundEndReason)?
    func roundTimeExpired(sim: MatchSimulation) -> (Team, RoundEndReason)
    func checkMatchEnd(sim: MatchSimulation) -> MatchResult?
    func canRespawn(sim: MatchSimulation, player: PlayerID) -> Bool
    func shouldCollect(sim: MatchSimulation, pickup: PickupInstance, by player: PlayerState) -> Bool
    func pickupCollected(sim: MatchSimulation, pickup: PickupInstance, by player: PlayerID)
    /// Objective progress for the HUD, 0...1 per team.
    func objectiveSummary(sim: MatchSimulation) -> ObjectiveSummary
}

public struct ObjectiveSummary: Sendable {
    public var headline: String
    public var strikeProgress: Float
    public var shieldProgress: Float
    public var detail: String

    public init(headline: String = "", strikeProgress: Float = 0,
                shieldProgress: Float = 0, detail: String = "") {
        self.headline = headline; self.strikeProgress = strikeProgress
        self.shieldProgress = shieldProgress; self.detail = detail
    }
}

public extension GameModeRules {
    func matchStarted(sim: MatchSimulation) {}
    func roundStarted(sim: MatchSimulation) {}
    func roundEnded(sim: MatchSimulation, winner: Team, reason: RoundEndReason) {}
    func tick(sim: MatchSimulation, dt: Float) {}
    func playerKilled(sim: MatchSimulation, victim: PlayerID, killer: PlayerID,
                      weapon: WeaponID, headshot: Bool, position: Vec3) {}
    func checkRoundEnd(sim: MatchSimulation) -> (Team, RoundEndReason)? { nil }
    func roundTimeExpired(sim: MatchSimulation) -> (Team, RoundEndReason) {
        (sim.state.leadingTeam, .timeExpired)
    }
    func canRespawn(sim: MatchSimulation, player: PlayerID) -> Bool { kind.allowsRespawn }
    func shouldCollect(sim: MatchSimulation, pickup: PickupInstance, by player: PlayerState) -> Bool {
        switch pickup.kind {
        case .bomb: return player.team == .strike && !player.hasBomb
        case .defuseKit: return player.team == .shield
        default: return true
        }
    }
    func pickupCollected(sim: MatchSimulation, pickup: PickupInstance, by player: PlayerID) {}
    func objectiveSummary(sim: MatchSimulation) -> ObjectiveSummary { ObjectiveSummary() }
}

public enum GameModeRulesFactory {
    public static func rules(for kind: GameModeKind) -> GameModeRules {
        switch kind {
        case .teamDeathmatch: return ScoreLimitRules(kind: .teamDeathmatch)
        case .freeForAll: return FreeForAllRules()
        case .bombDefusal: return BombDefusalRules()
        case .domination: return DominationRules()
        case .gunGame: return GunGameRules()
        case .searchAndRescue: return SearchAndRescueRules()
        case .killConfirmed: return KillConfirmedRules()
        case .hardpoint: return HardpointRules()
        case .oneInTheChamber: return OneInTheChamberRules()
        case .zombies: return ZombieRules()
        case .training: return TrainingRules()
        }
    }
}

// MARK: - Team Deathmatch

/// Shared "first to N kills" logic, also used as a base by several modes.
public final class ScoreLimitRules: GameModeRules {
    public let kind: GameModeKind
    public init(kind: GameModeKind) { self.kind = kind }

    public func playerKilled(sim: MatchSimulation, victim: PlayerID, killer: PlayerID,
                             weapon: WeaponID, headshot: Bool, position: Vec3) {
        guard killer.isValid, killer != victim, let k = sim.player(killer) else { return }
        guard let v = sim.player(victim), k.team != v.team || v.team == .none else { return }
        sim.mutateState { $0.addScore(k.team, 1) }
        sim.events.emit(.scoreChanged(strike: sim.state.score(.strike), shield: sim.state.score(.shield)))
    }

    public func checkRoundEnd(sim: MatchSimulation) -> (Team, RoundEndReason)? {
        let limit = sim.state.mode.scoreLimit
        guard limit > 0 else { return nil }
        for team in [Team.strike, Team.shield] where sim.state.score(team) >= limit {
            return (team, .objectiveComplete)
        }
        return nil
    }

    public func checkMatchEnd(sim: MatchSimulation) -> MatchResult? {
        let limit = sim.state.mode.scoreLimit
        for team in [Team.strike, Team.shield] where sim.state.score(team) >= limit {
            return sim.buildResult(winner: team)
        }
        return nil
    }

    public func objectiveSummary(sim: MatchSimulation) -> ObjectiveSummary {
        let limit = max(1, sim.state.mode.scoreLimit)
        return ObjectiveSummary(headline: "Eliminate the enemy team",
                                strikeProgress: Float(sim.state.score(.strike)) / Float(limit),
                                shieldProgress: Float(sim.state.score(.shield)) / Float(limit),
                                detail: "First to \(limit) kills")
    }
}

// MARK: - Free For All

public final class FreeForAllRules: GameModeRules {
    public let kind: GameModeKind = .freeForAll
    public init() {}

    public func playerKilled(sim: MatchSimulation, victim: PlayerID, killer: PlayerID,
                             weapon: WeaponID, headshot: Bool, position: Vec3) {
        guard killer.isValid, killer != victim else { return }
        if (sim.player(killer)?.kills ?? 0) >= sim.state.mode.scoreLimit {
            sim.finishMatch(sim.buildResult(winner: .none))
        }
    }

    public func checkMatchEnd(sim: MatchSimulation) -> MatchResult? {
        guard sim.allPlayers().contains(where: { $0.kills >= sim.state.mode.scoreLimit }) else { return nil }
        return sim.buildResult(winner: .none)
    }

    public func objectiveSummary(sim: MatchSimulation) -> ObjectiveSummary {
        let leader = sim.allPlayers().max { $0.kills < $1.kills }
        let limit = max(1, sim.state.mode.scoreLimit)
        return ObjectiveSummary(headline: "Free For All",
                                strikeProgress: Float(leader?.kills ?? 0) / Float(limit),
                                detail: "\(leader?.name ?? "—") leads with \(leader?.kills ?? 0)")
    }
}

// MARK: - Bomb Defusal

public final class BombDefusalRules: GameModeRules {
    public let kind: GameModeKind = .bombDefusal
    public init() {}

    public func roundStarted(sim: MatchSimulation) {
        // Hand the bomb to a random living attacker.
        let attackers = sim.alivePlayers(team: .strike)
        guard !attackers.isEmpty else { return }
        let index = sim.rng.int(in: 0...(attackers.count - 1))
        let carrier = attackers[index].id
        sim.mutatePlayer(carrier) { $0.hasBomb = true }
        sim.mutateState { $0.bomb.carrier = carrier }
        sim.events.emit(.bombPickedUp(player: carrier))
        // Defenders get a kit each round; buying more is handled by the buy menu.
        for defender in sim.alivePlayers(team: .shield) {
            sim.mutatePlayer(defender.id) { $0.hasDefuseKit = sim.rng.chance(0.5) }
        }
    }

    public func tick(sim: MatchSimulation, dt: Float) {
        var bomb = sim.state.bomb
        guard sim.state.phase == .live else { return }

        if bomb.isPlanted && !bomb.isDefused && !bomb.hasExploded {
            if bomb.timer.tick(dt) {
                bomb.hasExploded = true
                sim.mutateState { $0.bomb = bomb }
                sim.detonateBomb(at: bomb.position)
                return
            }
            tickDefuse(sim: sim, bomb: &bomb, dt: dt)
        } else if !bomb.isPlanted {
            tickPlant(sim: sim, bomb: &bomb, dt: dt)
        }
        sim.mutateState { $0.bomb = bomb }
    }

    private func tickPlant(sim: MatchSimulation, bomb: inout BombState, dt: Float) {
        for player in sim.alivePlayers(team: .strike) where player.hasBomb {
            guard let site = sim.map.bombSites.first(where: { $0.contains(player.position) }) else {
                sim.mutatePlayer(player.id) { $0.plantProgress = 0 }
                continue
            }
            let planting = isHoldingUse(player)
            guard planting, player.onGround else {
                sim.mutatePlayer(player.id) { $0.plantProgress = 0 }
                continue
            }
            var progress = player.plantProgress + dt / BombState.plantDuration
            if progress >= 1 {
                progress = 0
                bomb.isPlanted = true
                bomb.site = site.index
                bomb.position = player.position + Vec3(0, 0.2, 0)
                bomb.planter = player.id
                bomb.timer.start(BombState.fuseDuration)
                sim.mutatePlayer(player.id) { $0.hasBomb = false; $0.plantProgress = 0 }
                sim.giveMoney(player.id, 300)
                sim.awardXP(player.id, 250, reason: "Bomb Planted")
                sim.events.emit(.bombPlanted(player: player.id, site: site.index, position: bomb.position))
                // Planting freezes the round timer: now only the fuse matters.
                sim.setPhase(.live, duration: BombState.fuseDuration + 1)
                return
            }
            sim.mutatePlayer(player.id) { $0.plantProgress = progress }
        }
    }

    private func tickDefuse(sim: MatchSimulation, bomb: inout BombState, dt: Float) {
        var anyDefusing = false
        for player in sim.alivePlayers(team: .shield) {
            let atBomb = player.position.distance(to: bomb.position) < 2.2
            guard atBomb, isHoldingUse(player) else {
                if bomb.defuser == player.id {
                    bomb.defuser = .none
                    sim.mutatePlayer(player.id) { $0.defuseProgress = 0 }
                    sim.events.emit(.bombDefuseAborted(player: player.id))
                }
                continue
            }
            anyDefusing = true
            if bomb.defuser != player.id {
                bomb.defuser = player.id
                sim.events.emit(.bombDefuseStarted(player: player.id, hasKit: player.hasDefuseKit))
            }
            let duration = player.hasDefuseKit ? BombState.defuseWithKitDuration : BombState.defuseDuration
            var progress = player.defuseProgress + dt / duration
            if progress >= 1 {
                progress = 0
                bomb.isDefused = true
                sim.giveMoney(player.id, 300)
                sim.awardXP(player.id, 300, reason: "Bomb Defused")
                sim.events.emit(.bombDefused(player: player.id))
            }
            sim.mutatePlayer(player.id) { $0.defuseProgress = progress }
            break
        }
        if !anyDefusing { bomb.defuser = .none }
    }

    private func isHoldingUse(_ player: PlayerState) -> Bool {
        // `isUsing` is set from the interact button by the simulation each tick.
        player.isUsing
    }

    public func checkRoundEnd(sim: MatchSimulation) -> (Team, RoundEndReason)? {
        let bomb = sim.state.bomb
        if bomb.isDefused { return (.shield, .bombDefused) }
        if bomb.hasExploded { return (.strike, .bombExploded) }
        let attackers = sim.alivePlayers(team: .strike).count
        let defenders = sim.alivePlayers(team: .shield).count
        if attackers == 0 && !bomb.isPlanted { return (.shield, .elimination) }
        if defenders == 0 { return (.strike, .elimination) }
        return nil
    }

    public func roundTimeExpired(sim: MatchSimulation) -> (Team, RoundEndReason) {
        sim.state.bomb.isPlanted ? (.strike, .bombExploded) : (.shield, .timeExpired)
    }

    public func roundEnded(sim: MatchSimulation, winner: Team, reason: RoundEndReason) {
        // Round economy: winners get a flat bonus, losers get a growing loss streak bonus.
        for player in sim.allPlayers() {
            let won = player.team == winner
            let reward = won ? 3250 : 1400 + min(sim.state.round, 5) * 500
            sim.giveMoney(player.id, reward)
            if won { sim.awardXP(player.id, 200, reason: "Round Won") }
        }
    }

    public func checkMatchEnd(sim: MatchSimulation) -> MatchResult? {
        let target = sim.state.mode.roundsToWin
        for team in [Team.strike, Team.shield] where (sim.state.roundWins[team] ?? 0) >= target {
            return sim.buildResult(winner: team)
        }
        return nil
    }

    public func canRespawn(sim: MatchSimulation, player: PlayerID) -> Bool { false }

    public func objectiveSummary(sim: MatchSimulation) -> ObjectiveSummary {
        let bomb = sim.state.bomb
        let target = Float(max(1, sim.state.mode.roundsToWin))
        var headline = "Plant the bomb"
        var detail = "Round \(sim.state.round)"
        if bomb.isPlanted {
            headline = "Bomb planted at \(bomb.site == 0 ? "A" : "B")"
            detail = String(format: "%.0fs", bomb.timer.remaining)
        }
        return ObjectiveSummary(headline: headline,
                                strikeProgress: Float(sim.state.roundWins[.strike] ?? 0) / target,
                                shieldProgress: Float(sim.state.roundWins[.shield] ?? 0) / target,
                                detail: detail)
    }
}

// MARK: - Domination

public final class DominationRules: GameModeRules {
    public let kind: GameModeKind = .domination
    public static let captureTime: Float = 6.0
    public static let tickInterval: Float = 5.0
    private var scoreAccumulator: Float = 0
    public init() {}

    public func tick(sim: MatchSimulation, dt: Float) {
        guard sim.state.phase == .live else { return }
        var captures = sim.state.captures
        for i in captures.indices {
            guard let zone = sim.map.capturePoints.first(where: { $0.index == captures[i].index }) else { continue }
            let inside = sim.allPlayers().filter { $0.isAlive && zone.contains($0.position) }
            let strike = inside.filter { $0.team == .strike }.count
            let shield = inside.filter { $0.team == .shield }.count
            captures[i].strikeCount = strike
            captures[i].shieldCount = shield
            captures[i].contested = strike > 0 && shield > 0

            if captures[i].contested {
                sim.events.emit(.objectiveContested(point: captures[i].index))
                continue
            }
            // Extra players capture faster, with diminishing returns.
            let rate = dt / DominationRules.captureTime
            if strike > 0 {
                captures[i].progress = min(1, captures[i].progress + rate * (1 + Float(strike - 1) * 0.4))
            } else if shield > 0 {
                captures[i].progress = max(-1, captures[i].progress - rate * (1 + Float(shield - 1) * 0.4))
            }

            let newOwner: Team = captures[i].progress >= 1 ? .strike
                              : (captures[i].progress <= -1 ? .shield : captures[i].owner)
            if newOwner != captures[i].owner && newOwner != .none {
                captures[i].owner = newOwner
                let capturers = inside.filter { $0.team == newOwner }.map(\.id)
                for id in capturers { sim.awardXP(id, 150, reason: "Capture") }
                sim.events.emit(.objectiveCaptured(point: captures[i].index, team: newOwner, by: capturers))
            }
            sim.events.emit(.objectiveProgress(point: captures[i].index,
                                               team: captures[i].progress >= 0 ? .strike : .shield,
                                               progress: abs(captures[i].progress)))
        }
        sim.mutateState { $0.captures = captures }

        // Score ticks proportional to points held.
        scoreAccumulator += dt
        if scoreAccumulator >= DominationRules.tickInterval {
            scoreAccumulator -= DominationRules.tickInterval
            for team in [Team.strike, Team.shield] {
                let held = captures.filter { $0.owner == team }.count
                if held > 0 {
                    sim.mutateState { $0.addScore(team, held * 5) }
                }
            }
            sim.events.emit(.scoreChanged(strike: sim.state.score(.strike), shield: sim.state.score(.shield)))
        }
    }

    public func checkMatchEnd(sim: MatchSimulation) -> MatchResult? {
        let limit = sim.state.mode.scoreLimit
        for team in [Team.strike, Team.shield] where sim.state.score(team) >= limit {
            return sim.buildResult(winner: team)
        }
        return nil
    }

    public func checkRoundEnd(sim: MatchSimulation) -> (Team, RoundEndReason)? {
        let limit = sim.state.mode.scoreLimit
        for team in [Team.strike, Team.shield] where sim.state.score(team) >= limit {
            return (team, .objectiveComplete)
        }
        return nil
    }

    public func objectiveSummary(sim: MatchSimulation) -> ObjectiveSummary {
        let limit = Float(max(1, sim.state.mode.scoreLimit))
        let held = sim.state.captures.map { $0.owner }
        let names = ["A", "B", "C", "D"]
        let detail = held.enumerated().map { i, t in
            "\(i < names.count ? names[i] : "?"):\(t == .none ? "-" : (t == .strike ? "S" : "D"))"
        }.joined(separator: " ")
        return ObjectiveSummary(headline: "Hold the objectives",
                                strikeProgress: Float(sim.state.score(.strike)) / limit,
                                shieldProgress: Float(sim.state.score(.shield)) / limit,
                                detail: detail)
    }
}

// MARK: - Hardpoint

public final class HardpointRules: GameModeRules {
    public let kind: GameModeKind = .hardpoint
    public static let rotationInterval: Float = 60
    private var accumulator: Float = 0
    public init() {}

    public func roundStarted(sim: MatchSimulation) {
        sim.mutateState {
            $0.activeHardpoint = 0
            $0.hardpointRotationTimer.start(HardpointRules.rotationInterval)
        }
    }

    public func tick(sim: MatchSimulation, dt: Float) {
        guard sim.state.phase == .live, !sim.map.hardpoints.isEmpty else { return }
        var rotation = sim.state.hardpointRotationTimer
        if rotation.tick(dt) {
            let next = (sim.state.activeHardpoint + 1) % sim.map.hardpoints.count
            rotation.start(HardpointRules.rotationInterval)
            sim.mutateState { $0.activeHardpoint = next; $0.hardpointRotationTimer = rotation }
            sim.events.emit(.objectiveCaptured(point: next, team: .none, by: []))
        } else {
            sim.mutateState { $0.hardpointRotationTimer = rotation }
        }

        let zone = sim.map.hardpoints[sim.state.activeHardpoint]
        let inside = sim.allPlayers().filter { $0.isAlive && zone.contains($0.position) }
        let strike = inside.filter { $0.team == .strike }
        let shield = inside.filter { $0.team == .shield }
        guard !(strike.isEmpty && shield.isEmpty), strike.isEmpty || shield.isEmpty else {
            if !strike.isEmpty && !shield.isEmpty {
                sim.events.emit(.objectiveContested(point: zone.index))
            }
            return
        }
        let holder: Team = strike.isEmpty ? .shield : .strike
        accumulator += dt
        while accumulator >= 1 {
            accumulator -= 1
            sim.mutateState { $0.addScore(holder, 1) }
            for p in (holder == .strike ? strike : shield) {
                sim.awardXP(p.id, 10, reason: "Hardpoint")
            }
        }
        sim.events.emit(.objectiveProgress(point: zone.index, team: holder, progress: 1))
    }

    public func checkRoundEnd(sim: MatchSimulation) -> (Team, RoundEndReason)? {
        let limit = sim.state.mode.scoreLimit
        for team in [Team.strike, Team.shield] where sim.state.score(team) >= limit {
            return (team, .objectiveComplete)
        }
        return nil
    }

    public func checkMatchEnd(sim: MatchSimulation) -> MatchResult? {
        let limit = sim.state.mode.scoreLimit
        for team in [Team.strike, Team.shield] where sim.state.score(team) >= limit {
            return sim.buildResult(winner: team)
        }
        return nil
    }

    public func objectiveSummary(sim: MatchSimulation) -> ObjectiveSummary {
        let limit = Float(max(1, sim.state.mode.scoreLimit))
        let name = sim.map.hardpoints.indices.contains(sim.state.activeHardpoint)
            ? sim.map.hardpoints[sim.state.activeHardpoint].name : "—"
        return ObjectiveSummary(headline: "Hold \(name)",
                                strikeProgress: Float(sim.state.score(.strike)) / limit,
                                shieldProgress: Float(sim.state.score(.shield)) / limit,
                                detail: String(format: "Rotates in %.0fs", sim.state.hardpointRotationTimer.remaining))
    }
}

// MARK: - Gun Game

public final class GunGameRules: GameModeRules {
    public let kind: GameModeKind = .gunGame
    public init() {}

    public func playerKilled(sim: MatchSimulation, victim: PlayerID, killer: PlayerID,
                             weapon: WeaponID, headshot: Bool, position: Vec3) {
        guard killer.isValid, killer != victim else { return }
        var level = 0
        sim.mutatePlayer(killer) { p in
            p.gunGameLevel += 1
            level = p.gunGameLevel
        }
        let ladder = GameModeDatabase.gunGameLadder
        guard level < ladder.count else {
            sim.finishMatch(sim.buildResult(winner: .none))
            return
        }
        let next = ladder[level]
        sim.mutatePlayer(killer) { p in
            p.slots[.primary] = WeaponSlotState(build: WeaponBuild(weapon: next))
            p.activeSlot = .primary
            p.action = .drawing
            p.actionTimer.start(0.4)
            p.health = p.maxHealth
        }
        sim.events.emit(.weaponSwitched(player: killer, weapon: next, slot: .primary))
        sim.awardXP(killer, 60, reason: "Level Up")
    }

    public func checkMatchEnd(sim: MatchSimulation) -> MatchResult? {
        guard sim.allPlayers().contains(where: { $0.gunGameLevel >= GameModeDatabase.gunGameLadder.count })
        else { return nil }
        return sim.buildResult(winner: .none)
    }

    public func objectiveSummary(sim: MatchSimulation) -> ObjectiveSummary {
        let leader = sim.allPlayers().max { $0.gunGameLevel < $1.gunGameLevel }
        let total = Float(GameModeDatabase.gunGameLadder.count)
        let level = min((leader?.gunGameLevel ?? 0) + 1, Int(total))
        return ObjectiveSummary(headline: "Work through every weapon",
                                strikeProgress: Float(leader?.gunGameLevel ?? 0) / total,
                                detail: "\(leader?.name ?? "—") on level \(level)/\(Int(total))")
    }
}

// MARK: - Kill Confirmed

public final class KillConfirmedRules: GameModeRules {
    public let kind: GameModeKind = .killConfirmed
    public init() {}

    public func playerKilled(sim: MatchSimulation, victim: PlayerID, killer: PlayerID,
                             weapon: WeaponID, headshot: Bool, position: Vec3) {
        let team = sim.player(victim)?.team ?? .none
        sim.spawnPickup(kind: .health, at: position + Vec3(0, 0.4, 0),
                        dogTagOwner: victim, dogTagTeam: team)
    }

    public func shouldCollect(sim: MatchSimulation, pickup: PickupInstance, by player: PlayerState) -> Bool {
        guard pickup.dogTagOwner.isValid else { return true }
        return true   // both teams interact with tags: enemies confirm, allies deny
    }

    public func pickupCollected(sim: MatchSimulation, pickup: PickupInstance, by player: PlayerID) {
        guard pickup.dogTagOwner.isValid, let collector = sim.player(player) else { return }
        if collector.team != pickup.dogTagTeam {
            sim.mutateState { $0.addScore(collector.team, 1) }
            sim.mutatePlayer(player) { $0.score += 50 }
            sim.awardXP(player, 75, reason: "Confirmed")
        } else {
            sim.mutatePlayer(player) { $0.score += 25 }
            sim.awardXP(player, 50, reason: "Denied")
        }
        sim.events.emit(.scoreChanged(strike: sim.state.score(.strike), shield: sim.state.score(.shield)))
    }

    public func checkRoundEnd(sim: MatchSimulation) -> (Team, RoundEndReason)? {
        let limit = sim.state.mode.scoreLimit
        for team in [Team.strike, Team.shield] where sim.state.score(team) >= limit {
            return (team, .objectiveComplete)
        }
        return nil
    }

    public func checkMatchEnd(sim: MatchSimulation) -> MatchResult? {
        let limit = sim.state.mode.scoreLimit
        for team in [Team.strike, Team.shield] where sim.state.score(team) >= limit {
            return sim.buildResult(winner: team)
        }
        return nil
    }

    public func objectiveSummary(sim: MatchSimulation) -> ObjectiveSummary {
        let limit = Float(max(1, sim.state.mode.scoreLimit))
        return ObjectiveSummary(headline: "Collect the dog tags",
                                strikeProgress: Float(sim.state.score(.strike)) / limit,
                                shieldProgress: Float(sim.state.score(.shield)) / limit,
                                detail: "Kills only count when confirmed")
    }
}

// MARK: - Search & Rescue

public final class SearchAndRescueRules: GameModeRules {
    public let kind: GameModeKind = .searchAndRescue
    private let bomb = BombDefusalRules()
    public init() {}

    public func roundStarted(sim: MatchSimulation) { bomb.roundStarted(sim: sim) }
    public func tick(sim: MatchSimulation, dt: Float) { bomb.tick(sim: sim, dt: dt) }

    public func playerKilled(sim: MatchSimulation, victim: PlayerID, killer: PlayerID,
                             weapon: WeaponID, headshot: Bool, position: Vec3) {
        let team = sim.player(victim)?.team ?? .none
        sim.spawnPickup(kind: .health, at: position + Vec3(0, 0.4, 0),
                        dogTagOwner: victim, dogTagTeam: team)
    }

    public func pickupCollected(sim: MatchSimulation, pickup: PickupInstance, by player: PlayerID) {
        guard pickup.dogTagOwner.isValid, let collector = sim.player(player) else { return }
        if collector.team == pickup.dogTagTeam {
            // Rescue: the fallen teammate comes back next tick.
            sim.respawn(pickup.dogTagOwner, force: true)
            sim.awardXP(player, 200, reason: "Rescue")
        } else {
            sim.awardXP(player, 75, reason: "Eliminated")
        }
    }

    public func checkRoundEnd(sim: MatchSimulation) -> (Team, RoundEndReason)? {
        bomb.checkRoundEnd(sim: sim)
    }
    public func roundTimeExpired(sim: MatchSimulation) -> (Team, RoundEndReason) {
        bomb.roundTimeExpired(sim: sim)
    }
    public func roundEnded(sim: MatchSimulation, winner: Team, reason: RoundEndReason) {
        bomb.roundEnded(sim: sim, winner: winner, reason: reason)
    }
    public func checkMatchEnd(sim: MatchSimulation) -> MatchResult? { bomb.checkMatchEnd(sim: sim) }
    public func canRespawn(sim: MatchSimulation, player: PlayerID) -> Bool { false }
    public func objectiveSummary(sim: MatchSimulation) -> ObjectiveSummary {
        var summary = bomb.objectiveSummary(sim: sim)
        summary.detail += " • Grab tags to revive"
        return summary
    }
}

// MARK: - One in the Chamber

public final class OneInTheChamberRules: GameModeRules {
    public let kind: GameModeKind = .oneInTheChamber
    public init() {}

    public func checkMatchEnd(sim: MatchSimulation) -> MatchResult? {
        guard sim.allPlayers().contains(where: { $0.kills >= sim.state.mode.scoreLimit }) else { return nil }
        return sim.buildResult(winner: .none)
    }

    public func objectiveSummary(sim: MatchSimulation) -> ObjectiveSummary {
        let leader = sim.allPlayers().max { $0.kills < $1.kills }
        return ObjectiveSummary(headline: "One bullet. One life.",
                                strikeProgress: Float(leader?.kills ?? 0) / Float(max(1, sim.state.mode.scoreLimit)),
                                detail: "Every kill gives you a round back")
    }
}

// MARK: - Zombies

public final class ZombieRules: GameModeRules {
    public let kind: GameModeKind = .zombies
    private var waveTimer = Countdown()
    private var zombiesAlive = 0
    public init() {}

    public func roundStarted(sim: MatchSimulation) {
        sim.mutateState { $0.zombieWave = 1 }
        waveTimer.start(6)
    }

    public func tick(sim: MatchSimulation, dt: Float) {
        guard sim.state.phase == .live else { return }
        zombiesAlive = sim.alivePlayers(team: .shield).count
        if zombiesAlive == 0 && waveTimer.tick(dt) {
            sim.mutateState { $0.zombieWave += 1 }
            waveTimer.start(10)
            for id in sim.playerOrder where sim.player(id)?.team == .shield {
                sim.respawn(id, force: true)
            }
            // Survivors are paid per wave cleared.
            for survivor in sim.alivePlayers(team: .strike) {
                sim.giveMoney(survivor.id, 500 + sim.state.zombieWave * 50)
                sim.awardXP(survivor.id, 120, reason: "Wave Cleared")
            }
        }
    }

    public func checkRoundEnd(sim: MatchSimulation) -> (Team, RoundEndReason)? {
        sim.alivePlayers(team: .strike).isEmpty ? (.shield, .elimination) : nil
    }

    public func checkMatchEnd(sim: MatchSimulation) -> MatchResult? {
        sim.alivePlayers(team: .strike).isEmpty ? sim.buildResult(winner: .shield) : nil
    }

    public func canRespawn(sim: MatchSimulation, player: PlayerID) -> Bool {
        sim.player(player)?.team == .shield
    }

    public func objectiveSummary(sim: MatchSimulation) -> ObjectiveSummary {
        ObjectiveSummary(headline: "Wave \(sim.state.zombieWave)",
                         strikeProgress: 0,
                         detail: "\(zombiesAlive) hostiles remaining")
    }
}

// MARK: - Training

public final class TrainingRules: GameModeRules {
    public let kind: GameModeKind = .training
    public init() {}

    public func playerKilled(sim: MatchSimulation, victim: PlayerID, killer: PlayerID,
                             weapon: WeaponID, headshot: Bool, position: Vec3) {
        // Targets pop straight back up.
        sim.respawn(victim, force: true)
    }

    public func canRespawn(sim: MatchSimulation, player: PlayerID) -> Bool { true }

    /// The range never ends on its own; the player leaves when they are done.
    public func checkMatchEnd(sim: MatchSimulation) -> MatchResult? { nil }

    public func objectiveSummary(sim: MatchSimulation) -> ObjectiveSummary {
        ObjectiveSummary(headline: "Training Range", detail: "Practise spray control and lineups")
    }
}
