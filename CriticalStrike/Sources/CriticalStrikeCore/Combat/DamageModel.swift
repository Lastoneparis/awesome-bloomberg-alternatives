import Foundation

public struct DamageResult: Equatable, Sendable {
    /// Damage that reached health.
    public var health: Float
    /// Damage absorbed by armor (armor is consumed by this amount).
    public var armor: Float
    /// Everything the attacker "dealt" — what the hit marker and damage numbers show.
    public var total: Float { health + armor }
    public func isLethal(against currentHealth: Float) -> Bool { health >= currentHealth }

    public init(health: Float, armor: Float) {
        self.health = health; self.armor = armor
    }

    public static let none = DamageResult(health: 0, armor: 0)

    public static func == (a: DamageResult, b: DamageResult) -> Bool {
        abs(a.health - b.health) < 1e-4 && abs(a.armor - b.armor) < 1e-4
    }
}

public enum DamageModel {
    /// Fraction of blocked damage that actually wears the armor down. Lower values mean
    /// armor lasts longer; 0.5 is tuned so a full plate survives roughly one rifle mag.
    public static let armorWearFactor: Float = 0.5
    /// How much of the non-penetrating damage armor stops when it is intact.
    public static let armorBlockFraction: Float = 0.55

    /// Distance falloff curve. Flat inside `falloffStart`, linear to `falloffEnd`, flat after.
    public static func falloffScale(distance: Float, weapon: WeaponData) -> Float {
        if distance <= weapon.falloffStart { return 1 }
        if weapon.falloffEnd <= weapon.falloffStart { return weapon.falloffMinScale }
        let t = MathUtil.unlerp(weapon.falloffStart, weapon.falloffEnd, distance)
        return MathUtil.lerp(1, weapon.falloffMinScale, t)
    }

    /// The single entry point every damage source funnels through.
    /// - Parameters:
    ///   - base: raw damage before any modifier (usually `weapon.baseDamage`, or the
    ///           explosion's damage at that distance).
    ///   - penetratedSurfaces: how many solid surfaces the round crossed on the way.
    public static func resolve(base: Float,
                               distance: Float,
                               weapon: WeaponData,
                               hitbox: HitboxKind,
                               armor: Float,
                               penetratedSurfaces: Int,
                               hasHelmet: Bool = true,
                               damageScale: Float = 1,
                               resistance: Float = 0) -> DamageResult {
        guard base > 0 else { return .none }

        var damage = base * falloffScale(distance: distance, weapon: weapon)
        damage *= hitbox.damageMultiplier
        if hitbox.isHead { damage *= weapon.headshotMultiplier }
        if penetratedSurfaces > 0 {
            damage *= pow(weapon.penetrationDamageScale, Float(penetratedSurfaces))
        }
        damage *= damageScale
        damage *= (1 - MathUtil.clamp(resistance, 0, 0.95))

        let armorApplies = armor > 0 && (hitbox.isArmorCovered || (hitbox.isHead && hasHelmet))
        guard armorApplies else { return DamageResult(health: damage, armor: 0) }

        // Part of the damage punches straight through; the rest is contested by the plate.
        let throughput = MathUtil.clamp(weapon.armorPenetration, 0, 1)
        let unblocked = damage * throughput
        let contested = damage - unblocked
        let blocked = contested * armorBlockFraction
        let leaked = contested - blocked

        var armorDamage = blocked * armorWearFactor
        var healthDamage = unblocked + leaked

        // Armor that runs out mid-hit stops less than it wanted to.
        if armorDamage > armor {
            let overflowRatio = (armorDamage - armor) / max(armorDamage, 0.0001)
            healthDamage += blocked * overflowRatio
            armorDamage = armor
        }
        return DamageResult(health: healthDamage, armor: armorDamage)
    }

    /// Radial (explosion) damage with a smooth inner→outer falloff and optional
    /// line-of-sight attenuation for targets behind cover.
    public static func explosion(damage: Float, innerRadius: Float, outerRadius: Float,
                                 distance: Float, occluded: Bool, resistance: Float = 0) -> Float {
        guard distance <= outerRadius else { return 0 }
        let t = distance <= innerRadius ? 0 : MathUtil.unlerp(innerRadius, outerRadius, distance)
        // Quadratic falloff reads better than linear: the edge of a frag should sting, not kill.
        var d = damage * (1 - t * t)
        if occluded { d *= 0.35 }
        d *= (1 - MathUtil.clamp(resistance, 0, 0.95))
        return max(0, d)
    }

    /// Falling damage. Nothing below 4m hurts; 12m+ is fatal from full health.
    public static func fallDamage(impactSpeed: Float, scale: Float = 1) -> Float {
        let safeSpeed: Float = 9.0       // ~4m drop
        guard impactSpeed > safeSpeed else { return 0 }
        let over = impactSpeed - safeSpeed
        return min(100, over * over * 0.45) * scale
    }

    /// Flash intensity 0...1 from how centred and close the flashbang was.
    public static func flashIntensity(eye: Vec3, viewForward: Vec3, flashPosition: Vec3,
                                      radius: Float, occluded: Bool, resistance: Float) -> Float {
        let toFlash = flashPosition - eye
        let distance = toFlash.length
        guard distance <= radius, !occluded else { return 0 }
        let distanceTerm = 1 - MathUtil.unlerp(0, radius, distance)
        let facing = MathUtil.clamp(toFlash.normalized.dot(viewForward), -1, 1)
        // Looking straight at it = full blind; back turned = a brief wash.
        let facingTerm = MathUtil.remap(facing, -1, 1, 0.12, 1)
        return MathUtil.clamp(distanceTerm * facingTerm * (1 - resistance), 0, 1)
    }

    /// Time-to-kill in seconds for the balance tooling and the loadout UI.
    public static func timeToKill(weapon: WeaponData, health: Float = 100, armor: Float = 0,
                                  distance: Float = 0, headshotRatio: Float = 0) -> Float {
        let body = resolve(base: weapon.baseDamage * Float(weapon.pelletsPerShot), distance: distance,
                           weapon: weapon, hitbox: .chest, armor: armor, penetratedSurfaces: 0).total
        let head = resolve(base: weapon.baseDamage * Float(weapon.pelletsPerShot), distance: distance,
                           weapon: weapon, hitbox: .head, armor: armor, penetratedSurfaces: 0).total
        let perShot = MathUtil.lerp(body, head, MathUtil.clamp(headshotRatio, 0, 1))
        guard perShot > 0 else { return .infinity }
        let shots = max(1, Int(ceil(health / perShot)))
        if weapon.fireMode == .burst {
            let bursts = Int(ceil(Float(shots) / Float(max(weapon.burstCount, 1))))
            let shotsInLastBurst = shots - (bursts - 1) * weapon.burstCount
            return Float(bursts - 1) * (Float(weapon.burstCount - 1) * weapon.fireInterval + weapon.burstDelay)
                 + Float(max(shotsInLastBurst - 1, 0)) * weapon.fireInterval
        }
        return Float(shots - 1) * weapon.fireInterval
    }
}
