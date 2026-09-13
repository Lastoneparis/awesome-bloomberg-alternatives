import XCTest
@testable import CriticalStrikeCore

/// The synthesis has no ear on it, so these tests are the ear: they check the things that
/// are actually wrong when a recipe is wrong — silence, a filter blowing up, a NaN reaching
/// the audio unit, a sound ten times longer than it needs to be, a sniper that is brighter
/// than an SMG.
final class WaveformTests: XCTestCase {

    func testDurationFollowsSampleRate() {
        XCTAssertEqual(Waveform(seconds: 0.5).count, 22_050)
        XCTAssertEqual(Waveform(seconds: 0.5).duration, 0.5, accuracy: 1e-4)
        XCTAssertEqual(Waveform(sampleRate: 48_000, seconds: 1).count, 48_000)
    }

    func testMixGrowsTheBufferAndAddsAtTheOffset() {
        var base = Waveform(seconds: 0.1)
        let blip = Waveform(samples: [1, 1, 1])
        base.mix(blip, at: 0.05, gain: 0.5)
        let offset = Int(0.05 * Waveform.defaultSampleRate)
        XCTAssertEqual(base.samples[offset], 0.5, accuracy: 1e-6)
        XCTAssertEqual(base.samples[offset - 1], 0, accuracy: 1e-6)

        var short = Waveform(samples: [1, 1])
        short.mix(Waveform(samples: [2, 2, 2, 2]))
        XCTAssertEqual(short.count, 4, "mixing past the end must grow the buffer")
        XCTAssertEqual(short.samples, [3, 3, 2, 2])
    }

    func testNormalizedHitsTheTargetPeak() {
        let quiet = Waveform(samples: [0.01, -0.02, 0.015])
        XCTAssertEqual(quiet.normalized(to: 0.9).peak, 0.9, accuracy: 1e-5)
        // Silence has no peak to scale to, and dividing by it would produce infinities.
        let silent = Waveform(samples: [0, 0, 0])
        XCTAssertEqual(silent.normalized().samples, [0, 0, 0])
    }

    func testFadeRemovesTheEdgeDiscontinuity() {
        let square = Waveform(samples: [Float](repeating: 1, count: 4410))
        let faded = square.faded(inSeconds: 0.005, outSeconds: 0.005)
        XCTAssertEqual(faded.samples.first!, 0, accuracy: 1e-6)
        XCTAssertEqual(faded.samples.last!, 0, accuracy: 1e-6)
        XCTAssertEqual(faded.samples[2205], 1, accuracy: 1e-6, "the middle must be untouched")
    }

    func testTrimmedSilenceCutsTheTailButKeepsTheSound() {
        var buffer = Waveform(seconds: 2)
        for index in 0..<1000 { buffer.samples[index] = 0.5 }
        let trimmed = buffer.trimmedSilence(releaseSeconds: 0.05)
        XCTAssertLessThan(trimmed.duration, 0.1)
        XCTAssertGreaterThan(trimmed.duration, 1000 / Waveform.defaultSampleRate)
        XCTAssertEqual(trimmed.samples[500], 0.5, accuracy: 1e-6)
    }

    func testTrimmedSilenceLeavesAFullyQuietBufferAlone() {
        let silent = Waveform(seconds: 0.5)
        XCTAssertEqual(silent.trimmedSilence().count, silent.count)
    }

    func testLoopableJoinsHeadToTail() {
        // A bed that steps from -1 to +1 at the seam would click on every repeat.
        var buffer = Waveform(seconds: 1)
        for index in buffer.samples.indices {
            buffer.samples[index] = index < buffer.count / 2 ? -1 : 1
        }
        let looped = buffer.loopable(crossfadeSeconds: 0.2)
        let seamStep = abs(looped.samples[0] - looped.samples[looped.count - 1])
        let rawStep = abs(buffer.samples[0] - buffer.samples[buffer.count - 1])
        XCTAssertLessThan(seamStep, rawStep, "the crossfade did not close the seam")
        XCTAssertLessThan(looped.count, buffer.count)
    }

    func testResamplingPreservesDurationAndContent() {
        let source = Synth.tone(frequency: 440, seconds: 0.2)
        let resampled = source.resampled(to: 48_000)
        XCTAssertEqual(resampled.sampleRate, 48_000)
        XCTAssertEqual(resampled.duration, source.duration, accuracy: 0.002)
        // A 440 Hz sine is still a 440 Hz sine: same peak, and no DC offset introduced.
        XCTAssertEqual(resampled.peak, source.peak, accuracy: 0.02)
        let mean = resampled.samples.reduce(0, +) / Float(resampled.count)
        XCTAssertEqual(mean, 0, accuracy: 0.02)
    }

    func testResamplingToTheSameRateIsFree() {
        let source = Synth.tone(frequency: 440, seconds: 0.05)
        XCTAssertEqual(source.resampled(to: Waveform.defaultSampleRate).samples, source.samples)
    }

    func testSanitizedReplacesNonFiniteSamples() {
        let broken = Waveform(samples: [0.5, .nan, .infinity, -.infinity, 4])
        let clean = broken.sanitized()
        XCTAssertEqual(clean.samples, [0.5, 0, 0, 0, 1])
        for sample in clean.samples { XCTAssertTrue(sample.isFinite) }
    }
}

final class SynthTests: XCTestCase {

    /// Energy above and below a frequency, by counting zero crossings and by a crude
    /// band measurement — enough to tell a dull sound from a bright one.
    private func zeroCrossingRate(_ buffer: Waveform) -> Float {
        guard buffer.count > 1 else { return 0 }
        var crossings = 0
        for index in 1..<buffer.count where (buffer.samples[index] < 0) != (buffer.samples[index - 1] < 0) {
            crossings += 1
        }
        return Float(crossings) / buffer.duration
    }

    func testToneIsPeriodicAtTheRequestedFrequency() {
        let tone = Synth.tone(frequency: 1000, seconds: 0.5)
        // Two crossings per cycle.
        XCTAssertEqual(zeroCrossingRate(tone) / 2, 1000, accuracy: 20)
    }

    func testNoiseIsDeterministicAndCentred() {
        let a = Synth.noise(seconds: 0.1, seed: 99)
        let b = Synth.noise(seconds: 0.1, seed: 99)
        XCTAssertEqual(a.samples, b.samples)
        XCTAssertNotEqual(a.samples, Synth.noise(seconds: 0.1, seed: 100).samples)
        let mean = a.samples.reduce(0, +) / Float(a.count)
        XCTAssertEqual(mean, 0, accuracy: 0.05)
        XCTAssertGreaterThan(a.rms, 0.4)
    }

    func testLowPassRemovesHighFrequencies() {
        let noise = Synth.noise(seconds: 0.3, seed: 5)
        let filtered = Synth.filter(noise, mode: .lowPass, cutoff: 400)
        XCTAssertLessThan(zeroCrossingRate(filtered), zeroCrossingRate(noise) * 0.25)
        XCTAssertTrue(filtered.samples.allSatisfy { $0.isFinite })
    }

    func testHighPassRemovesLowFrequencies() {
        // A 60 Hz sine through a 2 kHz high pass should be almost entirely gone.
        let low = Synth.tone(frequency: 60, seconds: 0.3)
        let filtered = Synth.filter(low, mode: .highPass, cutoff: 2000)
        XCTAssertLessThan(filtered.rms, low.rms * 0.1)
    }

    func testFilterIsStableAtExtremeSettings() {
        // The cutoff and resonance are clamped precisely so a recipe cannot blow the
        // filter up; a self-oscillating SVF is full-scale static.
        let noise = Synth.noise(seconds: 0.2, seed: 3)
        for cutoff in [Float(1), 20, 8_000, 22_050, 100_000] {
            for resonance in [Float(0.01), 0.7, 10, 1_000] {
                for mode in [Synth.FilterMode.lowPass, .bandPass, .highPass] {
                    let filtered = Synth.filter(noise, mode: mode, cutoff: cutoff,
                                                resonance: resonance)
                    XCTAssertTrue(filtered.samples.allSatisfy { $0.isFinite },
                                  "cutoff \(cutoff) resonance \(resonance) produced a non-finite sample")
                    XCTAssertLessThan(filtered.peak, 50,
                                      "cutoff \(cutoff) resonance \(resonance) blew up")
                }
            }
        }
    }

    func testEnvelopeRisesThenFalls() {
        let flat = Waveform(samples: [Float](repeating: 1, count: 4410))
        let shaped = Synth.envelope(flat, attack: 0.01, hold: 0.01, decay: 0.05)
        XCTAssertEqual(shaped.samples[0], 0, accuracy: 1e-6)
        let attackEnd = Int(0.01 * Waveform.defaultSampleRate)
        XCTAssertEqual(shaped.samples[attackEnd + 100], 1, accuracy: 1e-6, "hold must be flat")
        XCTAssertLessThan(shaped.samples[shaped.count - 1], 0.05)
        XCTAssertLessThanOrEqual(shaped.peak, 1)
    }

    func testDecayHalvesAtTheHalfLife() {
        let flat = Waveform(samples: [Float](repeating: 1, count: 44_100))
        let decayed = Synth.decay(flat, halfLife: 0.1)
        XCTAssertEqual(decayed.samples[4410], 0.5, accuracy: 0.01)
        XCTAssertEqual(decayed.samples[8820], 0.25, accuracy: 0.01)
    }

    func testSaturationRaisesLevelWithoutClipping() {
        let quiet = Synth.tone(frequency: 300, seconds: 0.1).gained(0.3)
        let driven = Synth.saturate(quiet, drive: 4)
        XCTAssertGreaterThan(driven.rms, quiet.rms)
        XCTAssertLessThanOrEqual(driven.peak, 1.0001)
    }

    func testRoomKeepsTheDirectSoundLoudest() {
        // Four cascaded in-place delays used to pile reflections up until the loudest
        // moment of a gunshot was fifty milliseconds after the trigger.
        var impulse = Waveform(seconds: 0.05)
        impulse.samples[0] = 1
        let wet = Synth.room(impulse, size: 2, decay: 0.6, mix: 0.4)
        let peakIndex = wet.samples.indices.max { abs(wet.samples[$0]) < abs(wet.samples[$1]) }
        XCTAssertEqual(peakIndex, 0, "a reflection is louder than the direct sound")
        XCTAssertGreaterThan(wet.duration, impulse.duration, "the room needs somewhere to ring")
    }
}

/// Synthesis is a pure function with no cache — the app caches the results, the core does
/// not — so the tests memoise, or a music bed gets built from scratch in every assertion
/// that mentions it. In a debug build that is the difference between a fast suite and a
/// slow one.
private enum Bank {
    private static var cache: [String: Waveform?] = [:]

    static func sound(_ name: String) -> Waveform? {
        if let cached = cache[name] { return cached }
        let sound = SoundBank.sound(named: name)
        cache[name] = sound
        return sound
    }
}

final class SoundBankTests: XCTestCase {

    private func centroid(_ buffer: Waveform) -> Float {
        // Crude spectral centroid via zero-crossing rate: exact enough to order sounds
        // from dull to bright, which is all these assertions need.
        guard buffer.count > 1 else { return 0 }
        var crossings = 0
        for index in 1..<buffer.count where (buffer.samples[index] < 0) != (buffer.samples[index - 1] < 0) {
            crossings += 1
        }
        return Float(crossings) / buffer.duration / 2
    }

    func testEverySoundTheGameAsksForExists() {
        for name in SoundBank.fixedNames {
            XCTAssertNotNil(Bank.sound(name), "no recipe for \(name)")
        }
        for surface in SurfaceKind.allCases {
            XCTAssertNotNil(Bank.sound(surface.footstepSound), surface.footstepSound)
            XCTAssertNotNil(Bank.sound(surface.impactSound), surface.impactSound)
        }
        for weapon in WeaponDatabase.all {
            XCTAssertNotNil(Bank.sound(weapon.fireSound), weapon.fireSound)
            XCTAssertNotNil(Bank.sound(weapon.reloadSound), weapon.reloadSound)
        }
        for name in ["mus_menu", "mus_victory", "mus_defeat", "amb_wind", "amb_desert_wind",
                     "amb_industrial", "amb_hum", "amb_city_night", "amb_blizzard"] {
            XCTAssertNotNil(Bank.sound(name), name)
        }
    }

    func testUnknownNamesReturnNilRatherThanSilence() {
        XCTAssertNil(SoundBank.sound(named: "sfx_not_a_real_sound"))
        XCTAssertNil(SoundBank.sound(named: "sfx_no_such_weapon_fire"))
        XCTAssertNil(SoundBank.sound(named: ""))
    }

    func testEverySoundIsAudibleFiniteAndInRange() {
        var names = SoundBank.fixedNames
        names += SurfaceKind.allCases.map(\.footstepSound)
        names += WeaponDatabase.all.map(\.fireSound)
        names += ["mus_menu", "mus_victory", "amb_desert_wind"]

        for name in names {
            guard let sound = Bank.sound(name) else {
                XCTFail("no recipe for \(name)")
                continue
            }
            XCTAssertTrue(sound.samples.allSatisfy { $0.isFinite }, "\(name) has a non-finite sample")
            XCTAssertLessThanOrEqual(sound.peak, 1.0001, "\(name) clips")
            XCTAssertGreaterThan(sound.rms, 0.005, "\(name) is effectively silent")
            XCTAssertGreaterThan(sound.duration, 0.01, "\(name) is too short to hear")
            XCTAssertLessThan(sound.duration, 25, "\(name) is far longer than any sound needs")
        }
    }

    func testSynthesisIsDeterministic() {
        // Determinism is what lets the same sound be reused across a session and compared
        // across devices — and it is the only reason these assertions mean anything.
        for name in ["sfx_explosion", "sfx_step_metal", "amb_blizzard"] {
            XCTAssertEqual(SoundBank.sound(named: name)?.samples,
                           SoundBank.sound(named: name)?.samples, name)
        }
    }

    func testGunshotsAreShortEnoughToBeGunshots() {
        // A generously padded room simulation once rang into eleven seconds of buffer to
        // produce about one second of audible tail, at 44.1 kHz, per weapon.
        for weapon in WeaponDatabase.all where weapon.weaponClass != .melee {
            guard let shot = Bank.sound(weapon.fireSound) else { continue }
            XCTAssertLessThan(shot.duration, 1.5, "\(weapon.id.value) rings for \(shot.duration)s")
            XCTAssertGreaterThan(shot.duration, 0.1, "\(weapon.id.value) is too short")
        }
    }

    func testGunshotAttackIsImmediate() {
        // The loudest moment of a gunshot is the gunshot. Anything else is a swell.
        for weapon in WeaponDatabase.all where weapon.weaponClass != .melee {
            guard let shot = Bank.sound(weapon.fireSound), shot.count > 0 else { continue }
            let peakIndex = shot.samples.indices.max {
                abs(shot.samples[$0]) < abs(shot.samples[$1])
            } ?? 0
            let peakTime = Float(peakIndex) / shot.sampleRate
            XCTAssertLessThan(peakTime, 0.03,
                              "\(weapon.id.value) peaks \(peakTime * 1000)ms in")
        }
    }

    func testBiggerRoundsSoundLowerThanSmallerOnes() {
        // The whole point of deriving the report from the weapon data: rebalancing a
        // weapon has to rebalance how it sounds.
        let heavy = WeaponData(id: "test_heavy", name: "Heavy", weaponClass: .sniperRifle,
                               fireMode: .bolt, ammoType: .sniper,
                               baseDamage: 100, falloffStart: 90, falloffEnd: 160,
                               roundsPerMinute: 45,
                               magazineSize: 5, reserveAmmo: 20, reloadTime: 3)
        let light = WeaponData(id: "test_light", name: "Light", weaponClass: .submachineGun,
                               fireMode: .auto, ammoType: .light,
                               baseDamage: 22, falloffStart: 12, falloffEnd: 30,
                               roundsPerMinute: 900,
                               magazineSize: 30, reserveAmmo: 120, reloadTime: 1.8)
        XCTAssertLessThan(centroid(SoundBank.gunshot(for: heavy)),
                          centroid(SoundBank.gunshot(for: light)),
                          "a sniper should be darker than an SMG")
    }

    func testHeadshotIsDistinctFromABodyHit() {
        let body = SoundBank.hitMarker(headshot: false)
        let head = SoundBank.hitMarker(headshot: true)
        XCTAssertGreaterThan(centroid(head), centroid(body), "a headshot must read brighter")
        XCTAssertGreaterThan(head.duration, body.duration, "a headshot must read longer")
    }

    func testLoopingBedsAreSeamless() {
        for name in ["amb_desert_wind", "amb_industrial", "amb_city_night", "mus_sandstorm"] {
            guard let bed = Bank.sound(name), bed.count > 2 else {
                XCTFail("no recipe for \(name)")
                continue
            }
            // The step across the loop point must not stand out against the material's
            // own sample-to-sample movement, or every repeat clicks.
            let seam = abs(bed.samples[0] - bed.samples[bed.count - 1])
            var typical: Float = 0
            for index in 1..<bed.count { typical += abs(bed.samples[index] - bed.samples[index - 1]) }
            typical /= Float(bed.count - 1)
            XCTAssertLessThan(seam, max(typical * 12, 0.02), "\(name) clicks at the loop point")
        }
    }

    func testBedsAreLongEnoughNotToBeObvious() {
        for name in ["amb_desert_wind", "amb_hum", "mus_menu"] {
            guard let bed = Bank.sound(name) else { continue }
            XCTAssertGreaterThan(bed.duration, 4, "\(name) repeats too quickly to hide")
        }
    }

    func testMusicStingsDoNotLoopForever() {
        // These are scheduled without .loops, so they have to end by themselves.
        for name in ["mus_victory", "mus_defeat"] {
            guard let sting = Bank.sound(name) else { continue }
            XCTAssertLessThan(sting.duration, 6, "\(name) is a sting, not a bed")
            XCTAssertGreaterThan(sting.duration, 0.5)
        }
    }

    func testKillstreakAnnouncementsRiseWithTheStreak() {
        var previous: Float = 0
        for step in 1...5 {
            guard let sound = Bank.sound("sfx_streak_\(step)") else {
                XCTFail("no sfx_streak_\(step)")
                continue
            }
            let pitch = centroid(sound)
            XCTAssertGreaterThan(pitch, previous, "streak \(step) is not higher than \(step - 1)")
            previous = pitch
        }
    }

    func testFootstepSurfacesAreDistinguishable() {
        // Footsteps carry more competitive information than anything else in the mix; if
        // two surfaces measure the same they sound the same.
        var centroids: [SurfaceKind: Float] = [:]
        for surface in SurfaceKind.allCases {
            centroids[surface] = centroid(SoundBank.footstep(surface: surface, seed: 1))
        }
        XCTAssertGreaterThan(centroids[.grass]!, centroids[.dirt]!,
                             "grass should be brighter than dirt")
        XCTAssertGreaterThan(centroids[.metal]!, centroids[.wood]!,
                             "metal should ring higher than wood")
        XCTAssertGreaterThan(centroids[.glass]!, centroids[.concrete]!)
    }

    func testSoundNamesHashStably() {
        XCTAssertEqual(SoundBank.hash("sfx_explosion"), SoundBank.hash("sfx_explosion"))
        XCTAssertNotEqual(SoundBank.hash("sfx_explosion"), SoundBank.hash("sfx_flash"))
    }
}
