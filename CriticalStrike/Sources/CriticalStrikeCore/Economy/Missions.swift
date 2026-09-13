import Foundation

public enum MissionScope: String, Codable, CaseIterable, Sendable {
    case daily, weekly, career, seasonal

    public var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .career: return "Career"
        case .seasonal: return "Seasonal"
        }
    }

    public var refreshInterval: TimeInterval {
        switch self {
        case .daily: return 86400
        case .weekly: return 604800
        default: return .infinity
        }
    }
}

/// What a mission counts. Each case maps to one or more `GameEvent`s.
public enum MissionObjective: Codable, Sendable, Equatable {
    case kills(count: Int)
    case headshots(count: Int)
    case killsWith(weaponClass: WeaponClass, count: Int)
    case killsWithWeapon(WeaponID, count: Int)
    case wins(count: Int)
    case matchesPlayed(count: Int)
    case damageDealt(amount: Int)
    case objectivesCaptured(count: Int)
    case bombsPlanted(count: Int)
    case bombsDefused(count: Int)
    case killStreak(length: Int)
    case grenadeKills(count: Int)
    case meleeKills(count: Int)
    case wallbangs(count: Int)
    case playTimeMinutes(count: Int)
    case reachLevel(level: Int)

    public var target: Int {
        switch self {
        case let .kills(c), let .headshots(c), let .wins(c), let .matchesPlayed(c),
             let .objectivesCaptured(c), let .bombsPlanted(c), let .bombsDefused(c),
             let .grenadeKills(c), let .meleeKills(c), let .wallbangs(c), let .playTimeMinutes(c):
            return c
        case let .killsWith(_, c), let .killsWithWeapon(_, c):
            return c
        case let .damageDealt(a): return a
        case let .killStreak(l): return l
        case let .reachLevel(l): return l
        }
    }

    public var description: String {
        switch self {
        case let .kills(c): return "Get \(c) kills"
        case let .headshots(c): return "Get \(c) headshots"
        case let .killsWith(cls, c): return "Get \(c) kills with an \(cls.displayName)"
        case let .killsWithWeapon(id, c):
            return "Get \(c) kills with the \(WeaponDatabase.weapon(id)?.name ?? id.value)"
        case let .wins(c): return "Win \(c) matches"
        case let .matchesPlayed(c): return "Play \(c) matches"
        case let .damageDealt(a): return "Deal \(a) damage"
        case let .objectivesCaptured(c): return "Capture \(c) objectives"
        case let .bombsPlanted(c): return "Plant the bomb \(c) times"
        case let .bombsDefused(c): return "Defuse the bomb \(c) times"
        case let .killStreak(l): return "Get a \(l) kill streak"
        case let .grenadeKills(c): return "Get \(c) grenade kills"
        case let .meleeKills(c): return "Get \(c) melee kills"
        case let .wallbangs(c): return "Get \(c) kills through a wall"
        case let .playTimeMinutes(c): return "Play for \(c) minutes"
        case let .reachLevel(l): return "Reach level \(l)"
        }
    }
}

public struct Mission: Identifiable, Codable, Sendable {
    public var id: MissionID
    public var title: String
    public var scope: MissionScope
    public var objective: MissionObjective
    public var xpReward: Int
    public var currencyReward: (CurrencyKind, Int)?
    public var cosmeticReward: SkinID?
    public var unlockLevel: Int

    public init(id: MissionID, title: String, scope: MissionScope, objective: MissionObjective,
                xpReward: Int, currencyReward: (CurrencyKind, Int)? = nil,
                cosmeticReward: SkinID? = nil, unlockLevel: Int = 1) {
        self.id = id; self.title = title; self.scope = scope; self.objective = objective
        self.xpReward = xpReward; self.currencyReward = currencyReward
        self.cosmeticReward = cosmeticReward; self.unlockLevel = unlockLevel
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, scope, objective, xpReward, currencyKind, currencyAmount,
             cosmeticReward, unlockLevel
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(MissionID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        scope = try c.decode(MissionScope.self, forKey: .scope)
        objective = try c.decode(MissionObjective.self, forKey: .objective)
        xpReward = try c.decode(Int.self, forKey: .xpReward)
        if let kind = try c.decodeIfPresent(CurrencyKind.self, forKey: .currencyKind),
           let amount = try c.decodeIfPresent(Int.self, forKey: .currencyAmount) {
            currencyReward = (kind, amount)
        }
        cosmeticReward = try c.decodeIfPresent(SkinID.self, forKey: .cosmeticReward)
        unlockLevel = try c.decode(Int.self, forKey: .unlockLevel)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(scope, forKey: .scope)
        try c.encode(objective, forKey: .objective)
        try c.encode(xpReward, forKey: .xpReward)
        try c.encodeIfPresent(currencyReward?.0, forKey: .currencyKind)
        try c.encodeIfPresent(currencyReward?.1, forKey: .currencyAmount)
        try c.encodeIfPresent(cosmeticReward, forKey: .cosmeticReward)
        try c.encode(unlockLevel, forKey: .unlockLevel)
    }
}

public struct MissionProgress: Codable, Equatable, Sendable {
    public var missionID: MissionID
    public var progress: Int
    public var claimed: Bool
    public var assignedAt: Date

    public init(missionID: MissionID, progress: Int = 0, claimed: Bool = false,
                assignedAt: Date = Date()) {
        self.missionID = missionID; self.progress = progress
        self.claimed = claimed; self.assignedAt = assignedAt
    }

    public func isComplete(target: Int) -> Bool { progress >= target }
    public func fraction(target: Int) -> Float {
        target > 0 ? MathUtil.clamp(Float(progress) / Float(target), 0, 1) : 0
    }
}

public enum MissionDatabase {
    public static let dailyPool: [Mission] = [
        Mission(id: "d_kills_15", title: "Get to Work", scope: .daily,
                objective: .kills(count: 15), xpReward: 800, currencyReward: (.coins, 1500)),
        Mission(id: "d_headshots_5", title: "Precision", scope: .daily,
                objective: .headshots(count: 5), xpReward: 900, currencyReward: (.coins, 1800)),
        Mission(id: "d_win_2", title: "Take the W", scope: .daily,
                objective: .wins(count: 2), xpReward: 1000, currencyReward: (.coins, 2000)),
        Mission(id: "d_ar_kills", title: "Rifleman", scope: .daily,
                objective: .killsWith(weaponClass: .assaultRifle, count: 12),
                xpReward: 850, currencyReward: (.coins, 1600)),
        Mission(id: "d_smg_kills", title: "Close Quarters", scope: .daily,
                objective: .killsWith(weaponClass: .submachineGun, count: 12),
                xpReward: 850, currencyReward: (.coins, 1600)),
        Mission(id: "d_sniper_kills", title: "Overwatch", scope: .daily,
                objective: .killsWith(weaponClass: .sniperRifle, count: 6),
                xpReward: 950, currencyReward: (.coins, 1800), unlockLevel: 12),
        Mission(id: "d_grenade_3", title: "Fire in the Hole", scope: .daily,
                objective: .grenadeKills(count: 3), xpReward: 900, currencyReward: (.coins, 1700)),
        Mission(id: "d_melee_2", title: "Up Close", scope: .daily,
                objective: .meleeKills(count: 2), xpReward: 850, currencyReward: (.coins, 1600)),
        Mission(id: "d_damage", title: "Attrition", scope: .daily,
                objective: .damageDealt(amount: 3000), xpReward: 800, currencyReward: (.coins, 1500)),
        Mission(id: "d_streak_4", title: "On a Roll", scope: .daily,
                objective: .killStreak(length: 4), xpReward: 1000, currencyReward: (.coins, 2000)),
        Mission(id: "d_play_3", title: "Clock In", scope: .daily,
                objective: .matchesPlayed(count: 3), xpReward: 700, currencyReward: (.coins, 1200)),
        Mission(id: "d_objectives", title: "Play the Objective", scope: .daily,
                objective: .objectivesCaptured(count: 4), xpReward: 950,
                currencyReward: (.coins, 1800), unlockLevel: 2)
    ]

    public static let weeklyPool: [Mission] = [
        Mission(id: "w_kills_150", title: "Veteran's Week", scope: .weekly,
                objective: .kills(count: 150), xpReward: 6000, currencyReward: (.gems, 120)),
        Mission(id: "w_wins_10", title: "Winning Streak", scope: .weekly,
                objective: .wins(count: 10), xpReward: 7000, currencyReward: (.gems, 150)),
        Mission(id: "w_headshots_50", title: "Marksman's Week", scope: .weekly,
                objective: .headshots(count: 50), xpReward: 6500, currencyReward: (.gems, 130)),
        Mission(id: "w_playtime", title: "Dedicated", scope: .weekly,
                objective: .playTimeMinutes(count: 240), xpReward: 5500,
                currencyReward: (.coins, 15000)),
        Mission(id: "w_bombs", title: "Demolitions", scope: .weekly,
                objective: .bombsPlanted(count: 12), xpReward: 6000,
                currencyReward: (.coins, 14000), unlockLevel: 3),
        Mission(id: "w_wallbangs", title: "See Through It", scope: .weekly,
                objective: .wallbangs(count: 15), xpReward: 6800, currencyReward: (.gems, 140))
    ]

    public static let careerMissions: [Mission] = [
        Mission(id: "c_kills_1000", title: "Thousand Yard Stare", scope: .career,
                objective: .kills(count: 1000), xpReward: 20000,
                cosmeticReward: "title_untouchable"),
        Mission(id: "c_level_50", title: "Seasoned", scope: .career,
                objective: .reachLevel(level: 50), xpReward: 0,
                cosmeticReward: "charm_skull"),
        Mission(id: "c_wins_100", title: "Century", scope: .career,
                objective: .wins(count: 100), xpReward: 25000,
                currencyReward: (.gems, 500)),
        Mission(id: "c_headshots_500", title: "Head Hunter", scope: .career,
                objective: .headshots(count: 500), xpReward: 22000,
                cosmeticReward: "spray_headshot")
    ]

    public static var all: [Mission] { dailyPool + weeklyPool + careerMissions }

    public static func mission(_ id: MissionID) -> Mission? { all.first { $0.id == id } }

    /// Deterministic daily assignment: everyone at a given level gets the same three,
    /// so players can compare and the server can validate.
    public static func dailyAssignment(for date: Date, level: Int, count: Int = 3) -> [Mission] {
        let day = Int(date.timeIntervalSince1970 / 86400)
        var rng = DeterministicRandom(seed: UInt64(bitPattern: Int64(day &* 7919)))
        let eligible = dailyPool.filter { $0.unlockLevel <= level }
        return Array(rng.shuffled(eligible).prefix(count))
    }

    public static func weeklyAssignment(for date: Date, level: Int, count: Int = 3) -> [Mission] {
        let week = Int(date.timeIntervalSince1970 / 604800)
        var rng = DeterministicRandom(seed: UInt64(bitPattern: Int64(week &* 104729)))
        let eligible = weeklyPool.filter { $0.unlockLevel <= level }
        return Array(rng.shuffled(eligible).prefix(count))
    }
}

/// Watches game events and advances mission counters. One instance per player profile.
public final class MissionTracker {
    public private(set) var progress: [MissionID: MissionProgress] = [:]
    public var onMissionCompleted: ((Mission) -> Void)?
    private var activeMissions: [Mission] = []

    public init() {}

    public func setActiveMissions(_ missions: [Mission], existing: [MissionID: MissionProgress]) {
        activeMissions = missions
        progress = existing
        for mission in missions where progress[mission.id] == nil {
            progress[mission.id] = MissionProgress(missionID: mission.id)
        }
    }

    public func handle(_ event: GameEvent, localPlayer: PlayerID, weapon: WeaponID? = nil) {
        switch event {
        case let .playerDied(_, killer, weaponID, headshot, wallbang) where killer == localPlayer:
            advance(.kills(count: 0), by: 1)
            if headshot { advance(.headshots(count: 0), by: 1) }
            if wallbang { advance(.wallbangs(count: 0), by: 1) }
            if let data = WeaponDatabase.weapon(weaponID) {
                advanceClassKills(data.weaponClass)
                advanceWeaponKills(weaponID)
                if data.weaponClass == .melee { advance(.meleeKills(count: 0), by: 1) }
            }
            if weaponID.value.hasPrefix("nade_") { advance(.grenadeKills(count: 0), by: 1) }
        case let .playerDamaged(_, attacker, amount, _, _) where attacker == localPlayer:
            advance(.damageDealt(amount: 0), by: Int(amount))
        case let .killStreak(player, count) where player == localPlayer:
            advanceStreak(count)
        case let .objectiveCaptured(_, _, by) where by.contains(localPlayer):
            advance(.objectivesCaptured(count: 0), by: 1)
        case let .bombPlanted(player, _, _) where player == localPlayer:
            advance(.bombsPlanted(count: 0), by: 1)
        case let .bombDefused(player) where player == localPlayer:
            advance(.bombsDefused(count: 0), by: 1)
        default:
            break
        }
        _ = weapon
    }

    public func recordMatchFinished(won: Bool, durationMinutes: Int, level: Int) {
        advance(.matchesPlayed(count: 0), by: 1)
        if won { advance(.wins(count: 0), by: 1) }
        advance(.playTimeMinutes(count: 0), by: durationMinutes)
        for mission in activeMissions {
            if case .reachLevel = mission.objective {
                setProgress(mission.id, to: level)
            }
        }
    }

    public func claim(_ missionID: MissionID) -> Mission? {
        guard var p = progress[missionID], !p.claimed,
              let mission = activeMissions.first(where: { $0.id == missionID }),
              p.isComplete(target: mission.objective.target) else { return nil }
        p.claimed = true
        progress[missionID] = p
        return mission
    }

    public func claimable() -> [Mission] {
        activeMissions.filter { mission in
            guard let p = progress[mission.id] else { return false }
            return !p.claimed && p.isComplete(target: mission.objective.target)
        }
    }

    // MARK: - Counter plumbing

    private func advance(_ template: MissionObjective, by amount: Int) {
        guard amount > 0 else { return }
        for mission in activeMissions where sameKind(mission.objective, template) {
            bump(mission, by: amount)
        }
    }

    private func advanceClassKills(_ weaponClass: WeaponClass) {
        for mission in activeMissions {
            if case let .killsWith(cls, _) = mission.objective, cls == weaponClass {
                bump(mission, by: 1)
            }
        }
    }

    private func advanceWeaponKills(_ id: WeaponID) {
        for mission in activeMissions {
            if case let .killsWithWeapon(weaponID, _) = mission.objective, weaponID == id {
                bump(mission, by: 1)
            }
        }
    }

    private func advanceStreak(_ length: Int) {
        for mission in activeMissions {
            if case let .killStreak(required) = mission.objective, length >= required {
                setProgress(mission.id, to: required)
            }
        }
    }

    private func bump(_ mission: Mission, by amount: Int) {
        var p = progress[mission.id] ?? MissionProgress(missionID: mission.id)
        let wasComplete = p.isComplete(target: mission.objective.target)
        p.progress = min(mission.objective.target, p.progress + amount)
        progress[mission.id] = p
        if !wasComplete && p.isComplete(target: mission.objective.target) {
            onMissionCompleted?(mission)
        }
    }

    private func setProgress(_ id: MissionID, to value: Int) {
        guard let mission = activeMissions.first(where: { $0.id == id }) else { return }
        var p = progress[id] ?? MissionProgress(missionID: id)
        let wasComplete = p.isComplete(target: mission.objective.target)
        p.progress = max(p.progress, min(value, mission.objective.target))
        progress[id] = p
        if !wasComplete && p.isComplete(target: mission.objective.target) {
            onMissionCompleted?(mission)
        }
    }

    private func sameKind(_ a: MissionObjective, _ b: MissionObjective) -> Bool {
        switch (a, b) {
        case (.kills, .kills), (.headshots, .headshots), (.wins, .wins),
             (.matchesPlayed, .matchesPlayed), (.damageDealt, .damageDealt),
             (.objectivesCaptured, .objectivesCaptured), (.bombsPlanted, .bombsPlanted),
             (.bombsDefused, .bombsDefused), (.grenadeKills, .grenadeKills),
             (.meleeKills, .meleeKills), (.wallbangs, .wallbangs),
             (.playTimeMinutes, .playTimeMinutes):
            return true
        default:
            return false
        }
    }
}
