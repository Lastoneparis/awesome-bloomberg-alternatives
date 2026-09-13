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
        // +pi and -pi are the same angle, and which side of the boundary 3*pi lands on
        // after a float remainder is not a property worth asserting — it flipped to -pi on
        // the CI machine and the test failed on a difference of one ulp. What matters is
        // that the result is in range and still points the same way.
        for input in [3 * Float.pi, -3 * Float.pi, .pi, -.pi, 7.3, -7.3, 0, 0.5] {
            let wrapped = MathUtil.wrapAngle(input)
            XCTAssertLessThanOrEqual(abs(wrapped), Float.pi + 1e-5,
                                     "\(input) wrapped to \(wrapped), outside the range")
            XCTAssertLessThan(abs(MathUtil.angleDelta(input, wrapped)), 1e-4,
                              "\(input) wrapped to \(wrapped), which is a different angle")
        }
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
        var timer = Countdown()
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

/// `ScalarField` is the substrate every procedural texture is built on, so a bug here
/// shows up as a seam or a mismatched normal map on every surface at once. The wrapping
/// behaviour is the part worth pinning down: it is what makes the derived maps tileable.
final class ScalarFieldTests: XCTestCase {
    private func ramp(width: Int = 8, height: Int = 8) -> ScalarField {
        ScalarField(width: width, height: height) { x, y in x + y }
    }

    func testGeneratorSamplesNormalizedCoordinates() {
        let field = ScalarField(width: 4, height: 2) { x, y in x * 10 + y }
        // x runs 0, 0.25, 0.5, 0.75 across the row; y is 0 on the first row, 0.5 on the second.
        XCTAssertEqual(field[0, 0], 0, accuracy: 1e-6)
        XCTAssertEqual(field[3, 0], 7.5, accuracy: 1e-6)
        XCTAssertEqual(field[0, 1], 0.5, accuracy: 1e-6)
        XCTAssertEqual(field[3, 1], 8, accuracy: 1e-6)
    }

    func testSubscriptWrapsPastBothEdges() {
        var field = ScalarField(width: 4, height: 3)
        field[0, 0] = 1
        field[3, 2] = 2

        XCTAssertEqual(field[4, 3], 1, "one tile to the right and down should land back on the origin")
        XCTAssertEqual(field[-4, -3], 1)
        XCTAssertEqual(field[-1, -1], 2, "stepping off the top-left must arrive at the bottom-right")
        XCTAssertEqual(field[7, 5], 2)
    }

    func testSubscriptSetterWraps() {
        var field = ScalarField(width: 4, height: 4)
        field[-1, -1] = 5
        XCTAssertEqual(field[3, 3], 5)
        field[8, 8] = 9
        XCTAssertEqual(field[0, 0], 9)
    }

    func testNormalizedFillsTheUnitRange() {
        let normalized = ramp().normalized()
        let (lo, hi) = normalized.range
        XCTAssertEqual(lo, 0, accuracy: 1e-6)
        XCTAssertEqual(hi, 1, accuracy: 1e-6)
        for value in normalized.values {
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 1)
        }
    }

    func testNormalizedLeavesAFlatFieldAlone() {
        // Dividing by a zero range would produce NaN and take every derived map with it.
        let flat = ScalarField(width: 4, height: 4, repeating: 0.3)
        XCTAssertEqual(flat.normalized().values, flat.values)
    }

    func testNormalizedPreservesOrdering() {
        let field = ramp()
        let normalized = field.normalized()
        for index in field.values.indices.dropFirst() {
            let before = field.values[index] - field.values[index - 1]
            let after = normalized.values[index] - normalized.values[index - 1]
            XCTAssertEqual(before.sign, after.sign)
        }
    }

    func testMappedAndCombined() {
        let field = ScalarField(width: 3, height: 3, repeating: 2)
        XCTAssertEqual(field.mapped { $0 * 3 }.values, [Float](repeating: 6, count: 9))
        let other = ScalarField(width: 3, height: 3, repeating: 5)
        XCTAssertEqual(field.combined(with: other, +).values, [Float](repeating: 7, count: 9))
    }

    func testBlurLeavesAFlatFieldFlat() {
        let flat = ScalarField(width: 8, height: 8, repeating: 0.42)
        for value in flat.blurred(radius: 3).values {
            XCTAssertEqual(value, 0.42, accuracy: 1e-5)
        }
    }

    func testBlurPreservesTotalEnergy() {
        // A box blur is a weighted average, so the mean must survive it. If it does not,
        // the wrapping is dropping or double counting samples at the edges.
        var field = ScalarField(width: 16, height: 16)
        var rng = DeterministicRandom(seed: 7)
        for index in field.values.indices { field.values[index] = rng.unit() }
        let before = field.values.reduce(0, +)
        let after = field.blurred(radius: 2).values.reduce(0, +)
        XCTAssertEqual(before, after, accuracy: before * 1e-3)
    }

    func testBlurBleedsAcrossTheSeam() {
        // An impulse on the left edge must brighten the right edge, or every blurred mask
        // in the game would show a dark line where the tile repeats.
        var field = ScalarField(width: 16, height: 16)
        field[0, 8] = 1
        let blurred = field.blurred(radius: 2)
        XCTAssertGreaterThan(blurred[15, 8], 0, "blur did not wrap horizontally")
        XCTAssertGreaterThan(blurred[14, 8], 0)

        var vertical = ScalarField(width: 16, height: 16)
        vertical[8, 0] = 1
        XCTAssertGreaterThan(vertical.blurred(radius: 2)[8, 15], 0, "blur did not wrap vertically")
    }

    func testBlurIsSymmetricAroundAnImpulse() {
        var field = ScalarField(width: 16, height: 16)
        field[8, 8] = 1
        let blurred = field.blurred(radius: 3)
        for offset in 1...3 {
            XCTAssertEqual(blurred[8 - offset, 8], blurred[8 + offset, 8], accuracy: 1e-6)
            XCTAssertEqual(blurred[8, 8 - offset], blurred[8, 8 + offset], accuracy: 1e-6)
        }
    }

    func testZeroRadiusBlurIsIdentity() {
        let field = ramp()
        XCTAssertEqual(field.blurred(radius: 0).values, field.values)
    }

    func testAmbientOcclusionLightsAFlatSurfaceFully() {
        let flat = ScalarField(width: 16, height: 16, repeating: 0.5)
        for value in flat.ambientOcclusion(radius: 3).values {
            XCTAssertEqual(value, 1, accuracy: 1e-4)
        }
    }

    func testAmbientOcclusionDarkensPitsAndSparesPeaks() {
        var field = ScalarField(width: 32, height: 32, repeating: 0.5)
        field[8, 8] = 0      // a pit
        field[24, 24] = 1    // a peak
        let occlusion = field.ambientOcclusion(radius: 3, strength: 1)
        XCTAssertLessThan(occlusion[8, 8], 0.9, "the pit should be occluded")
        XCTAssertEqual(occlusion[24, 24], 1, accuracy: 1e-4, "the peak should stay fully lit")
        XCTAssertGreaterThan(occlusion[16, 16], occlusion[8, 8])
    }

    func testAmbientOcclusionStaysInTheUnitRange() {
        var rng = DeterministicRandom(seed: 11)
        var field = ScalarField(width: 24, height: 24)
        for index in field.values.indices { field.values[index] = rng.signedUnit() * 2 }
        for value in field.ambientOcclusion(radius: 2, strength: 3).values {
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 1)
        }
    }

    func testCurvatureIsNeutralOnAFlatField() {
        let flat = ScalarField(width: 16, height: 16, repeating: 0.7)
        for value in flat.curvature(radius: 2).values {
            XCTAssertEqual(value, 0.5, accuracy: 1e-4)
        }
    }

    func testCurvatureSeparatesConvexFromConcave() {
        var field = ScalarField(width: 32, height: 32, repeating: 0.5)
        field[8, 8] = 1     // convex — this is where paint wears off
        field[24, 24] = 0   // concave
        let curvature = field.curvature(radius: 2)
        XCTAssertGreaterThan(curvature[8, 8], 0.5)
        XCTAssertLessThan(curvature[24, 24], 0.5)
    }

    func testFilteringCommutesWithTranslation() {
        // The real claim behind the wrapping sampler: the field is a torus, so filtering it
        // and then rolling it must give the same answer as rolling it and then filtering.
        // Anything that clamps or mirrors at the edges breaks this, and the break shows up
        // in game as a seam line down every tiled surface.
        let size = 24
        let source = ScalarField(width: size, height: size) { x, y in
            Noise.fbm(x * Float(size), y * Float(size), period: size, octaves: 3, seed: 5)
        }
        var rolled = ScalarField(width: size, height: size)
        let shiftX = 7, shiftY = 13
        for y in 0..<size {
            for x in 0..<size { rolled[x + shiftX, y + shiftY] = source[x, y] }
        }

        let filters: [(String, (ScalarField) -> ScalarField)] = [
            ("blur", { $0.blurred(radius: 3) }),
            ("ambient occlusion", { $0.ambientOcclusion(radius: 3) }),
            ("curvature", { $0.curvature(radius: 2) }),
        ]
        for (name, filter) in filters {
            let filteredThenRolled = filter(source)
            let rolledThenFiltered = filter(rolled)
            for y in 0..<size {
                for x in 0..<size {
                    XCTAssertEqual(rolledThenFiltered[x + shiftX, y + shiftY],
                                   filteredThenRolled[x, y],
                                   accuracy: 1e-5,
                                   "\(name) is not translation invariant at \(x),\(y)")
                }
            }
        }
    }
}

final class RGBTests: XCTestCase {
    func testHexInitialiser() {
        let orange = RGB(hex: 0xFF7A18)
        XCTAssertEqual(orange.r, 1, accuracy: 1e-6)
        XCTAssertEqual(orange.g, Float(0x7A) / 255, accuracy: 1e-6)
        XCTAssertEqual(orange.b, Float(0x18) / 255, accuracy: 1e-6)
        XCTAssertEqual(RGB(hex: 0xFFFFFF).r, RGB.white.r)
        XCTAssertEqual(RGB(hex: 0x000000).b, RGB.black.b)
    }

    func testLerpClampsOutsideTheUnitInterval() {
        let a = RGB(0, 0, 0)
        let b = RGB(1, 0.5, 0.25)
        XCTAssertEqual(a.lerp(b, 0.5).g, 0.25, accuracy: 1e-6)
        XCTAssertEqual(a.lerp(b, -3).r, 0, accuracy: 1e-6)
        XCTAssertEqual(a.lerp(b, 9).r, 1, accuracy: 1e-6)
    }

    func testArithmetic() {
        let sum = RGB(0.1, 0.2, 0.3) + RGB(0.4, 0.4, 0.4)
        XCTAssertEqual(sum.r, 0.5, accuracy: 1e-6)
        let scaled = RGB(0.2, 0.4, 0.6) * 2
        XCTAssertEqual(scaled.b, 1.2, accuracy: 1e-6)
        let modulated = RGB(0.5, 0.5, 0.5) * RGB(0.5, 1, 0)
        XCTAssertEqual(modulated.r, 0.25, accuracy: 1e-6)
        XCTAssertEqual(modulated.b, 0, accuracy: 1e-6)
        XCTAssertEqual(RGB(0.4, 0.4, 0.4).scaled(0.5).g, 0.2, accuracy: 1e-6)
    }
}
