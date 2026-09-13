import Foundation
import UIKit
import Metal
import CriticalStrikeCore

/// Works out what the device can handle so the first launch picks sensible graphics
/// settings instead of dumping the player into a slideshow.
enum DeviceCapabilities {
    static var modelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            identifier += String(UnicodeScalar(UInt8(value)))
        }
    }

    static var physicalMemoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    }

    static var processorCount: Int { ProcessInfo.processInfo.processorCount }

    static var supportsProMotion: Bool {
        UIScreen.main.maximumFramesPerSecond > 60
    }

    static var maximumFrameRate: Int { UIScreen.main.maximumFramesPerSecond }

    /// GPU family is the most reliable single signal available without a device database.
    static var tier: DeviceTier {
        guard let device = MTLCreateSystemDefaultDevice() else { return .low }
        let memory = physicalMemoryGB

        if device.supportsFamily(.apple8) && memory >= 6 { return .flagship }
        if device.supportsFamily(.apple7) && memory >= 4 { return .high }
        if device.supportsFamily(.apple6) && memory >= 3 { return .medium }
        if device.supportsFamily(.apple5) && memory >= 3 { return .medium }
        return .low
    }

    static var recommendedSettings: GameSettings {
        var settings = GameSettings.recommended(forDeviceTier: tier)
        if supportsProMotion && tier == .flagship {
            settings.frameRateCap = .onetwenty
        }
        return settings
    }

    /// Thermal state drives the dynamic-resolution governor: a hot phone gets a lower
    /// render scale rather than a dropped frame rate, because frame pacing matters more.
    static var thermalState: ProcessInfo.ThermalState {
        ProcessInfo.processInfo.thermalState
    }

    static var isLowPowerModeEnabled: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    static func summary() -> String {
        """
        device=\(modelIdentifier) tier=\(tier.rawValue) ram=\(String(format: "%.1f", physicalMemoryGB))GB \
        cores=\(processorCount) maxFPS=\(maximumFrameRate)
        """
    }
}
