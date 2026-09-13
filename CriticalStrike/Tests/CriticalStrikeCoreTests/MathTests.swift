import XCTest
@testable import CriticalStrikeCore

final class MathTests: XCTestCase {
    func testVectorNormalizationHandlesZero() {
        XCTAssertEqual(Vec3.zero.normalized, .zero)
        XCTAssertEqual(Vec3(3, 0, 4).normalized.length, 1, accuracy: 0.0001)
    }

    func testClipRemovesComponentIntoSurface() {
        let velocity = Vec3(1, 0, -1)
        let wallNormal = Vec3(0, 0, 1)
        let clipped = velocity.clipped(normal: wallNormal)
        XCTAssertEqual(clipped.z, 0, accuracy: 0.0001)
        XCTAssertEqual(clipped.x, 1, accuracy: 0.0001)
    }

    func testAngleWrapping() {
        XCTAssertEqual(MathUtil.wrapAngle(3 * .pi), .pi, accuracy: 0.0001)
        XCTAssertEqual(MathUtil.wrapAngle(-3 * .pi), .pi, accuracy: 0.0001)
        XCTAssertEqual(MathUtil.angleDelta(3.0, -3.0), 0.2831853, accuracy: 0.001)
    }

    func testViewAnglesForwardIsUnitAndConsistent() {
        for pitch in stride(from: Float(-1.5), through: 1.5, by: 0.3) {
            for yaw in stride(from: Float(-3), through: 3, by: 0.5) {
                let angles = ViewAngles(pitch: pitch, yaw: yaw)
                XCTAssertEqual(angles.forward.length, 1, accuracy: 0.001)
                XCTAssertEqual(angles.right.length, 1, accuracy: 0.001)
                // Forward and right must stay perpendicular in the horizontal plane.
                XCTAssertEqual(angles.groundForward.dot(angles.right), 0, accuracy: 0.001)
            }
        }
    }

    func testLookingAtProducesAnglesThatPointBack() {
        let from = Vec3(0, 1.6, 0)
        let to = Vec3(10, 3, -6)
        let angles = ViewAngles.looking(from: from, at: to)
        let expected = (to - from).normalized
        let actual = angles.forward
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.01)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.01)
        XCTAssertEqual(actual.z, expected.z, accuracy: 0.01)
    }

    func testAABBRaycastHitsAndMisses() {
        let box = AABB(center: Vec3(0, 0, -10), size: Vec3(2, 2, 2))
        let hit = box.raycast(Ray(origin: .zero, direction: Vec3(0, 0, -1)), maxDistance: 100)
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit!.t, 9, accuracy: 0.01)
        XCTAssertEqual(hit!.normal.z, 1, accuracy: 0.01)

        let miss = box.raycast(Ray(origin: .zero, direction: Vec3(1, 0, 0)), maxDistance: 100)
        XCTAssertNil(miss)
    }

    func testDeterministicRandomIsReproducible() {
        var a = DeterministicRandom(seed: 12345)
        var b = DeterministicRandom(seed: 12345)
        for _ in 0..<1000 {
            XCTAssertEqual(a.unit(), b.unit())
        }
    }

    func testDeterministicRandomStaysInRange() {
        var rng = DeterministicRandom(seed: 99)
        for _ in 0..<10_000 {
            let value = rng.unit()
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThan(value, 1)
            let integer = rng.int(in: 3...7)
            XCTAssertTrue((3...7).contains(integer))
        }
    }

    func testUnitDiskSamplesStayInsideTheDisk() {
        var rng = DeterministicRandom(seed: 7)
        for _ in 0..<5000 {
            let (x, y) = rng.insideUnitDisk()
            XCTAssertLessThanOrEqual(x * x + y * y, 1.0001)
        }
    }

    func testDampIsFrameRateIndependent() {
        // Damping over one 0.1s step should land close to ten 0.01s steps.
        let single = MathUtil.damp(0, 100, halfLife: 0.1, dt: 0.1)
        var stepped: Float = 0
        for _ in 0..<10 { stepped = MathUtil.damp(stepped, 100, halfLife: 0.1, dt: 0.01) }
        XCTAssertEqual(single, stepped, accuracy: 1.0)
    }

    func testTimerFiresExactlyOnce() {
        var timer = Timer()
        timer.start(0.1)
        XCTAssertFalse(timer.tick(0.05))
        XCTAssertTrue(timer.tick(0.06))
        XCTAssertFalse(timer.tick(0.06))
        XCTAssertTrue(timer.isFinished)
    }

    func testGameClockAccumulatesFixedSteps() {
        var clock = GameClock()
        let steps = clock.advance(deltaTime: GameClock.tickInterval * 3.5)
        XCTAssertEqual(steps, 3)
        XCTAssertGreaterThan(clock.interpolationAlpha, 0)
        XCTAssertLessThan(clock.interpolationAlpha, 1)
    }

    func testGameClockClampsCatchUp() {
        var clock = GameClock()
        // A five second stall must not produce 320 simulation steps.
        let steps = clock.advance(deltaTime: 5)
        XCTAssertLessThanOrEqual(steps, GameClock.maxCatchUpTicks)
    }
}

final class NoiseTests: XCTestCase {
    /// Every noise function must be seamless: sampling just inside one edge of the unit
    /// tile has to match the opposite edge, or the whole level shows a grid of seams.
    func testValueNoiseTiles() {
        let period = 8
        for step in 0..<64 {
            let t = Float(step) / 64 * Float(period)
            XCTAssertEqual(Noise.value(0, t, period: period, seed: 7),
                           Noise.value(Float(period), t, period: period, seed: 7),
                           accuracy: 0.0001, "value noise does not wrap in x")
            XCTAssertEqual(Noise.value(t, 0, period: period, seed: 7),
                           Noise.value(t, Float(period), period: period, seed: 7),
                           accuracy: 0.0001, "value noise does not wrap in y")
        }
    }

    func testGradientNoiseTiles() {
        let period = 6
        for step in 0..<64 {
            let t = Float(step) / 64 * Float(period)
            XCTAssertEqual(Noise.gradient(0, t, period: period, seed: 3),
                           Noise.gradient(Float(period), t, period: period, seed: 3),
                           accuracy: 0.0001)
            XCTAssertEqual(Noise.gradient(t, 0, period: period, seed: 3),
                           Noise.gradient(t, Float(period), period: period, seed: 3),
                           accuracy: 0.0001)
        }
    }

    func testFractalNoiseTiles() {
        let period = 4
        for step in 0..<48 {
            let t = Float(step) / 48 * Float(period)
            XCTAssertEqual(Noise.fbm(0, t, period: period, octaves: 5, seed: 11),
                           Noise.fbm(Float(period), t, period: period, octaves: 5, seed: 11),
                           accuracy: 0.0005, "fbm does not wrap — check octave period scaling")
            XCTAssertEqual(Noise.ridged(t, 0, period: period, octaves: 4, seed: 11),
                           Noise.ridged(t, Float(period), period: period, octaves: 4, seed: 11),
                           accuracy: 0.0005)
        }
    }

    func testCellularNoiseTiles() {
        let period = 10
        for step in 0..<48 {
            let t = Float(step) / 48 * Float(period)
            let left = Noise.cellular(0, t, period: period, seed: 5)
            let right = Noise.cellular(Float(period), t, period: period, seed: 5)
            XCTAssertEqual(left.nearest, right.nearest, accuracy: 0.0005)
            XCTAssertEqual(left.cellValue, right.cellValue, accuracy: 0.0001)
        }
    }

    func testDomainWarpTiles() {
        let period = 5
        for step in 0..<32 {
            let t = Float(step) / 32 * Float(period)
            let left = Noise.warp(0, t, period: period, strength: 1.5, seed: 9)
            let right = Noise.warp(Float(period), t, period: period, strength: 1.5, seed: 9)
            // The warp offset must match; the coordinate itself differs by the period.
            XCTAssertEqual(left.x, right.x - Float(period), accuracy: 0.0005)
            XCTAssertEqual(left.y, right.y, accuracy: 0.0005)
        }
    }

    func testWaveTilesForAnyIntegerCycleCount() {
        let period = 4
        for cyclesX in 1...6 {
            for cyclesY in 0...6 {
                for step in 0..<24 {
                    let t = Float(step) / 24 * Float(period)
                    XCTAssertEqual(
                        Noise.wave(0, t, period: period, cyclesX: cyclesX, cyclesY: cyclesY),
                        Noise.wave(Float(period), t, period: period,
                                   cyclesX: cyclesX, cyclesY: cyclesY),
                        accuracy: 0.0005, "wave \(cyclesX)x\(cyclesY) does not wrap")
                }
            }
        }
    }

    func testNoiseStaysInUnitRange() {
        var minimum: Float = 1
        var maximum: Float = 0
        for step in 0..<4000 {
            let x = Float(step % 64) * 0.37
            let y = Float(step / 64) * 0.53
            for sample in [Noise.value(x, y, period: 16, seed: 1),
                           Noise.gradient(x, y, period: 16, seed: 1),
                           Noise.fbm(x, y, period: 16, seed: 1),
                           Noise.ridged(x, y, period: 16, seed: 1),
                           Noise.wave(x, y, period: 16, cyclesX: 2, cyclesY: 3)] {
                minimum = Swift.min(minimum, sample)
                maximum = Swift.max(maximum, sample)
            }
        }
        XCTAssertGreaterThanOrEqual(minimum, 0)
        XCTAssertLessThanOrEqual(maximum, 1)
    }

    func testNoiseIsDeterministic() {
        for step in 0..<200 {
            let x = Float(step) * 0.13
            XCTAssertEqual(Noise.fbm(x, x * 0.7, period: 8, seed: 42),
                           Noise.fbm(x, x * 0.7, period: 8, seed: 42))
        }
    }

    func testDifferentSeedsProduceDifferentFields() {
        var differences = 0
        for step in 0..<200 {
            let x = Float(step) * 0.21
            if abs(Noise.fbm(x, 1.3, period: 8, seed: 1)
                   - Noise.fbm(x, 1.3, period: 8, seed: 2)) > 0.01 {
                differences += 1
            }
        }
        XCTAssertGreaterThan(differences, 150, "seeding barely changes the field")
    }
}
