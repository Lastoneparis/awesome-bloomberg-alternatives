import Foundation

/// Recoil has two halves:
///   * `recoilOffset` — a real aim offset the player must pull down against. Deterministic
///     for the first N shots (the learnable spray pattern), random after.
///   * `recoilPunch`  — a purely visual camera kick that decays fast and never affects aim.
/// Spread is separate again: it is the cone the bullet can land in, and it is what
/// movement, jumping and crouching modify.
public enum RecoilSystem {
    /// Called once per shot.
    public static func applyShot(player: inout PlayerState, weapon: WeaponData,
                                 shotIndex: Int, rng: inout DeterministicRandom) {
        var up: Float
        var side: Float

        if shotIndex < weapon.sprayPattern.count {
            let point = weapon.sprayPattern[shotIndex]
            let previous = shotIndex > 0 ? weapon.sprayPattern[shotIndex - 1] : SprayPoint(0, 0)
            // Patterns store absolute offsets; convert to a per-shot delta.
            up = (point.up - previous.up) * (weapon.recoilVertical / 0.011)
            side = (point.side - previous.side) * (weapon.recoilHorizontal / 0.004)
            // A little jitter keeps the pattern learnable without being a laser.
            up += rng.signedUnit() * weapon.recoilVertical * 0.12
            side += rng.signedUnit() * weapon.recoilHorizontal * 0.18
        } else {
            up = weapon.recoilVertical * rng.float(in: 0.7...1.25)
            side = weapon.recoilHorizontal * rng.signedUnit() * 1.4
        }

        // Aiming down sights is meaningfully more controllable.
        let adsScale = MathUtil.lerp(1.0, 0.72, player.adsProgress)
        // Crouching further steadies the gun.
        let stanceScale: Float = player.stance == .crouching ? 0.82 : 1.0
        let airborneScale: Float = player.onGround ? 1.0 : 1.45

        let scale = adsScale * stanceScale * airborneScale
        player.recoilOffset.pitch += up * scale
        player.recoilOffset.yaw += side * scale

        // Visual punch is bigger than the aim offset — it sells the impact.
        player.recoilPunch.pitch += up * scale * 2.1
        player.recoilPunch.yaw += side * scale * 1.6
        player.recoilPunch.roll += side * scale * 6.0

        // Spread bloom.
        player.currentSpread = min(weapon.maxSpread, player.currentSpread + weapon.spreadPerShot)
    }

    /// Called every tick.
    public static func decay(player: inout PlayerState, weapon: WeaponData, dt: Float) {
        // Aim offset recovers towards zero; the player's own pull-down combines with it.
        let recovery = weapon.recoilRecoverySpeed * dt
        player.recoilOffset.pitch = MathUtil.moveTowards(player.recoilOffset.pitch, 0,
                                                         maxDelta: abs(player.recoilOffset.pitch) * recovery + 0.0006)
        player.recoilOffset.yaw = MathUtil.moveTowards(player.recoilOffset.yaw, 0,
                                                       maxDelta: abs(player.recoilOffset.yaw) * recovery + 0.0006)

        // Visual punch snaps back much faster.
        let punchHalfLife: Float = 0.055
        player.recoilPunch.pitch = MathUtil.damp(player.recoilPunch.pitch, 0, halfLife: punchHalfLife, dt: dt)
        player.recoilPunch.yaw = MathUtil.damp(player.recoilPunch.yaw, 0, halfLife: punchHalfLife, dt: dt)
        player.recoilPunch.roll = MathUtil.damp(player.recoilPunch.roll, 0, halfLife: punchHalfLife * 1.6, dt: dt)

        // Spread recovers linearly.
        player.currentSpread = max(0, player.currentSpread - weapon.spreadRecovery * dt)
    }

    /// Total cone half-angle for the next shot, in radians.
    public static func effectiveSpread(player: PlayerState, weapon: WeaponData) -> Float {
        let aimBase = MathUtil.lerp(weapon.baseSpread, weapon.adsSpread, player.adsProgress)
        var spread = aimBase + player.currentSpread

        let horizontalSpeed = player.velocity.horizontalLength
        if horizontalSpeed > 0.6 {
            let moveFactor = MathUtil.clamp(horizontalSpeed / MovementSystem.runSpeed, 0, 1.4)
            spread += weapon.moveSpreadPenalty * moveFactor
        }
        if !player.onGround {
            spread += weapon.jumpSpreadPenalty
        } else if player.stance == .crouching {
            spread *= weapon.crouchSpreadBonus
        } else if player.stance == .sliding {
            spread += weapon.moveSpreadPenalty * 1.5
        }
        if player.stunAmount > 0 { spread *= 1 + player.stunAmount * 0.8 }

        return max(0, spread)
    }

    /// Applies a spread cone to an aim direction.
    public static func spreadDirection(_ direction: Vec3, spread: Float,
                                       rng: inout DeterministicRandom) -> Vec3 {
        guard spread > 1e-5 else { return direction }
        let (right, up) = Geometry.basis(forward: direction)
        let (dx, dy) = rng.insideUnitDisk()
        return (direction + right * (dx * spread) + up * (dy * spread)).normalized
    }

    /// Where the crosshair should sit on screen: the aim offset from recoil, in radians.
    public static func aimDirection(for player: PlayerState) -> Vec3 {
        var angles = player.angles
        angles.pitch = MathUtil.clamp(angles.pitch + player.recoilOffset.pitch,
                                      -ViewAngles.maxPitch, ViewAngles.maxPitch)
        angles.yaw = MathUtil.wrapAngle(angles.yaw + player.recoilOffset.yaw)
        return angles.forward
    }
}
