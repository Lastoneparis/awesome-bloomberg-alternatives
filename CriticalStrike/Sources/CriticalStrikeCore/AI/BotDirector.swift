import Foundation

/// Owns every bot in a match: creates them, feeds their input into the simulation each
/// tick, keeps teams balanced, and quietly adjusts difficulty so a match stays close.
public final class BotDirector {
    public private(set) var brains: [PlayerID: BotBrain] = [:]
    public var baseDifficulty: BotDifficulty
    public var adaptiveDifficulty: Bool = true

    private var rng: DeterministicRandom
    private var nameIndex = 0
    private var adaptTimer: Float = 0
    private var difficultyBias: Int = 0     // -2...+2 steps applied on top of the base

    public init(difficulty: BotDifficulty = .regular, seed: UInt64 = 0xB0715) {
        self.baseDifficulty = difficulty
        self.rng = DeterministicRandom(seed: seed)
    }

    // MARK: - Roster

    @discardableResult
    public func addBot(to sim: MatchSimulation, team: Team,
                       loadout: Loadout? = nil, difficulty: BotDifficulty? = nil) -> PlayerID {
        let d = difficulty ?? baseDifficulty
        let name = BotNames.name(index: nameIndex, difficulty: d)
        nameIndex += 1
        let build = loadout ?? randomLoadout(for: d)
        let id = sim.addPlayer(name: name, team: team, isBot: true, loadout: build)
        brains[id] = BotBrain(id: id, difficulty: d, seed: UInt64(id.rawValue) &* 0x9E3779B9 &+ 17)
        return id
    }

    public func removeBot(_ id: PlayerID, from sim: MatchSimulation) {
        brains[id] = nil
        sim.removePlayer(id)
    }

    /// Fills every empty slot so a solo player always gets a full lobby instantly.
    public func fillMatch(_ sim: MatchSimulation, humanCount: Int = 1) {
        let mode = sim.state.mode
        if mode.kind.isTeamBased {
            let perTeam = mode.teamSize
            for team in [Team.strike, Team.shield] {
                let existing = sim.teamCount(team)
                for _ in existing..<perTeam {
                    addBot(to: sim, team: team)
                }
            }
        } else {
            let existing = sim.allPlayers().count
            for _ in existing..<mode.maxPlayers {
                addBot(to: sim, team: .none)
            }
        }
        _ = humanCount
    }

    /// Replaces a bot with a joining human, preserving team balance.
    public func makeRoomForHuman(_ sim: MatchSimulation, team: Team) -> Bool {
        guard let victim = brains.keys.first(where: { sim.player($0)?.team == team }) else { return false }
        removeBot(victim, from: sim)
        return true
    }

    // MARK: - Tick

    public func step(sim: MatchSimulation, dt: Float) {
        for (id, brain) in brains {
            guard sim.player(id) != nil else { continue }
            let command = brain.think(sim: sim, dt: dt)
            sim.setInput(command, for: id)
        }
        if adaptiveDifficulty { adapt(sim: sim, dt: dt) }
    }

    // MARK: - Adaptive difficulty

    /// Nudges bot skill toward keeping the human within a competitive band. Bounded to
    /// ±2 steps so it never feels like the game is playing itself.
    private func adapt(sim: MatchSimulation, dt: Float) {
        adaptTimer += dt
        guard adaptTimer > 20 else { return }
        adaptTimer = 0
        guard let human = sim.player(sim.localPlayer) else { return }

        let kd = human.deaths == 0 ? Float(human.kills) : Float(human.kills) / Float(human.deaths)
        let previousBias = difficultyBias
        if kd > 2.2 {
            difficultyBias = min(2, difficultyBias + 1)
        } else if kd < 0.55 {
            difficultyBias = max(-2, difficultyBias - 1)
        }
        guard difficultyBias != previousBias else { return }

        let all = BotDifficulty.allCases
        guard let baseIndex = all.firstIndex(of: baseDifficulty) else { return }
        let index = MathUtil.clamp(baseIndex + difficultyBias, 0, all.count - 1)
        let newDifficulty = all[index]
        for brain in brains.values { brain.setDifficulty(newDifficulty) }
        Log.debug("Adaptive difficulty → \(newDifficulty.rawValue) (k/d \(kd))", category: "ai")
    }

    // MARK: - Loadouts

    /// Bots run believable classes rather than one meta gun, and their gear respects the
    /// same unlock rules a player of that skill bracket would have.
    private func randomLoadout(for difficulty: BotDifficulty) -> Loadout {
        var loadouts = Loadout.defaultSet()
        // Better bots bring better attachments.
        let attachmentCount: Int
        switch difficulty {
        case .recruit: attachmentCount = 0
        case .regular: attachmentCount = 1
        case .hardened: attachmentCount = 2
        case .veteran: attachmentCount = 3
        case .elite: attachmentCount = 4
        }
        var pick = loadouts[rng.int(in: 0...(loadouts.count - 1))]
        var chosen: [AttachmentID] = []
        var slots = rng.shuffled(AttachmentSlot.allCases)
        for slot in slots.prefix(attachmentCount) {
            let options = AttachmentDatabase.attachments(for: slot)
            if let a = rng.pick(options) { chosen.append(a.id) }
        }
        pick.primary.attachments = chosen
        slots.removeAll()
        loadouts.removeAll()
        return pick
    }

    public func brain(for id: PlayerID) -> BotBrain? { brains[id] }
    public func reset() {
        brains.removeAll()
        nameIndex = 0
        difficultyBias = 0
    }
}
