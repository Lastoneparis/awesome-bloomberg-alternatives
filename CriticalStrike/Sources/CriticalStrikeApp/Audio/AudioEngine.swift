import Foundation
import AVFoundation
import CriticalStrikeCore

/// Audio for a competitive shooter has one job above all others: tell the player where
/// the danger is. Footsteps and gunfire are spatialised through AVAudioEnvironmentNode;
/// UI and music are flat. Everything is pooled, because allocating a player mid-firefight
/// is a guaranteed hitch.
final class AudioEngine {
    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private let musicPlayer = AVAudioPlayerNode()
    private let uiMixer = AVAudioMixerNode()

    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var spatialPool: [AVAudioPlayerNode] = []
    private var uiPool: [AVAudioPlayerNode] = []
    private var nextSpatial = 0
    private var nextUI = 0
    private var isRunning = false
    private var currentMusic: String?

    private var masterVolume: Float = 1
    private var musicVolume: Float = 0.55
    private var sfxVolume: Float = 1
    private var voiceVolume: Float = 0.8
    private var spatialEnabled = true

    private let spatialVoiceCount = 24
    private let uiVoiceCount = 8

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        configureSession()
        engine.attach(environment)
        engine.attach(musicPlayer)
        engine.attach(uiMixer)

        engine.connect(environment, to: engine.mainMixerNode, format: nil)
        engine.connect(uiMixer, to: engine.mainMixerNode, format: nil)
        engine.connect(musicPlayer, to: uiMixer, format: nil)

        environment.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        environment.distanceAttenuationParameters.referenceDistance = 2.5
        environment.distanceAttenuationParameters.maximumDistance = 90
        environment.distanceAttenuationParameters.rolloffFactor = 1.4
        environment.reverbParameters.enable = true
        environment.reverbParameters.loadFactoryReverbPreset(.mediumRoom)

        for _ in 0..<spatialVoiceCount {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: environment, format: monoFormat())
            node.renderingAlgorithm = .HRTFHQ
            spatialPool.append(node)
        }
        for _ in 0..<uiVoiceCount {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: uiMixer, format: nil)
            uiPool.append(node)
        }

        do {
            try engine.start()
            isRunning = true
        } catch {
            Log.error("Audio engine failed to start: \(error)", category: "audio")
        }
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .ambient means the player's own music keeps playing — a courtesy mobile
            // players expect, and the App Store review guidelines encourage.
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            Log.warn("Audio session setup failed: \(error)", category: "audio")
        }
    }

    func setSuspended(_ suspended: Bool) {
        guard isRunning else { return }
        if suspended {
            engine.pause()
        } else {
            try? engine.start()
        }
    }

    func apply(settings: GameSettings) {
        masterVolume = settings.masterVolume
        musicVolume = settings.musicVolume
        sfxVolume = settings.sfxVolume
        voiceVolume = settings.voiceVolume
        spatialEnabled = settings.spatialAudioEnabled
        engine.mainMixerNode.outputVolume = masterVolume
        musicPlayer.volume = musicVolume
        // The rendering algorithm is a property of each 3D input, not of the environment.
        for node in spatialPool {
            node.renderingAlgorithm = spatialEnabled ? .HRTFHQ : .equalPowerPanning
        }
    }

    // MARK: - Listener

    /// Updates the listener transform each frame so spatial audio tracks the camera.
    func updateListener(position: Vec3, forward: Vec3, up: Vec3) {
        guard isRunning else { return }
        environment.listenerPosition = AVAudio3DPoint(x: position.x, y: position.y, z: position.z)
        environment.listenerVectorOrientation = AVAudio3DVectorOrientation(
            forward: AVAudio3DVector(x: forward.x, y: forward.y, z: forward.z),
            up: AVAudio3DVector(x: up.x, y: up.y, z: up.z))
    }

    // MARK: - Playback

    func playSpatial(_ name: String, at position: Vec3, volume: Float = 1) {
        guard isRunning, let buffer = buffer(named: name) else { return }
        let node = spatialPool[nextSpatial % spatialPool.count]
        nextSpatial += 1
        node.stop()
        node.position = AVAudio3DPoint(x: position.x, y: position.y, z: position.z)
        node.volume = volume * sfxVolume
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
        node.play()
    }

    func playUI(_ name: String, volume: Float = 1) {
        guard isRunning, let buffer = buffer(named: name) else { return }
        let node = uiPool[nextUI % uiPool.count]
        nextUI += 1
        node.stop()
        node.volume = volume * sfxVolume
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
        node.play()
    }

    func playVoice(_ name: String, at position: Vec3?) {
        if let position {
            playSpatial(name, at: position, volume: voiceVolume / max(sfxVolume, 0.01))
        } else {
            playUI(name, volume: voiceVolume / max(sfxVolume, 0.01))
        }
    }

    func playMusic(_ name: String, loop: Bool = true) {
        guard isRunning, currentMusic != name, let buffer = buffer(named: name) else { return }
        currentMusic = name
        musicPlayer.stop()
        musicPlayer.volume = musicVolume
        musicPlayer.scheduleBuffer(buffer, at: nil,
                                   options: loop ? [.loops, .interrupts] : .interrupts)
        musicPlayer.play()
    }

    func stopMusic() {
        currentMusic = nil
        musicPlayer.stop()
    }

    /// Ducks music under an important moment (round win, bomb planted).
    func duckMusic(to volume: Float, duration: TimeInterval = 0.4) {
        guard isRunning else { return }
        musicPlayer.volume = volume * musicVolume
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self else { return }
            self.musicPlayer.volume = self.musicVolume
        }
    }

    // MARK: - Buffers

    private func buffer(named name: String) -> AVAudioPCMBuffer? {
        if let cached = buffers[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav")
            ?? Bundle.main.url(forResource: name, withExtension: "m4a")
            ?? Bundle.main.url(forResource: name, withExtension: "caf") else {
            return nil
        }
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)) else {
            return nil
        }
        try? file.read(into: buffer)
        buffers[name] = buffer
        return buffer
    }

    private func monoFormat() -> AVAudioFormat? {
        // Spatialisation requires a mono source; stereo sources are played flat.
        AVAudioFormat(standardFormatWithSampleRate: engine.outputNode.outputFormat(forBus: 0).sampleRate,
                      channels: 1)
    }

    /// Preloads the sounds a match will need so the first gunshot never stutters.
    func preload(for map: MapData, loadout: Loadout) {
        var names: Set<String> = [
            "sfx_hitmarker", "sfx_headshot", "sfx_kill", "sfx_death",
            "sfx_reload_empty", "sfx_dryfire", "sfx_grenade_bounce", "sfx_explosion",
            "sfx_flash", "sfx_smoke", "sfx_fire_loop", "sfx_pickup", "sfx_jump", "sfx_land",
            map.environment.ambienceLoop, map.environment.musicTrack
        ]
        for surface in SurfaceKind.allCases {
            names.insert(surface.footstepSound)
        }
        for build in [loadout.primary, loadout.secondary, loadout.melee] {
            let weapon = build.resolved()
            names.insert(weapon.fireSound)
            names.insert(weapon.reloadSound)
        }
        for name in names { _ = buffer(named: name) }
    }
}
