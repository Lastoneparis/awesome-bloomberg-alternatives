import Foundation

/// Fixed-step simulation clock. The renderer runs free, the simulation runs at
/// `tickRate` Hz, and the leftover is handed to the renderer as an interpolation alpha.
public struct GameClock: Sendable {
    public static let tickRate: Int = 64
    public static let tickInterval: Float = 1.0 / Float(GameClock.tickRate)
    /// Snapshots are broadcast at a lower rate than the sim to keep mobile bandwidth sane.
    public static let snapshotRate: Int = 20
    public static let maxCatchUpTicks: Int = 8

    public private(set) var tick: UInt32 = 0
    public private(set) var accumulator: Float = 0
    public private(set) var elapsed: Float = 0

    public init(startTick: UInt32 = 0) { tick = startTick }

    /// Feeds real frame time in and returns how many fixed steps to run.
    /// Clamped so a long stall (app backgrounded) never causes a death-spiral.
    public mutating func advance(deltaTime: Float) -> Int {
        accumulator += min(deltaTime, 0.25)
        var steps = 0
        while accumulator >= GameClock.tickInterval && steps < GameClock.maxCatchUpTicks {
            accumulator -= GameClock.tickInterval
            steps += 1
        }
        if steps == GameClock.maxCatchUpTicks { accumulator = 0 }
        return steps
    }

    public mutating func consumeTick() {
        tick &+= 1
        elapsed += GameClock.tickInterval
    }

    /// 0...1 blend between the previous and current simulation state.
    public var interpolationAlpha: Float { accumulator / GameClock.tickInterval }

    public static func seconds(forTicks ticks: UInt32) -> Float {
        Float(ticks) * tickInterval
    }

    public static func ticks(forSeconds seconds: Float) -> UInt32 {
        UInt32(max(0, (seconds * Float(tickRate)).rounded()))
    }
}

/// Simple countdown used all over the sim (reload, round timer, bomb, respawn).
///
/// Named `Countdown` rather than `Timer` because a public `Timer` in a module that gets
/// imported alongside Foundation shadows `Foundation.Timer` in every such file. It already
/// cost two `Foundation.Timer` qualifications in the app and broke the test target
/// outright, where XCTest brings Foundation in.
public struct Countdown: Codable, Equatable, Sendable {
    public private(set) var remaining: Float
    public private(set) var duration: Float

    public init(duration: Float = 0) {
        self.duration = duration
        self.remaining = duration
    }

    public var isRunning: Bool { remaining > 0 }
    public var isFinished: Bool { remaining <= 0 }
    public var progress: Float { duration > 0 ? 1 - MathUtil.clamp(remaining / duration, 0, 1) : 1 }

    public mutating func start(_ seconds: Float) {
        duration = seconds
        remaining = seconds
    }

    public mutating func stop() { remaining = 0 }

    /// Returns true on the tick the timer completes.
    @discardableResult
    public mutating func tick(_ dt: Float) -> Bool {
        guard remaining > 0 else { return false }
        remaining -= dt
        if remaining <= 0 {
            remaining = 0
            return true
        }
        return false
    }
}
