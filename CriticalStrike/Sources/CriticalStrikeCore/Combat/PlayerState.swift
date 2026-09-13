import Foundation

public enum Stance: UInt8, Codable, Sendable {
    case standing = 0, crouching, sliding, airborne, dead

    public var heightScale: Float {
        switch self {
        case .crouching: return 0.62
        case .sliding: return 0.52
        default: return 1.0
        }
    }

    public var eyeHeight: Float {
        switch self {
        case .crouching: return 1.12
        case .sliding: return 0.95
        case .dead: return 0.3
        default: return 1.65
        }
    }
}

/// Per-weapon live ammunition and heat state.
public struct WeaponSlotState: Codable, Sendable {
    public var build: WeaponBuild
    public var ammoInMagazine: Int
    public var reserveAmmo: Int
    public var shotsFiredInSpray: Int
    public var burstRemaining: Int

    public init(build: WeaponBuild, extraMagazines: Int = 0) {
        self.build = build
        let w = build.resolved()
        self.ammoInMagazine = w.magazineSize
        self.reserveAmmo = w.reserveAmmo + extraMagazines * w.magazineSize
        self.shotsFiredInSpray = 0
        self.burstRemaining = 0
    }

    public var resolvedWeapon: WeaponData { build.resolved() }
    public var isEmpty: Bool { ammoInMagazine <= 0 }
    public var canReload: Bool {
        let w = resolvedWeapon
        return w.magazineSize > 0 && ammoInMagazine < w.magazineSize && reserveAmmo > 0
    }
    public var totalAmmo: Int { ammoInMagazine + reserveAmmo }
}

public enum WeaponAction: UInt8, Codable, Sendable {
    case ready = 0, firing, reloading, drawing, holstering, throwingGrenade, meleeSwing, planting, defusing
}

/// Everything about one player that the simulation owns. Deliberately a value type:
/// snapshots, rollback and lag compensation all copy it.
public struct PlayerState: Codable, Sendable {
    public var id: PlayerID
    public var name: String
    public var team: Team
    public var isBot: Bool
    public var isAlive: Bool
    public var connected: Bool

    // Transform
    public var position: Vec3
    public var velocity: Vec3
    public var angles: ViewAngles
    public var stance: Stance
    public var onGround: Bool
    public var groundSurface: SurfaceKind

    // Vitals
    public var health: Float
    public var maxHealth: Float
    public var armor: Float
    public var maxArmor: Float
    public var hasHelmet: Bool
    public var lastDamagedAt: Float
    public var lastAttacker: PlayerID

    // Weapons
    public var slots: [LoadoutSlot: WeaponSlotState]
    public var activeSlot: LoadoutSlot
    public var action: WeaponAction
    public var actionTimer: Timer
    public var slideTimer: Timer
    /// Set when a weapon switch is queued behind the holster animation.
    public var pendingSlot: LoadoutSlot?
    /// Set while a grenade is being wound up.
    public var pendingGrenade: ContentID?
    /// Semi-automatic weapons require the trigger to be released between shots.
    public var semiTriggerReady: Bool
    /// True while the interact button is held (plant, defuse, pick up).
    public var isUsing: Bool
    public var fireCooldown: Float
    public var isAiming: Bool
    public var adsProgress: Float          // 0 hip → 1 fully aimed
    public var scopeLevel: Int
    public var currentSpread: Float
    public var recoilOffset: ViewAngles    // accumulated, decays back to zero
    public var recoilPunch: ViewAngles     // visual-only kick
    public var lethalCount: Int
    public var tacticalCount: Int
    public var lethalID: ContentID
    public var tacticalID: ContentID

    // Status effects
    public var flashAmount: Float
    public var flashDecayRate: Float
    public var stunAmount: Float
    public var slowUntil: Float
    public var burningUntil: Float
    public var invulnerableUntil: Float
    public var doubleDamageUntil: Float
    public var speedBoostUntil: Float
    public var overshieldUntil: Float
    public var inSmokeUntil: Float

    // Objective / economy
    public var money: Int
    public var hasBomb: Bool
    public var hasDefuseKit: Bool
    public var plantProgress: Float
    public var defuseProgress: Float

    // Scoring
    public var kills: Int
    public var deaths: Int
    public var assists: Int
    public var score: Int
    public var currentStreak: Int
    public var bestStreak: Int
    public var damageDealt: Float
    public var headshots: Int
    public var gunGameLevel: Int
    public var respawnTimer: Timer
    public var perks: PerkEffects
    public var loadout: Loadout

    // Bookkeeping
    public var lastFootstepDistance: Float
    public var lastFireTime: Float
    public var lastNoiseTime: Float
    public var lastNoisePosition: Vec3
    public var pendingDamageCredits: [PlayerID: Float]

    public init(id: PlayerID, name: String, team: Team, isBot: Bool, loadout: Loadout) {
        self.id = id; self.name = name; self.team = team; self.isBot = isBot
        self.isAlive = false; self.connected = true
        self.position = .zero; self.velocity = .zero; self.angles = ViewAngles()
        self.stance = .standing; self.onGround = true; self.groundSurface = .concrete
        let effects = loadout.perkEffects
        self.maxHealth = 100 + effects.healthBonus
        self.health = maxHealth
        self.maxArmor = 100; self.armor = effects.armorBonus
        self.hasHelmet = false; self.lastDamagedAt = -999; self.lastAttacker = .none
        self.slots = [:]
        self.activeSlot = .primary
        self.action = .ready; self.actionTimer = Timer(); self.slideTimer = Timer()
        self.pendingSlot = nil; self.pendingGrenade = nil; self.semiTriggerReady = true
        self.isUsing = false
        self.fireCooldown = 0
        self.isAiming = false; self.adsProgress = 0; self.scopeLevel = 0
        self.currentSpread = 0; self.recoilOffset = ViewAngles(); self.recoilPunch = ViewAngles()
        self.lethalCount = 1 + effects.extraGrenades
        self.tacticalCount = 1 + effects.extraGrenades
        self.lethalID = loadout.lethal; self.tacticalID = loadout.tactical
        self.flashAmount = 0; self.flashDecayRate = 1; self.stunAmount = 0
        self.slowUntil = 0; self.burningUntil = 0; self.invulnerableUntil = 0
        self.doubleDamageUntil = 0; self.speedBoostUntil = 0; self.overshieldUntil = 0
        self.inSmokeUntil = 0
        self.money = 800; self.hasBomb = false; self.hasDefuseKit = false
        self.plantProgress = 0; self.defuseProgress = 0
        self.kills = 0; self.deaths = 0; self.assists = 0; self.score = 0
        self.currentStreak = 0; self.bestStreak = 0; self.damageDealt = 0; self.headshots = 0
        self.gunGameLevel = 0; self.respawnTimer = Timer()
        self.perks = effects; self.loadout = loadout
        self.lastFootstepDistance = 0; self.lastFireTime = -999
        self.lastNoiseTime = -999; self.lastNoisePosition = .zero
        self.pendingDamageCredits = [:]
    }

    // MARK: Derived

    public var eyePosition: Vec3 { position + Vec3(0, stance.eyeHeight, 0) }
    public var activeSlotState: WeaponSlotState? { slots[activeSlot] }
    public var activeWeapon: WeaponData {
        slots[activeSlot]?.resolvedWeapon ?? WeaponDatabase.weaponOrDefault(WeaponDatabase.defaultMelee)
    }
    public var isBusy: Bool { action != .ready && action != .firing }
    public var isFlashed: Bool { flashAmount > 0.05 }
    public var bounds: AABB { HitboxLayout.bounds(at: position, crouchScale: stance.heightScale) }
    public var kdRatio: Float { deaths == 0 ? Float(kills) : Float(kills) / Float(deaths) }

    public func isInvulnerable(now: Float) -> Bool { now < invulnerableUntil }
    public func hasDoubleDamage(now: Float) -> Bool { now < doubleDamageUntil }
    public func hasOvershield(now: Float) -> Bool { now < overshieldUntil }
    public func isSlowed(now: Float) -> Bool { now < slowUntil }

    /// Movement speed multiplier from every active source.
    public func speedScale(now: Float) -> Float {
        var s = perks.moveSpeedScale * activeWeapon.movementSpeedScale
        if isAiming { s *= MathUtil.lerp(1, activeWeapon.adsMovementScale, adsProgress) }
        if isSlowed(now: now) { s *= 0.72 }
        if now < speedBoostUntil { s *= 1.25 }
        if stunAmount > 0 { s *= MathUtil.lerp(1, 0.55, MathUtil.clamp(stunAmount, 0, 1)) }
        return s
    }

    public mutating func giveLoadout(_ loadout: Loadout, mode: GameModeData) {
        self.loadout = loadout
        self.perks = loadout.perkEffects
        slots = [
            .primary: WeaponSlotState(build: loadout.primary, extraMagazines: perks.extraMagazines),
            .secondary: WeaponSlotState(build: loadout.secondary, extraMagazines: perks.extraMagazines),
            .melee: WeaponSlotState(build: loadout.melee)
        ]
        activeSlot = .primary
        lethalID = loadout.lethal
        tacticalID = loadout.tactical
        lethalCount = (GrenadeDatabase.grenade(loadout.lethal)?.maxCarried ?? 1) + perks.extraGrenades
        tacticalCount = (GrenadeDatabase.grenade(loadout.tactical)?.maxCarried ?? 1) + perks.extraGrenades
        maxHealth = mode.startingHealth + perks.healthBonus
        health = maxHealth
        armor = min(maxArmor, mode.startingArmor + perks.armorBonus)
        hasHelmet = armor > 0
    }

    public mutating func resetForRespawn(at spawn: SpawnPoint, mode: GameModeData, now: Float) {
        position = spawn.position
        velocity = .zero
        angles = ViewAngles(pitch: 0, yaw: spawn.yaw)
        stance = .standing
        onGround = true
        isAlive = true
        health = maxHealth
        armor = min(maxArmor, mode.startingArmor + perks.armorBonus)
        hasHelmet = armor > 0
        action = .ready
        actionTimer.stop()
        slideTimer.stop()
        pendingSlot = nil
        pendingGrenade = nil
        semiTriggerReady = true
        isUsing = false
        fireCooldown = 0
        isAiming = false
        adsProgress = 0
        scopeLevel = 0
        currentSpread = 0
        recoilOffset = ViewAngles()
        recoilPunch = ViewAngles()
        flashAmount = 0
        stunAmount = 0
        slowUntil = 0
        burningUntil = 0
        plantProgress = 0
        defuseProgress = 0
        invulnerableUntil = now + mode.respawnInvulnerability
        pendingDamageCredits.removeAll(keepingCapacity: true)
        for slot in Array(slots.keys) {
            if var s = slots[slot] {
                let w = s.resolvedWeapon
                s.ammoInMagazine = w.magazineSize
                s.reserveAmmo = w.reserveAmmo + perks.extraMagazines * w.magazineSize
                s.shotsFiredInSpray = 0
                s.burstRemaining = 0
                slots[slot] = s
            }
        }
        activeSlot = slots[.primary] != nil ? .primary : .melee
        lethalCount = (GrenadeDatabase.grenade(lethalID)?.maxCarried ?? 1) + perks.extraGrenades
        tacticalCount = (GrenadeDatabase.grenade(tacticalID)?.maxCarried ?? 1) + perks.extraGrenades
    }

    /// Applies damage and reports whether it was fatal.
    public mutating func applyDamage(_ result: DamageResult, from attacker: PlayerID, now: Float) -> Bool {
        armor = max(0, armor - result.armor)
        if armor <= 0 { hasHelmet = false }
        health -= result.health
        lastDamagedAt = now
        if attacker.isValid && attacker != id {
            lastAttacker = attacker
            pendingDamageCredits[attacker, default: 0] += result.total
        }
        if health <= 0 {
            health = 0
            return true
        }
        return false
    }
}
