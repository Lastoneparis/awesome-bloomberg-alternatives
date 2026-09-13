import Foundation
import AVFoundation
import CriticalStrikeCore

/// Turns the core's synthesised `Waveform`s into the `AVAudioPCMBuffer`s the engine
/// schedules, and caches them.
///
/// This is the audio counterpart of `TextureLibrary`: generation is deterministic, so it
/// happens once during loading and is reused for the whole session. Unlike the textures
/// there is no disk cache — a gunshot is a few tens of kilobytes and regenerating it costs
/// about a millisecond, which is cheaper than reading a file.
final class ProceduralSoundLibrary: @unchecked Sendable {
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var missing: Set<String> = []
    private let lock = NSLock()
    private let sampleRate: Double

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    func buffer(named name: String) -> AVAudioPCMBuffer? {
        lock.lock()
        if let cached = cache[name] {
            lock.unlock()
            return cached
        }
        // Names with no recipe are remembered, so a sound requested every frame — an
        // ambience loop that does not exist, say — is not re-synthesised and re-failed.
        if missing.contains(name) {
            lock.unlock()
            return nil
        }
        lock.unlock()

        guard let synthesised = SoundBank.sound(named: name) else {
            lock.lock(); missing.insert(name); lock.unlock()
            return nil
        }
        guard let pcm = ProceduralSoundLibrary.pcm(from: synthesised, at: sampleRate) else {
            lock.lock(); missing.insert(name); lock.unlock()
            return nil
        }
        lock.lock(); cache[name] = pcm; lock.unlock()
        return pcm
    }

    /// Mono float PCM at the engine's rate — mono because the environment node will only
    /// spatialise a mono source, and a gunshot that does not come from a direction is
    /// worse than no gunshot at all.
    private static func pcm(from buffer: Waveform, at sampleRate: Double) -> AVAudioPCMBuffer? {
        let resampled = buffer.resampled(to: Float(sampleRate))
        guard !resampled.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let pcm = AVAudioPCMBuffer(pcmFormat: format,
                                         frameCapacity: AVAudioFrameCount(resampled.count)),
              let channel = pcm.floatChannelData?[0] else {
            return nil
        }
        resampled.samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: resampled.count)
        }
        pcm.frameLength = AVAudioFrameCount(resampled.count)
        return pcm
    }

    /// Generates everything a match will ask for, off the main thread. Synthesising a
    /// music bed is tens of milliseconds; doing it on the first frame that needs it would
    /// be a visible hitch at exactly the wrong moment.
    func warmUp(names: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for name in Set(names) {
                group.addTask { [self] in _ = buffer(named: name) }
            }
        }
    }

    var cachedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return cache.count
    }
}
