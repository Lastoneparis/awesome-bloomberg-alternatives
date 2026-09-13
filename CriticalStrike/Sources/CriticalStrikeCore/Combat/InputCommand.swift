import Foundation

public struct InputButtons: OptionSet, Codable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let fire        = InputButtons(rawValue: 1 << 0)
    public static let aim         = InputButtons(rawValue: 1 << 1)
    public static let jump        = InputButtons(rawValue: 1 << 2)
    public static let crouch      = InputButtons(rawValue: 1 << 3)
    public static let reload      = InputButtons(rawValue: 1 << 4)
    public static let use         = InputButtons(rawValue: 1 << 5)
    public static let sprint      = InputButtons(rawValue: 1 << 6)
    public static let lethal      = InputButtons(rawValue: 1 << 7)
    public static let tactical    = InputButtons(rawValue: 1 << 8)
    public static let melee       = InputButtons(rawValue: 1 << 9)
    public static let swapWeapon  = InputButtons(rawValue: 1 << 10)
    public static let scopeToggle = InputButtons(rawValue: 1 << 11)
    public static let drop        = InputButtons(rawValue: 1 << 12)
}

/// One tick of player intent. This is the only thing a client is allowed to send about
/// its own movement — the server re-simulates it, so a modified client cannot teleport.
public struct InputCommand: Codable, Sendable {
    public var tick: UInt32
    public var deltaTime: Float
    public var moveForward: Float     // -1...1
    public var moveRight: Float       // -1...1
    public var yaw: Float
    public var pitch: Float
    public var buttons: InputButtons
    public var requestedSlot: LoadoutSlot?
    /// Sequence number so the client can match a server correction back to a prediction.
    public var sequence: UInt16

    public init(tick: UInt32 = 0, deltaTime: Float = GameClock.tickInterval,
                moveForward: Float = 0, moveRight: Float = 0,
                yaw: Float = 0, pitch: Float = 0, buttons: InputButtons = [],
                requestedSlot: LoadoutSlot? = nil, sequence: UInt16 = 0) {
        self.tick = tick; self.deltaTime = deltaTime
        self.moveForward = moveForward; self.moveRight = moveRight
        self.yaw = yaw; self.pitch = pitch; self.buttons = buttons
        self.requestedSlot = requestedSlot; self.sequence = sequence
    }

    public var moveVector: Vec3 {
        let v = Vec3(moveRight, 0, -moveForward)
        return v.lengthSquared > 1 ? v.normalized : v
    }

    public var wantsMove: Bool { abs(moveForward) > 0.05 || abs(moveRight) > 0.05 }

    /// Server-side sanity clamp. A hostile client can put anything in here.
    public func sanitized() -> InputCommand {
        var c = self
        c.deltaTime = MathUtil.clamp(deltaTime, 0.001, 0.1)
        c.moveForward = MathUtil.clamp(moveForward, -1, 1)
        c.moveRight = MathUtil.clamp(moveRight, -1, 1)
        c.pitch = MathUtil.clamp(pitch, -ViewAngles.maxPitch, ViewAngles.maxPitch)
        c.yaw = MathUtil.wrapAngle(yaw)
        if !c.deltaTime.isFinite { c.deltaTime = GameClock.tickInterval }
        if !c.moveForward.isFinite { c.moveForward = 0 }
        if !c.moveRight.isFinite { c.moveRight = 0 }
        if !c.pitch.isFinite { c.pitch = 0 }
        if !c.yaw.isFinite { c.yaw = 0 }
        return c
    }
}
