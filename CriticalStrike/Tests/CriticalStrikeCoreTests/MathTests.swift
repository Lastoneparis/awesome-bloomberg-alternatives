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
