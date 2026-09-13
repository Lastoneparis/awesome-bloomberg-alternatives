import Foundation

/// A mono block of audio samples.
///
/// Named `Waveform` rather than `AudioBuffer` because CoreAudioTypes already has an
/// `AudioBuffer`, which AVFoundation pulls in — the app's bridge to `AVAudioPCMBuffer`
/// could not name the type at all. Same lesson as `Countdown`.
///
/// The game ships no sound files. Every gunshot, footstep, impact and ambience is
/// synthesised from these, for the same reasons the textures are: the download stays tiny,
/// a new weapon is a set of numbers rather than a recording session, and — the part that
/// matters most here — the parameters can be derived from the weapon data the simulation
/// already has, so a heavier round really does sound heavier.
///
/// Like `ScalarField`, this lives in the core with no AVFoundation anywhere near it, so
/// the synthesis can be tested without a device.
public struct Waveform {
    /// 44.1 kHz throughout. Anything less starts to matter on the transient of a gunshot,
    /// which is the one sound in the game the player hears thousands of times.
    public static let defaultSampleRate: Float = 44_100

    public let sampleRate: Float
    public var samples: [Float]

    public init(sampleRate: Float = Waveform.defaultSampleRate, count: Int) {
        self.sampleRate = sampleRate
        self.samples = [Float](repeating: 0, count: max(0, count))
    }

    public init(sampleRate: Float = Waveform.defaultSampleRate, seconds: Float) {
        self.init(sampleRate: sampleRate, count: Int(max(0, seconds) * sampleRate))
    }

    public init(sampleRate: Float = Waveform.defaultSampleRate, samples: [Float]) {
        self.sampleRate = sampleRate
        self.samples = samples
    }

    public var count: Int { samples.count }
    public var duration: Float { Float(samples.count) / sampleRate }
    public var isEmpty: Bool { samples.isEmpty }

    public var peak: Float {
        var highest: Float = 0
        for sample in samples { highest = Swift.max(highest, abs(sample)) }
        return highest
    }

    public var rms: Float {
        guard !samples.isEmpty else { return 0 }
        var total: Float = 0
        for sample in samples { total += sample * sample }
        return (total / Float(samples.count)).squareRoot()
    }

    /// Mixes another buffer in at an offset, growing this one if it needs to.
    public mutating func mix(_ other: Waveform, at seconds: Float = 0, gain: Float = 1) {
        let offset = Int(max(0, seconds) * sampleRate)
        let needed = offset + other.count
        if needed > samples.count {
            samples.append(contentsOf: [Float](repeating: 0, count: needed - samples.count))
        }
        for index in 0..<other.count {
            samples[offset + index] += other.samples[index] * gain
        }
    }

    public func mixed(_ other: Waveform, at seconds: Float = 0, gain: Float = 1) -> Waveform {
        var copy = self
        copy.mix(other, at: seconds, gain: gain)
        return copy
    }

    public func gained(_ gain: Float) -> Waveform {
        Waveform(sampleRate: sampleRate, samples: samples.map { $0 * gain })
    }

    /// Scales so the loudest sample sits at `peak`. Synthesis output lands wherever the
    /// maths puts it, and every sound has to arrive at the mixer at a predictable level.
    public func normalized(to target: Float = 0.9) -> Waveform {
        let highest = peak
        guard highest > 1e-6 else { return self }
        return gained(target / highest)
    }

    /// A linear fade at each end. The fade-out is the important one: a buffer that stops
    /// mid-cycle clicks, and a click on every footstep is unbearable.
    public func faded(inSeconds: Float = 0.001, outSeconds: Float = 0.01) -> Waveform {
        var out = self
        let fadeIn = Swift.min(Int(inSeconds * sampleRate), samples.count)
        let fadeOut = Swift.min(Int(outSeconds * sampleRate), samples.count)
        for index in 0..<fadeIn {
            out.samples[index] *= Float(index) / Float(Swift.max(1, fadeIn))
        }
        for index in 0..<fadeOut {
            let position = samples.count - 1 - index
            out.samples[position] *= Float(index) / Float(Swift.max(1, fadeOut))
        }
        return out
    }

    public func trimmed(toSeconds seconds: Float) -> Waveform {
        let limit = Swift.min(samples.count, Int(max(0, seconds) * sampleRate))
        return Waveform(sampleRate: sampleRate, samples: Array(samples[0..<limit]))
    }

    public func padded(toSeconds seconds: Float) -> Waveform {
        let target = Int(max(0, seconds) * sampleRate)
        guard target > samples.count else { return self }
        return Waveform(sampleRate: sampleRate,
                           samples: samples + [Float](repeating: 0, count: target - samples.count))
    }

    /// Wraps the tail back over the head so the buffer can loop without a seam — the same
    /// problem the textures have, one dimension down.
    public func loopable(crossfadeSeconds: Float = 0.25) -> Waveform {
        let fade = Swift.min(Int(crossfadeSeconds * sampleRate), samples.count / 2)
        guard fade > 1 else { return self }
        var out = Array(samples[0..<(samples.count - fade)])
        for index in 0..<fade {
            let t = Float(index) / Float(fade)
            // Equal power, so the crossfade does not dip in the middle the way a linear
            // one does on uncorrelated material like wind.
            let head = samples[index]
            let tail = samples[samples.count - fade + index]
            out[index] = head * sqrt(t) + tail * sqrt(1 - t)
        }
        return Waveform(sampleRate: sampleRate, samples: out)
    }

    /// Linear resampling to another rate.
    ///
    /// Synthesis runs at 44.1 kHz, but the device decides what the audio engine actually
    /// runs at — 48 kHz on most hardware — and `AVAudioPlayerNode` will not schedule a
    /// buffer whose format does not match the connection. Linear interpolation is crude,
    /// but the material here is noise bursts and short sines, and the artefacts land far
    /// above anything a phone speaker reproduces.
    public func resampled(to newRate: Float) -> Waveform {
        guard newRate > 0, abs(newRate - sampleRate) > 0.5, !samples.isEmpty else { return self }
        let ratio = sampleRate / newRate
        let count = Int(Float(samples.count) / ratio)
        var out = Waveform(sampleRate: newRate, count: count)
        for index in 0..<count {
            let source = Float(index) * ratio
            let low = Int(source)
            let high = Swift.min(low + 1, samples.count - 1)
            let fraction = source - Float(low)
            out.samples[index] = samples[low] * (1 - fraction) + samples[high] * fraction
        }
        return out
    }

    /// Cuts the tail once the sound has fallen below audibility, with a short release so
    /// the cut itself makes no sound.
    ///
    /// The room simulation has to be given room to ring into, and what it actually needs is
    /// far less than what is safe to allocate up front — a sniper's reverb was ringing into
    /// eleven seconds of buffer to produce about one second of audible tail. Every one of
    /// those samples costs memory in the voice pool and time in the mixer.
    public func trimmedSilence(threshold: Float = 0.002, releaseSeconds: Float = 0.05) -> Waveform {
        guard let last = samples.lastIndex(where: { abs($0) > threshold }) else { return self }
        let release = Int(releaseSeconds * sampleRate)
        let end = Swift.min(samples.count, last + release)
        return Waveform(sampleRate: sampleRate, samples: Array(samples[0..<end]))
            .faded(inSeconds: 0, outSeconds: releaseSeconds)
    }

    /// Guards against a recipe that produced a NaN or an infinity: one of those reaching
    /// the audio unit is a burst of static at full scale, straight into headphones.
    public func sanitized() -> Waveform {
        Waveform(sampleRate: sampleRate,
                    samples: samples.map { $0.isFinite ? MathUtil.clamp($0, -1, 1) : 0 })
    }
}
