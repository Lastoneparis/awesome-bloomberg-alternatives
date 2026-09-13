import Foundation
import CriticalStrikeCore

/// A flat snapshot of everything the HUD draws. Publishing one value type instead of
/// twenty `@Published` properties means SwiftUI does exactly one diff per HUD update.
struct HUDState: Equatable {
    // Vitals
    var health: Float = 100
    var maxHealth: Float = 100
    var armor: Float = 0
    var maxArmor: Float = 100

    // Weapon
    var ammoInMagazine: Int = 30
    var reserveAmmo: Int = 90
    var magazineSize: Int = 30
    var weaponName: String = ""
    var weaponID: WeaponID = ""
    var crosshairKind: CrosshairKind = .cross
    var spread: Float = 0.02
    var adsProgress: Float = 0
    var scopeLevel: Int = 0
    var isScoped: Bool = false
    var isReloading: Bool = false
    var reloadProgress: Float = 0

    // Player
    var isAlive: Bool = true
    var respawnSeconds: Float = 0
    var lethalCount: Int = 1
    var tacticalCount: Int = 1
    var lethalID: ContentID = "nade_frag"
    var tacticalID: ContentID = "nade_flash"
    var flashAmount: Float = 0
    var stunAmount: Float = 0
    var lowHealthPulse: Bool = false
    var isBurning: Bool = false
    var hasTargetUnderCrosshair: Bool = false

    // Match
    var strikeScore: Int = 0
    var shieldScore: Int = 0
    var scoreLimit: Int = 0
    var round: Int = 0
    var phase: MatchPhase = .live
    var phaseTimeRemaining: Float = 0
    var matchTimeRemaining: Float = 0
    var objectiveHeadline: String = ""
    var objectiveDetail: String = ""
    var strikeObjectiveProgress: Float = 0
    var shieldObjectiveProgress: Float = 0

    // Bomb
    var bombPlanted: Bool = false
    var bombTimeRemaining: Float = 0
    var plantProgress: Float = 0
    var defuseProgress: Float = 0
    var canPlant: Bool = false
    var canDefuse: Bool = false

    // Economy / score
    var money: Int = 0
    var killStreak: Int = 0
    var kills: Int = 0
    var deaths: Int = 0
    var team: Team = .none
    var callout: String = ""
    var connectionQuality: ConnectionQuality = .excellent

    // Markers
    var teammates: [MinimapMarker] = []
    var minimapEnemies: [MinimapMarker] = []

    // Transient feedback (timestamps compared against the sim clock)
    var hitMarkerTimestamp: Float = -99
    var lastHitWasHeadshot: Bool = false
    var killConfirmTimestamp: Float = -99
    var announcement: String = ""
    var announcementTimestamp: Float = -99
    var streakBanner: String = ""
    var streakBannerTimestamp: Float = -99

    // Derived
    var healthFraction: Float { maxHealth > 0 ? MathUtil.clamp(health / maxHealth, 0, 1) : 0 }
    var armorFraction: Float { maxArmor > 0 ? MathUtil.clamp(armor / maxArmor, 0, 1) : 0 }
    var ammoFraction: Float {
        magazineSize > 0 ? MathUtil.clamp(Float(ammoInMagazine) / Float(magazineSize), 0, 1) : 0
    }
    var isLowAmmo: Bool { magazineSize > 0 && ammoFraction < 0.25 }
    var isOutOfAmmo: Bool { ammoInMagazine == 0 && reserveAmmo == 0 }

    var formattedPhaseTime: String {
        let seconds = max(0, Int(phaseTimeRemaining.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var formattedMatchTime: String {
        let seconds = max(0, Int(matchTimeRemaining.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var formattedBombTime: String {
        String(format: "%.1f", max(0, bombTimeRemaining))
    }
}

struct MinimapMarker: Identifiable, Equatable {
    var id: PlayerID
    var position: Vec3
    var yaw: Float
    var team: Team
    var isEnemy: Bool
    var name: String
}

struct DamageIndicator: Identifiable, Equatable {
    let id = UUID()
    /// Angle relative to the player's facing, in radians. 0 = directly ahead.
    var direction: Float
    var amount: Float
    var timestamp: Float
}

struct FloatingDamage: Identifiable, Equatable {
    let id = UUID()
    var amount: Float
    var headshot: Bool
    var worldPosition: Vec3
    var timestamp: Float
}
