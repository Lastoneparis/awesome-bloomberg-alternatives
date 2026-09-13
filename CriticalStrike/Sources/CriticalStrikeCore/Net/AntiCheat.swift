import Foundation

/// Server-side sanity checks on client input.
///
/// This is not DRM and it is not trying to detect a determined cheat — that belongs on the
/// backend with behavioural analysis. What it does is make the obvious client-side hacks
/// (speed, teleport, no-recoil bursts, impossible fire rates, aim snapping) simply not work,
/// because the server refuses to simulate them.
public final class AntiCheat {
    public struct Verdict {
        public var accepted: Bool
        public var reason: String
        public static let ok = Verdict(accepted: true, reason: "")
        public static func reject(_ reason: String) -> Verdict {
            Verdict(accepted: false, reason: reason)
        }
    }

    /// Rolling per-player telemetry used to spot patterns rather than single frames.
    private struct Telemetry {
        var lastTick: UInt32 = 0
        var lastYaw: Float = 0
        var lastPitch: Float = 0
        var snapCount: Int = 0
        var shotsThisSecond: Int = 0
        var secondStart: Float = 0
        var headshotStreak: Int = 0
        var totalShots: Int = 0
        var totalHits: Int = 0
    }

    private var telemetry: [PlayerID: Telemetry] = [:]

    /// Angular speed above this, sustained, is not reachable on a touch screen.
    public static let maxAimSpeedRadiansPerSecond: Float = 28
    public static let maxSnapsPerWindow = 8

    public init() {}

    public func validate(command: InputCommand, player: PlayerState, sim: MatchSimulation) -> Verdict {
        var t = telemetry[player.id] ?? Telemetry()
        defer { telemetry[player.id] = t }

        // 1. Movement intent must be inside the unit square (the sim clamps anyway, but a
        //    client sending 12.0 is telling on itself).
        if abs(command.moveForward) > 1.01 || abs(command.moveRight) > 1.01 {
            return .reject("move vector out of range")
        }
        if !command.moveForward.isFinite || !command.moveRight.isFinite
            || !command.yaw.isFinite || !command.pitch.isFinite {
            return .reject("non-finite input")
        }

        // 2. Pitch cannot exceed the clamp.
        if abs(command.pitch) > ViewAngles.maxPitch + 0.01 {
            return .reject("pitch out of range")
        }

        // 3. Timestep must be plausible; a huge dt is a classic speed hack.
        if command.deltaTime > 0.12 || command.deltaTime <= 0 {
            return .reject("implausible delta time")
        }

        // 4. Aim snap detection. A single snap is a flick; a sustained stream of them
        //    across many ticks is an aimbot.
        let dt = max(command.deltaTime, 0.001)
        let yawRate = abs(MathUtil.angleDelta(t.lastYaw, command.yaw)) / dt
        let pitchRate = abs(command.pitch - t.lastPitch) / dt
        if yawRate > AntiCheat.maxAimSpeedRadiansPerSecond
            || pitchRate > AntiCheat.maxAimSpeedRadiansPerSecond {
            t.snapCount += 1
            if t.snapCount > AntiCheat.maxSnapsPerWindow {
                t.snapCount = 0
                return .reject("aim snap pattern")
            }
        } else if t.snapCount > 0 {
            t.snapCount -= 1
        }
        t.lastYaw = command.yaw
        t.lastPitch = command.pitch

        // 5. Fire rate. The weapon state machine enforces this anyway; a client asking
        //    for more just gets counted.
        if command.buttons.contains(.fire) {
            if sim.time - t.secondStart > 1 {
                t.secondStart = sim.time
                t.shotsThisSecond = 0
            }
            t.shotsThisSecond += 1
            let weapon = player.activeWeapon
            let allowed = Int(weapon.roundsPerMinute / 60 * 1.5) + 4
            if t.shotsThisSecond > allowed {
                return .reject("fire rate above weapon limit")
            }
        }

        // 6. Ticks must move forward.
        if command.tick != 0 && command.tick + 64 < t.lastTick {
            return .reject("stale tick")
        }
        t.lastTick = max(t.lastTick, command.tick)
        return .ok
    }

    /// Called by the server when a shot lands so accuracy can be profiled over a match.
    public func recordShot(player: PlayerID, hit: Bool, headshot: Bool) {
        var t = telemetry[player] ?? Telemetry()
        t.totalShots += 1
        if hit { t.totalHits += 1 }
        t.headshotStreak = headshot ? t.headshotStreak + 1 : 0
        telemetry[player] = t
    }

    /// Heuristic score 0...1 — anything above ~0.8 deserves a backend review, never an
    /// automatic in-game ban.
    public func suspicionScore(for player: PlayerID) -> Float {
        guard let t = telemetry[player], t.totalShots > 40 else { return 0 }
        let accuracy = Float(t.totalHits) / Float(t.totalShots)
        var score: Float = 0
        if accuracy > 0.75 { score += (accuracy - 0.75) * 2 }
        if t.headshotStreak > 8 { score += 0.3 }
        return MathUtil.clamp(score, 0, 1)
    }

    public func reset() { telemetry.removeAll() }
}
