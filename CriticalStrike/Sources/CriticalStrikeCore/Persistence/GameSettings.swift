import Foundation

public enum GraphicsQuality: String, Codable, CaseIterable, Sendable {
    case low, medium, high, ultra

    public var displayName: String { rawValue.capitalized }

    public var shadowsEnabled: Bool { self != .low }
    public var shadowMapSize: Int {
        switch self {
        case .low: return 0
        case .medium: return 1024
        case .high: return 2048
        case .ultra: return 4096
        }
    }
    public var bloomEnabled: Bool { self == .high || self == .ultra }
    public var motionBlurEnabled: Bool { self == .ultra }
    public var ambientOcclusionEnabled: Bool { self == .high || self == .ultra }
    public var maxDecals: Int {
        switch self {
        case .low: return 24
        case .medium: return 64
        case .high: return 128
        case .ultra: return 256
        }
    }
    public var maxParticles: Int {
        switch self {
        case .low: return 120
        case .medium: return 400
        case .high: return 900
        case .ultra: return 2000
        }
    }
    public var ragdollsEnabled: Bool { self != .low }
    public var textureScale: Float {
        switch self {
        case .low: return 0.5
        case .medium: return 0.75
        case .high: return 1.0
        case .ultra: return 1.0
        }
    }
    /// Render scale relative to native resolution before dynamic scaling kicks in.
    public var renderScale: Float {
        switch self {
        case .low: return 0.65
        case .medium: return 0.8
        case .high: return 1.0
        case .ultra: return 1.0
        }
    }
    public var antialiasingSamples: Int {
        switch self {
        case .low, .medium: return 0
        case .high: return 2
        case .ultra: return 4
        }
    }
}

public enum FrameRateCap: Int, Codable, CaseIterable, Sendable {
    case thirty = 30, forty = 40, sixty = 60, ninety = 90, onetwenty = 120

    public var displayName: String { "\(rawValue) FPS" }
}

public enum FireMode2: String, Codable, CaseIterable, Sendable {
    /// Tap the fire button to shoot.
    case manual
    /// Shoots automatically when the crosshair is over an enemy — the standard mobile
    /// assist that makes the game playable one-handed.
    case autoFire
    /// Fires the moment the player aims down sights at a target.
    case adsAutoFire

    public var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .autoFire: return "Auto Fire"
        case .adsAutoFire: return "Auto Fire (ADS only)"
        }
    }
}

public enum AimAssistLevel: String, Codable, CaseIterable, Sendable {
    case off, light, standard, strong

    public var displayName: String { rawValue.capitalized }

    /// How strongly the camera slows near a target.
    public var stickiness: Float {
        switch self {
        case .off: return 0
        case .light: return 0.18
        case .standard: return 0.35
        case .strong: return 0.55
        }
    }
    /// Gentle pull toward the target while aiming.
    public var magnetism: Float {
        switch self {
        case .off: return 0
        case .light: return 0.08
        case .standard: return 0.16
        case .strong: return 0.28
        }
    }
    /// Screen-space radius, in points, within which assist applies.
    public var radius: Float {
        switch self {
        case .off: return 0
        case .light: return 46
        case .standard: return 62
        case .strong: return 82
        }
    }
}

public struct HUDElementLayout: Codable, Equatable, Sendable {
    public var id: String
    public var x: Float          // 0...1 of screen width
    public var y: Float          // 0...1 of screen height
    public var scale: Float
    public var opacity: Float
    public var hidden: Bool

    public init(id: String, x: Float, y: Float, scale: Float = 1,
                opacity: Float = 1, hidden: Bool = false) {
        self.id = id; self.x = x; self.y = y; self.scale = scale
        self.opacity = opacity; self.hidden = hidden
    }
}

public struct GameSettings: Codable, Equatable, Sendable {
    // Graphics
    public var quality: GraphicsQuality
    public var frameRateCap: FrameRateCap
    public var dynamicResolution: Bool
    public var fieldOfView: Float           // degrees, 60...100
    public var showBlood: Bool
    public var showDamageNumbers: Bool
    public var screenShake: Float           // 0...1
    public var colorBlindMode: ColorBlindMode

    // Audio
    public var masterVolume: Float
    public var musicVolume: Float
    public var sfxVolume: Float
    public var voiceVolume: Float
    public var hapticsEnabled: Bool
    public var spatialAudioEnabled: Bool

    // Controls
    public var lookSensitivity: Float       // 0.1...3
    public var adsSensitivityScale: Float
    public var scopeSensitivityScale: Float
    public var gyroEnabled: Bool
    public var gyroSensitivity: Float
    public var invertY: Bool
    public var fireMode: FireMode2
    public var aimAssist: AimAssistLevel
    public var autoSprint: Bool
    public var autoReload: Bool
    public var tapToCrouchSlide: Bool
    public var leftHanded: Bool
    public var joystickFollowsTouch: Bool
    public var joystickDeadZone: Float

    // HUD
    public var crosshairStyle: CrosshairKind
    public var crosshairColorHex: UInt32
    public var crosshairScale: Float
    public var showMinimap: Bool
    public var showKillFeed: Bool
    public var hudOpacity: Float
    public var hudLayout: [HUDElementLayout]

    // Gameplay
    public var preferredRegion: Region
    public var voiceChatEnabled: Bool
    public var textChatEnabled: Bool
    public var profanityFilter: Bool
    public var allowCrossplay: Bool
    public var preferredBotDifficulty: BotDifficulty

    public init() {
        quality = .high
        frameRateCap = .sixty
        dynamicResolution = true
        fieldOfView = 78
        showBlood = true
        showDamageNumbers = true
        screenShake = 0.7
        colorBlindMode = .none

        masterVolume = 1
        musicVolume = 0.55
        sfxVolume = 1
        voiceVolume = 0.8
        hapticsEnabled = true
        spatialAudioEnabled = true

        lookSensitivity = 1.0
        adsSensitivityScale = 0.8
        scopeSensitivityScale = 0.55
        gyroEnabled = false
        gyroSensitivity = 1.0
        invertY = false
        fireMode = .autoFire
        aimAssist = .standard
        autoSprint = true
        autoReload = true
        tapToCrouchSlide = true
        leftHanded = false
        joystickFollowsTouch = true
        joystickDeadZone = 0.12

        crosshairStyle = .cross
        crosshairColorHex = 0x00FF88
        crosshairScale = 1
        showMinimap = true
        showKillFeed = true
        hudOpacity = 1
        hudLayout = GameSettings.defaultHUDLayout

        preferredRegion = .auto
        voiceChatEnabled = false
        textChatEnabled = true
        profanityFilter = true
        allowCrossplay = true
        preferredBotDifficulty = .regular
    }

    public static let defaultHUDLayout: [HUDElementLayout] = [
        HUDElementLayout(id: "movementStick", x: 0.16, y: 0.74),
        HUDElementLayout(id: "fireButton", x: 0.86, y: 0.76, scale: 1.15),
        HUDElementLayout(id: "adsButton", x: 0.70, y: 0.68),
        HUDElementLayout(id: "jumpButton", x: 0.93, y: 0.55),
        HUDElementLayout(id: "crouchButton", x: 0.70, y: 0.88),
        HUDElementLayout(id: "reloadButton", x: 0.86, y: 0.53),
        HUDElementLayout(id: "lethalButton", x: 0.56, y: 0.86),
        HUDElementLayout(id: "tacticalButton", x: 0.47, y: 0.86),
        HUDElementLayout(id: "meleeButton", x: 0.93, y: 0.38),
        HUDElementLayout(id: "weaponSwap", x: 0.62, y: 0.52),
        HUDElementLayout(id: "useButton", x: 0.62, y: 0.40),
        HUDElementLayout(id: "minimap", x: 0.08, y: 0.12, scale: 1),
        HUDElementLayout(id: "healthBar", x: 0.08, y: 0.92),
        HUDElementLayout(id: "ammoCounter", x: 0.92, y: 0.92),
        HUDElementLayout(id: "killFeed", x: 0.86, y: 0.12),
        HUDElementLayout(id: "scoreHeader", x: 0.5, y: 0.06),
        HUDElementLayout(id: "pingButton", x: 0.30, y: 0.88)
    ]

    public func layout(for id: String) -> HUDElementLayout {
        hudLayout.first { $0.id == id }
            ?? GameSettings.defaultHUDLayout.first { $0.id == id }
            ?? HUDElementLayout(id: id, x: 0.5, y: 0.5)
    }

    public mutating func updateLayout(_ layout: HUDElementLayout) {
        if let index = hudLayout.firstIndex(where: { $0.id == layout.id }) {
            hudLayout[index] = layout
        } else {
            hudLayout.append(layout)
        }
    }

    public mutating func resetHUDLayout() { hudLayout = GameSettings.defaultHUDLayout }

    /// Sensitivity actually used for a given aim state.
    public func effectiveSensitivity(aiming: Bool, scoped: Bool) -> Float {
        var s = lookSensitivity
        if scoped { s *= scopeSensitivityScale }
        else if aiming { s *= adsSensitivityScale }
        return s
    }

    /// A conservative default for the device — the app layer calls this on first launch.
    public static func recommended(forDeviceTier tier: DeviceTier) -> GameSettings {
        var s = GameSettings()
        switch tier {
        case .low:
            s.quality = .low
            s.frameRateCap = .thirty
            s.showBlood = false
        case .medium:
            s.quality = .medium
            s.frameRateCap = .sixty
        case .high:
            s.quality = .high
            s.frameRateCap = .sixty
        case .flagship:
            s.quality = .ultra
            s.frameRateCap = .onetwenty
        }
        return s
    }
}

public enum DeviceTier: String, Codable, Sendable {
    case low, medium, high, flagship
}

public enum ColorBlindMode: String, Codable, CaseIterable, Sendable {
    case none, protanopia, deuteranopia, tritanopia

    public var displayName: String {
        switch self {
        case .none: return "Off"
        case .protanopia: return "Protanopia"
        case .deuteranopia: return "Deuteranopia"
        case .tritanopia: return "Tritanopia"
        }
    }

    /// Team colors are re-mapped rather than relying on red/green alone.
    public func teamColor(_ team: Team) -> UInt32 {
        switch self {
        case .none: return team.colorHex
        case .protanopia, .deuteranopia:
            return team == .strike ? 0xFFB000 : 0x0066FF
        case .tritanopia:
            return team == .strike ? 0xFF4D6D : 0x00C2A8
        }
    }
}
