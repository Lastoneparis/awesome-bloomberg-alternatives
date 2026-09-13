import Foundation

/// The synthesis primitives every sound in the game is built from.
///
/// Deliberately small: oscillators, noise, envelopes, a state-variable filter, saturation
/// and a delay. Almost all of a shooter's audio is a noise burst through a filter with a
/// fast envelope — what separates a rifle from a pistol from a footstep on gravel is the
/// filter, the envelope times and what is layered underneath, not exotic DSP.
public enum Synth {

    public enum Wave {
        case sine, triangle, sawtooth, square
    }

    // MARK: - Sources

    /// White noise from the deterministic generator, so a given sound is byte-identical
    /// every run — which is what lets the results be cached and tested.
    public static func noise(seconds: Float, seed: UInt64,
                             sampleRate: Float = Waveform.defaultSampleRate) -> Waveform {
        var buffer = Waveform(sampleRate: sampleRate, seconds: seconds)
        var random = DeterministicRandom(seed: seed)
        for index in buffer.samples.indices {
            buffer.samples[index] = random.signedUnit()
        }
        return buffer
    }

    public static func tone(frequency: Float, seconds: Float, wave: Wave = .sine,
                            phase: Float = 0,
                            sampleRate: Float = Waveform.defaultSampleRate) -> Waveform {
        sweep(from: frequency, to: frequency, seconds: seconds, wave: wave,
              phase: phase, sampleRate: sampleRate)
    }

    /// A frequency sweep. Almost every impact in the game has one underneath it: a pitch
    /// falling fast is what the ear reads as something large releasing energy.
    public static func sweep(from startFrequency: Float, to endFrequency: Float,
                             seconds: Float, wave: Wave = .sine, curve: Float = 2.5,
                             phase: Float = 0,
                             sampleRate: Float = Waveform.defaultSampleRate) -> Waveform {
        var buffer = Waveform(sampleRate: sampleRate, seconds: seconds)
        guard buffer.count > 0 else { return buffer }
        var accumulated = phase
        let inverseRate = 1 / sampleRate

        // A steady tone is the common case — the drones and pads under every music bed are
        // twenty seconds each — and it does not need the glide maths at all. Calling pow()
        // a million times to compute a constant is most of what a bed used to cost.
        if startFrequency == endFrequency {
            let step = startFrequency * inverseRate
            for index in buffer.samples.indices {
                accumulated += step
                buffer.samples[index] = sample(wave, phase: accumulated)
            }
            return buffer
        }

        let inverseCount = 1 / Float(buffer.count)
        for index in buffer.samples.indices {
            let t = Float(index) * inverseCount
            // Exponential glide, because pitch is perceived logarithmically; a linear
            // sweep spends most of its time at the top and sounds like a whistle.
            let blend = pow(1 - t, curve)
            let frequency = endFrequency + (startFrequency - endFrequency) * blend
            accumulated += frequency * inverseRate
            buffer.samples[index] = sample(wave, phase: accumulated)
        }
        return buffer
    }

    @inline(__always)
    private static func sample(_ wave: Wave, phase: Float) -> Float {
        let wrapped = phase - floor(phase)
        switch wave {
        case .sine:
            return sin(wrapped * 2 * .pi)
        case .triangle:
            return 4 * abs(wrapped - 0.5) - 1
        case .sawtooth:
            return wrapped * 2 - 1
        case .square:
            return wrapped < 0.5 ? 1 : -1
        }
    }

    // MARK: - Envelopes

    /// Attack–hold–decay with an exponential tail. `curve` above 1 makes the decay hug the
    /// axis, which is what a real transient does and what keeps a gunshot from sounding
    /// like a drum machine.
    public static func envelope(_ buffer: Waveform, attack: Float, hold: Float = 0,
                                decay: Float, curve: Float = 3) -> Waveform {
        var out = buffer
        let rate = buffer.sampleRate
        let attackSamples = Swift.max(1, Int(attack * rate))
        let holdSamples = Int(hold * rate)
        let decaySamples = Swift.max(1, Int(decay * rate))
        for index in out.samples.indices {
            let gain: Float
            if index < attackSamples {
                gain = Float(index) / Float(attackSamples)
            } else if index < attackSamples + holdSamples {
                gain = 1
            } else {
                let position = Float(index - attackSamples - holdSamples) / Float(decaySamples)
                gain = position >= 1 ? 0 : pow(1 - position, curve)
            }
            out.samples[index] *= gain
        }
        return out
    }

    /// A pure exponential decay, for tails that should never quite reach zero abruptly.
    public static func decay(_ buffer: Waveform, halfLife: Float) -> Waveform {
        var out = buffer
        guard halfLife > 0 else { return out }
        let perSample = pow(0.5, 1 / (halfLife * buffer.sampleRate))
        var gain: Float = 1
        for index in out.samples.indices {
            out.samples[index] *= gain
            gain *= perSample
        }
        return out
    }

    // MARK: - Filtering

    /// A topology-preserving-transform state-variable filter: low, band and high pass
    /// from one pass, and unconditionally stable at every cutoff and resonance.
    ///
    /// The obvious Chamberlin form is only *conditionally* stable — it needs
    /// `2·sin(π·fc/fs) < 2 − 1/Q` — and this file asks for cutoffs of 4.2 kHz on the music
    /// tick, 5.2 kHz on the smoke hiss and 3.8 kHz on impact grit. All of those are past
    /// the limit at ordinary resonance, and at 8 kHz the state diverges to infinity within
    /// a few hundred samples. Real game sounds were being made by a filter that was blowing
    /// up; `sanitized()` then quietly replaced the infinities with zeros.
    ///
    /// This form has no such condition. `g = tan(π·fc/fs)` prewarps the cutoff, and the
    /// integrators are solved together rather than being stepped one sample behind.
    public enum FilterMode { case lowPass, bandPass, highPass }

    /// Cutoff has to stay below Nyquist: `tan` goes to infinity there.
    private static let maxCutoffFraction: Float = 0.45

    public static func filter(_ buffer: Waveform, mode: FilterMode, cutoff: Float,
                              resonance: Float = 0.7) -> Waveform {
        var out = buffer
        let fc = MathUtil.clamp(cutoff, 10, buffer.sampleRate * maxCutoffFraction)
        let g = tan(.pi * fc / buffer.sampleRate)
        let k = 1 / MathUtil.clamp(resonance, 0.5, 10)
        let a1 = 1 / (1 + g * (g + k))
        let a2 = g * a1
        let a3 = g * a2

        var ic1 : Float = 0, ic2: Float = 0
        for index in out.samples.indices {
            let input = buffer.samples[index]
            let v3 = input - ic2
            let v1 = a1 * ic1 + a2 * v3
            let v2 = ic2 + a2 * ic1 + a3 * v3
            ic1 = 2 * v1 - ic1
            ic2 = 2 * v2 - ic2
            switch mode {
            case .lowPass: out.samples[index] = v2
            case .bandPass: out.samples[index] = v1
            case .highPass: out.samples[index] = input - k * v1 - v2
            }
        }
        return out
    }

    /// A filter whose cutoff moves across the buffer — a gunshot's tail dulls as it
    /// travels, and a static filter makes the whole thing sound like it is behind a door.
    public static func sweepingLowPass(_ buffer: Waveform, from startCutoff: Float,
                                       to endCutoff: Float, resonance: Float = 0.7) -> Waveform {
        var out = buffer
        guard buffer.count > 0 else { return out }
        let k = 1 / MathUtil.clamp(resonance, 0.5, 10)
        let nyquist = buffer.sampleRate * maxCutoffFraction
        let inverseCount = 1 / Float(buffer.count)
        var ic1: Float = 0, ic2: Float = 0

        for index in out.samples.indices {
            let t = Float(index) * inverseCount
            let fc = MathUtil.clamp(startCutoff + (endCutoff - startCutoff) * t, 10, nyquist)
            let g = tan(.pi * fc / buffer.sampleRate)
            let a1 = 1 / (1 + g * (g + k))
            let a2 = g * a1
            let a3 = g * a2

            let input = buffer.samples[index]
            let v3 = input - ic2
            let v1 = a1 * ic1 + a2 * v3
            let v2 = ic2 + a2 * ic1 + a3 * v3
            ic1 = 2 * v1 - ic1
            ic2 = 2 * v2 - ic2
            out.samples[index] = v2
        }
        return out
    }

    // MARK: - Shaping

    /// Soft saturation. A gunshot that is simply scaled up clips into buzz; driven through
    /// a tanh it gets louder and thicker instead, which is what a limiter on a real
    /// recording does.
    public static func saturate(_ buffer: Waveform, drive: Float = 3) -> Waveform {
        var out = buffer
        let normalise = tanh(drive)
        for index in out.samples.indices {
            out.samples[index] = tanh(out.samples[index] * drive) / normalise
        }
        return out
    }

    /// A feedback delay. Used as a stand-in for a room: three of these at prime-ish spacings
    /// read as reflections, which is all a gunshot tail needs.
    public static func delay(_ buffer: Waveform, seconds: Float, feedback: Float,
                             mix: Float, tailSeconds: Float = 0) -> Waveform {
        var out = buffer.padded(toSeconds: buffer.duration + tailSeconds)
        let step = Swift.max(1, Int(seconds * buffer.sampleRate))
        guard step < out.count else { return buffer }
        let clampedFeedback = MathUtil.clamp(feedback, 0, 0.95)
        for index in step..<out.count {
            out.samples[index] += out.samples[index - step] * clampedFeedback * mix
        }
        return out
    }

    /// A handful of comb filters at incommensurate spacings, which is a poor reverb and an
    /// excellent gunshot tail.
    ///
    /// Each line produces reflections only — it is fed by the dry signal and feeds back
    /// into itself, and the result is mixed under the dry rather than added into it. Run
    /// as four in-place passes instead, the delays compound: the reflections pile up until
    /// the loudest moment of a gunshot is fifty milliseconds after the trigger, which
    /// reads as a swell rather than a shot.
    ///
    /// The padding is the room to ring into. It is deliberately modest and the caller
    /// trims what is left: sized generously, a large room rings into ten seconds of buffer
    /// to produce one second of audible tail, and every one of those samples costs memory
    /// in the voice pool and time in the mixer.
    public static func room(_ buffer: Waveform, size: Float, decay: Float,
                            mix: Float = 0.4) -> Waveform {
        let total = buffer.duration + size * 1.2
        let dry = buffer.padded(toSeconds: total)
        var wet = Waveform(sampleRate: buffer.sampleRate, count: dry.count)
        let feedback = MathUtil.clamp(decay, 0, 0.92)
        let spacings: [Float] = [0.0297, 0.0371, 0.0411, 0.0437]

        for spacing in spacings {
            let step = Swift.max(1, Int(spacing * size * buffer.sampleRate))
            guard step < dry.count else { continue }
            var line = Waveform(sampleRate: buffer.sampleRate, count: dry.count)
            for index in step..<line.count {
                line.samples[index] = (dry.samples[index - step]
                                       + line.samples[index - step]) * feedback
            }
            wet.mix(line, gain: 1 / Float(spacings.count))
        }

        var out = dry
        out.mix(wet, gain: mix)
        return out
    }
}
