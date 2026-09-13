import XCTest
@testable import CriticalStrikeCore

final class DamageModelTests: XCTestCase {
    private let rifle = WeaponDatabase.weaponOrDefault("ar_vanguard")

    func testPointBlankChestDamageMatchesBase() {
        let result = DamageModel.resolve(base: rifle.baseDamage, distance: 0, weapon: rifle,
                                         hitbox: .chest, armor: 0, penetratedSurfaces: 0)
        XCTAssertEqual(result.health, rifle.baseDamage, accuracy: 0.01)
        XCTAssertEqual(result.armor, 0, accuracy: 0.01)
    }

    func testHeadshotAppliesWeaponMultiplier() {
        let body = DamageModel.resolve(base: rifle.baseDamage, distance: 0, weapon: rifle,
                                       hitbox: .chest, armor: 0, penetratedSurfaces: 0)
        let head = DamageModel.resolve(base: rifle.baseDamage, distance: 0, weapon: rifle,
                                       hitbox: .head, armor: 0, penetratedSurfaces: 0)
        XCTAssertEqual(head.total / body.total, rifle.headshotMultiplier, accuracy: 0.01)
    }

    func testFalloffIsFlatThenLinearThenFlat() {
        XCTAssertEqual(DamageModel.falloffScale(distance: 0, weapon: rifle), 1, accuracy: 0.001)
        XCTAssertEqual(DamageModel.falloffScale(distance: rifle.falloffStart, weapon: rifle), 1,
                       accuracy: 0.001)
        let mid = DamageModel.falloffScale(distance: (rifle.falloffStart + rifle.falloffEnd) / 2,
                                           weapon: rifle)
        XCTAssertEqual(mid, (1 + rifle.falloffMinScale) / 2, accuracy: 0.01)
        XCTAssertEqual(DamageModel.falloffScale(distance: 10_000, weapon: rifle),
                       rifle.falloffMinScale, accuracy: 0.001)
    }

    func testArmorReducesHealthDamageAndIsConsumed() {
        let unarmored = DamageModel.resolve(base: rifle.baseDamage, distance: 0, weapon: rifle,
                                            hitbox: .chest, armor: 0, penetratedSurfaces: 0)
        let armored = DamageModel.resolve(base: rifle.baseDamage, distance: 0, weapon: rifle,
                                          hitbox: .chest, armor: 100, penetratedSurfaces: 0)
        XCTAssertLessThan(armored.health, unarmored.health)
        XCTAssertGreaterThan(armored.armor, 0)
        // Total dealt should never exceed the unarmored figure.
        XCTAssertLessThanOrEqual(armored.total, unarmored.total + 0.001)
    }

    func testArmorDoesNotProtectLimbs() {
        let leg = DamageModel.resolve(base: rifle.baseDamage, distance: 0, weapon: rifle,
                                      hitbox: .leg, armor: 100, penetratedSurfaces: 0)
        XCTAssertEqual(leg.armor, 0, accuracy: 0.001)
    }

    func testArmorOverflowLeaksToHealth() {
        // One point of armor cannot absorb a full rifle round.
        let nearlyGone = DamageModel.resolve(base: rifle.baseDamage, distance: 0, weapon: rifle,
                                             hitbox: .chest, armor: 1, penetratedSurfaces: 0)
        let plenty = DamageModel.resolve(base: rifle.baseDamage, distance: 0, weapon: rifle,
                                         hitbox: .chest, armor: 100, penetratedSurfaces: 0)
        XCTAssertGreaterThan(nearlyGone.health, plenty.health)
        XCTAssertLessThanOrEqual(nearlyGone.armor, 1.001)
    }

    func testPenetrationReducesDamageGeometrically() {
        let clean = DamageModel.resolve(base: rifle.baseDamage, distance: 0, weapon: rifle,
                                        hitbox: .chest, armor: 0, penetratedSurfaces: 0)
        let once = DamageModel.resolve(base: rifle.baseDamage, distance: 0, weapon: rifle,
                                       hitbox: .chest, armor: 0, penetratedSurfaces: 1)
        let twice = DamageModel.resolve(base: rifle.baseDamage, distance: 0, weapon: rifle,
                                        hitbox: .chest, armor: 0, penetratedSurfaces: 2)
        XCTAssertEqual(once.health / clean.health, rifle.penetrationDamageScale, accuracy: 0.01)
        XCTAssertEqual(twice.health / clean.health,
                       rifle.penetrationDamageScale * rifle.penetrationDamageScale, accuracy: 0.01)
    }

    func testExplosionFalloffReachesZeroAtOuterRadius() {
        XCTAssertEqual(DamageModel.explosion(damage: 100, innerRadius: 2, outerRadius: 8,
                                             distance: 8, occluded: false), 0, accuracy: 0.01)
        XCTAssertEqual(DamageModel.explosion(damage: 100, innerRadius: 2, outerRadius: 8,
                                             distance: 0, occluded: false), 100, accuracy: 0.01)
        XCTAssertEqual(DamageModel.explosion(damage: 100, innerRadius: 2, outerRadius: 8,
                                             distance: 20, occluded: false), 0, accuracy: 0.01)
    }

    func testOcclusionCutsExplosionDamage() {
        let open = DamageModel.explosion(damage: 100, innerRadius: 1, outerRadius: 8,
                                         distance: 4, occluded: false)
        let behindCover = DamageModel.explosion(damage: 100, innerRadius: 1, outerRadius: 8,
                                                distance: 4, occluded: true)
        XCTAssertLessThan(behindCover, open)
    }

    func testFlashIsStrongerWhenFacingIt() {
        let eye = Vec3(0, 1.6, 0)
        let flash = Vec3(0, 1.6, -5)
        let facing = DamageModel.flashIntensity(eye: eye, viewForward: Vec3(0, 0, -1),
                                                flashPosition: flash, radius: 16,
                                                occluded: false, resistance: 0)
        let away = DamageModel.flashIntensity(eye: eye, viewForward: Vec3(0, 0, 1),
                                              flashPosition: flash, radius: 16,
                                              occluded: false, resistance: 0)
        XCTAssertGreaterThan(facing, away)
        XCTAssertGreaterThan(away, 0)
    }

    func testWallsBlockFlashesEntirely() {
        XCTAssertEqual(DamageModel.flashIntensity(eye: .zero, viewForward: Vec3(0, 0, -1),
                                                  flashPosition: Vec3(0, 0, -3), radius: 16,
                                                  occluded: true, resistance: 0), 0)
    }

    func testFallDamageOnlyAppliesAboveThreshold() {
        XCTAssertEqual(DamageModel.fallDamage(impactSpeed: 5), 0)
        XCTAssertGreaterThan(DamageModel.fallDamage(impactSpeed: 16), 0)
        XCTAssertLessThanOrEqual(DamageModel.fallDamage(impactSpeed: 100), 100)
    }
}

final class WeaponBalanceTests: XCTestCase {
    /// Guard rails on the roster: these are the invariants that keep the game fair.
    func testNoWeaponKillsFasterThanTheFloor() {
        for weapon in WeaponDatabase.all where weapon.weaponClass != .melee {
            let ttk = DamageModel.timeToKill(weapon: weapon, health: 100, armor: 0, distance: 0)
            XCTAssertGreaterThanOrEqual(ttk, 0, "\(weapon.name) has a negative TTK")
            XCTAssertLessThan(ttk, 3.0, "\(weapon.name) takes over 3s to kill at point blank")
        }
    }

    func testEveryWeaponHasSaneMagazineAndReserve() {
        for weapon in WeaponDatabase.all where weapon.weaponClass != .melee {
            XCTAssertGreaterThan(weapon.magazineSize, 0, "\(weapon.name) has no magazine")
            XCTAssertGreaterThan(weapon.reserveAmmo, 0, "\(weapon.name) has no reserve ammo")
            XCTAssertGreaterThan(weapon.roundsPerMinute, 0, "\(weapon.name) has no fire rate")
        }
    }

    func testSpreadIsAlwaysTighterWhenAiming() {
        for weapon in WeaponDatabase.all where weapon.weaponClass != .melee {
            XCTAssertLessThanOrEqual(weapon.adsSpread, weapon.baseSpread,
                                     "\(weapon.name) is less accurate while aiming")
        }
    }

    func testSnipersTradeMobilityForDamage() {
        for weapon in WeaponDatabase.weapons(of: .sniperRifle) {
            XCTAssertLessThan(weapon.movementSpeedScale, 1.0)
            XCTAssertGreaterThan(weapon.baseDamage, 60)
        }
    }

    func testAttachmentsAlwaysHaveADownside() {
        for attachment in AttachmentDatabase.all {
            let upsides = [attachment.damageScale > 1, attachment.rangeScale > 1,
                           attachment.fireRateScale > 1, attachment.magazineScale > 1,
                           attachment.reloadScale < 1, attachment.adsTimeScale < 1,
                           attachment.hipSpreadScale < 1, attachment.adsSpreadScale < 1,
                           attachment.recoilVerticalScale < 1, attachment.recoilHorizontalScale < 1,
                           attachment.moveSpeedScale > 1, attachment.penetrationScale > 1,
                           attachment.loudnessScale < 1].filter { $0 }.count
            let downsides = [attachment.damageScale < 1, attachment.rangeScale < 1,
                             attachment.fireRateScale < 1, attachment.magazineScale < 1,
                             attachment.reloadScale > 1, attachment.adsTimeScale > 1,
                             attachment.hipSpreadScale > 1, attachment.adsSpreadScale > 1,
                             attachment.recoilVerticalScale > 1, attachment.recoilHorizontalScale > 1,
                             attachment.moveSpeedScale < 1, attachment.penetrationScale < 1,
                             attachment.loudnessScale > 1].filter { $0 }.count
            XCTAssertGreaterThan(upsides, 0, "\(attachment.name) does nothing")
            XCTAssertGreaterThan(downsides, 0, "\(attachment.name) is strictly better")
        }
    }

    func testSprayPatternsStartCentred() {
        for weapon in WeaponDatabase.all where !weapon.sprayPattern.isEmpty {
            let first = weapon.sprayPattern[0]
            XCTAssertEqual(first.up, 0, accuracy: 0.0001, "\(weapon.name) first shot is offset")
            XCTAssertEqual(first.side, 0, accuracy: 0.0001, "\(weapon.name) first shot is offset")
        }
    }

    func testSprayPatternsClimbBeforeTheyWander() {
        // The first five shots of any pattern must trend upward, which is what makes a
        // pattern learnable rather than random.
        for weapon in WeaponDatabase.all where weapon.sprayPattern.count > 5 {
            for index in 1..<5 {
                XCTAssertGreaterThan(weapon.sprayPattern[index].up,
                                     weapon.sprayPattern[index - 1].up,
                                     "\(weapon.name) does not climb at shot \(index)")
            }
        }
    }
}
