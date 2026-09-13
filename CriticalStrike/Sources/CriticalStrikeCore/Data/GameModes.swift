import Foundation

public enum GameModeKind: String, Codable, CaseIterable, Sendable {
    case teamDeathmatch
    case freeForAll
    case bombDefusal
    case domination
    case gunGame
    case searchAndRescue
    case killConfirmed
    case hardpoint
    case oneInTheChamber
    case zombies
    case training

    public var displayName: String {
        switch self {
        case .teamDeathmatch: return "Team Deathmatch"
        case .freeForAll: return "Free For All"
        case .bombDefusal: return "Bomb Defusal"
        case .domination: return "Domination"
        case .gunGame: return "Gun Game"
        case .searchAndRescue: return "Search & Rescue"
        case .killConfirmed: return "Kill Confirmed"
        case .hardpoint: return "Hardpoint"
        case .oneInTheChamber: return "One in the Chamber"
        case .zombies: return "Zombie Survival"
        case .training: return "Training Range"
        }
    }

    public var shortName: String {
        switch self {
        case .teamDeathmatch: return "TDM"
        case .freeForAll: return "FFA"
        case .bombDefusal: return "BOMB"
        case .domination: return "DOM"
        case .gunGame: return "GUN"
        case .searchAndRescue: return "S&R"
        case .killConfirmed: return "KC"
        case .hardpoint: return "HP"
        case .oneInTheChamber: return "OITC"
        case .zombies: return "ZMB"
        case .training: return "RANGE"
        }
    }

    public var isTeamBased: Bool {
        switch self {
        case .freeForAll, .gunGame, .oneInTheChamber, .training: return false
        default: return true
        }
    }

    public var isRoundBased: Bool {
        switch self {
        case .bombDefusal, .searchAndRescue: return true
        default: return false
        }
    }

    /// Round-based modes have no respawn; everything else does.
    public var allowsRespawn: Bool { !isRoundBased && self != .zombies }

    public var usesBuyMenu: Bool { isRoundBased }

    public var iconName: String { "icon_mode_\(rawValue)" }
}

public struct GameModeData: Codable, Identifiable, Sendable {
    public var id: ContentID
    public var kind: GameModeKind
    public var name: String
    public var summary: String

    public var teamSize: Int
    public var maxPlayers: Int
    public var scoreLimit: Int
    public var timeLimitSeconds: Float
    public var roundsToWin: Int
    public var roundTimeSeconds: Float
    public var warmupSeconds: Float
    public var freezeTimeSeconds: Float
    public var respawnDelay: Float
    public var respawnInvulnerability: Float
    public var friendlyFire: Bool
    public var healthRegen: Bool
    public var regenDelay: Float
    public var regenRate: Float
    public var startingHealth: Float
    public var startingArmor: Float
    public var startingMoney: Int
    public var killReward: Int
    public var xpMultiplier: Float
    public var minimapShowsEnemies: Bool
    public var overtimeEnabled: Bool
    public var unlockLevel: Int

    public init(id: ContentID, kind: GameModeKind, name: String? = nil, summary: String,
                teamSize: Int = 5, maxPlayers: Int = 10, scoreLimit: Int = 75,
                timeLimitSeconds: Float = 600, roundsToWin: Int = 0, roundTimeSeconds: Float = 0,
                warmupSeconds: Float = 12, freezeTimeSeconds: Float = 0, respawnDelay: Float = 4,
                respawnInvulnerability: Float = 1.2, friendlyFire: Bool = false,
                healthRegen: Bool = true, regenDelay: Float = 5, regenRate: Float = 22,
                startingHealth: Float = 100, startingArmor: Float = 0, startingMoney: Int = 0,
                killReward: Int = 0, xpMultiplier: Float = 1, minimapShowsEnemies: Bool = false,
                overtimeEnabled: Bool = true, unlockLevel: Int = 1) {
        self.id = id; self.kind = kind; self.name = name ?? kind.displayName; self.summary = summary
        self.teamSize = teamSize; self.maxPlayers = maxPlayers; self.scoreLimit = scoreLimit
        self.timeLimitSeconds = timeLimitSeconds; self.roundsToWin = roundsToWin
        self.roundTimeSeconds = roundTimeSeconds; self.warmupSeconds = warmupSeconds
        self.freezeTimeSeconds = freezeTimeSeconds; self.respawnDelay = respawnDelay
        self.respawnInvulnerability = respawnInvulnerability; self.friendlyFire = friendlyFire
        self.healthRegen = healthRegen; self.regenDelay = regenDelay; self.regenRate = regenRate
        self.startingHealth = startingHealth; self.startingArmor = startingArmor
        self.startingMoney = startingMoney; self.killReward = killReward
        self.xpMultiplier = xpMultiplier; self.minimapShowsEnemies = minimapShowsEnemies
        self.overtimeEnabled = overtimeEnabled; self.unlockLevel = unlockLevel
    }
}

public enum GameModeDatabase {
    public static let all: [GameModeData] = [
        GameModeData(id: "mode_tdm", kind: .teamDeathmatch,
                     summary: "First team to 75 kills wins. Respawns enabled.",
                     teamSize: 5, maxPlayers: 10, scoreLimit: 75, timeLimitSeconds: 600,
                     respawnDelay: 3.5, killReward: 0, xpMultiplier: 1.0),

        GameModeData(id: "mode_ffa", kind: .freeForAll,
                     summary: "Everyone for themselves. 30 kills takes it.",
                     teamSize: 1, maxPlayers: 8, scoreLimit: 30, timeLimitSeconds: 480,
                     respawnDelay: 3, xpMultiplier: 1.05),

        GameModeData(id: "mode_bomb", kind: .bombDefusal,
                     summary: "Plant or defuse. No respawns. Best of 15 rounds.",
                     teamSize: 5, maxPlayers: 10, scoreLimit: 0, timeLimitSeconds: 0,
                     roundsToWin: 8, roundTimeSeconds: 115, warmupSeconds: 15, freezeTimeSeconds: 12,
                     respawnDelay: 0, friendlyFire: true, healthRegen: false,
                     startingArmor: 0, startingMoney: 800, killReward: 300,
                     xpMultiplier: 1.35, unlockLevel: 3),

        GameModeData(id: "mode_dom", kind: .domination,
                     summary: "Hold A, B and C. Points tick while you own them.",
                     teamSize: 5, maxPlayers: 10, scoreLimit: 200, timeLimitSeconds: 720,
                     respawnDelay: 4, xpMultiplier: 1.2, unlockLevel: 2),

        GameModeData(id: "mode_gungame", kind: .gunGame,
                     summary: "Every kill upgrades your weapon. Knife the last one to win.",
                     teamSize: 1, maxPlayers: 8, scoreLimit: 18, timeLimitSeconds: 600,
                     respawnDelay: 2.5, xpMultiplier: 1.1, unlockLevel: 5),

        GameModeData(id: "mode_sar", kind: .searchAndRescue,
                     summary: "One life per round — revive your teammates' tags to bring them back.",
                     teamSize: 5, maxPlayers: 10, roundsToWin: 6, roundTimeSeconds: 150,
                     freezeTimeSeconds: 10, respawnDelay: 0, healthRegen: false,
                     startingMoney: 1000, killReward: 300, xpMultiplier: 1.4, unlockLevel: 12),

        GameModeData(id: "mode_kc", kind: .killConfirmed,
                     summary: "Kills only count when you collect the dog tag.",
                     teamSize: 5, maxPlayers: 10, scoreLimit: 65, timeLimitSeconds: 600,
                     respawnDelay: 3.5, xpMultiplier: 1.15, unlockLevel: 7),

        GameModeData(id: "mode_hardpoint", kind: .hardpoint,
                     summary: "One rotating objective. Hold it to score.",
                     teamSize: 5, maxPlayers: 10, scoreLimit: 250, timeLimitSeconds: 600,
                     respawnDelay: 4.5, xpMultiplier: 1.25, unlockLevel: 9),

        GameModeData(id: "mode_oitc", kind: .oneInTheChamber,
                     summary: "One bullet, one life. Every kill reloads you.",
                     teamSize: 1, maxPlayers: 6, scoreLimit: 15, timeLimitSeconds: 420,
                     respawnDelay: 3, healthRegen: false, startingHealth: 1,
                     xpMultiplier: 1.3, unlockLevel: 15),

        GameModeData(id: "mode_zombies", kind: .zombies,
                     summary: "Survive endless waves. Buy your way deeper.",
                     teamSize: 4, maxPlayers: 4, scoreLimit: 0, timeLimitSeconds: 0,
                     warmupSeconds: 8, respawnDelay: 0, healthRegen: true, regenDelay: 6,
                     startingMoney: 500, killReward: 60, xpMultiplier: 1.2, unlockLevel: 18),

        GameModeData(id: "mode_training", kind: .training,
                     summary: "Practice range: targets, spray patterns, grenade lineups.",
                     teamSize: 1, maxPlayers: 1, scoreLimit: 0, timeLimitSeconds: 0,
                     warmupSeconds: 0, respawnDelay: 1, healthRegen: true,
                     xpMultiplier: 0, unlockLevel: 1)
    ]

    private static let index: [GameModeKind: GameModeData] = {
        var m = [GameModeKind: GameModeData](); for g in all { m[g.kind] = g }; return m
    }()

    public static func mode(_ kind: GameModeKind) -> GameModeData {
        index[kind] ?? all[0]
    }
    public static func modes(unlockedAt level: Int) -> [GameModeData] {
        all.filter { $0.unlockLevel <= level && $0.kind != .training }
    }
    /// Gun Game progression: cheap and fast at the start, precise at the end.
    public static let gunGameLadder: [WeaponID] = [
        "smg_wasp", "ar_vanguard", "smg_hornet", "sg_breaker", "ar_falcon",
        "pst_tacmachine", "lmg_bulwark", "mrk_ranger", "ar_krait", "smg_viper",
        "sg_havoc", "ar_tempest", "snp_specter", "pst_sidearm", "snp_longbow",
        "pst_magnum", "mel_combatknife"
    ]
}
