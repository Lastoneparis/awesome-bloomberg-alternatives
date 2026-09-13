import Foundation

/// Rewinds player positions to where the shooter actually saw them.
///
/// Without this, a player on 120ms has to lead every target by a body width. With it,
/// the server re-creates the world as it appeared on the shooter's screen, resolves the
/// shot there, and applies the result to the present. The rewind window is capped so a
/// player cannot fake a huge latency to shoot people who are long gone.
public final class LagCompensator {
    public struct Frame {
        public var tick: UInt32
        public var time: Float
        public var volumes: [HitVolume]
    }

    public static let maxRewindSeconds: Float = 0.25
    private var history: [Frame] = []
    private let capacity: Int

    public init(historySeconds: Float = 1.0) {
        capacity = Int(historySeconds * Float(GameClock.tickRate)) + 2
        history.reserveCapacity(capacity)
    }

    public func record(sim: MatchSimulation) {
        let volumes = sim.allPlayers().filter(\.isAlive).map {
            HitVolume(player: $0.id, team: $0.team, position: $0.position,
                      crouchScale: $0.stance.heightScale, isAlive: true)
        }
        history.append(Frame(tick: sim.tick, time: sim.time, volumes: volumes))
        if history.count > capacity { history.removeFirst(history.count - capacity) }
    }

    public func reset() { history.removeAll(keepingCapacity: true) }

    /// Hit volumes as they were `latency` seconds ago, interpolated between recorded frames.
    public func rewind(latency: Float, now: Float, excluding shooter: PlayerID) -> [HitVolume] {
        let clamped = MathUtil.clamp(latency, 0, LagCompensator.maxRewindSeconds)
        let target = now - clamped
        guard history.count >= 2 else {
            return history.last?.volumes.filter { $0.player != shooter } ?? []
        }

        var previous = history[0]
        for frame in history {
            if frame.time >= target {
                let span = frame.time - previous.time
                let t = span > 1e-5 ? MathUtil.clamp((target - previous.time) / span, 0, 1) : 1
                return interpolate(previous, frame, t).filter { $0.player != shooter }
            }
            previous = frame
        }
        return history[history.count - 1].volumes.filter { $0.player != shooter }
    }

    private func interpolate(_ a: Frame, _ b: Frame, _ t: Float) -> [HitVolume] {
        b.volumes.map { target in
            guard let from = a.volumes.first(where: { $0.player == target.player }) else { return target }
            var out = target
            out.position = from.position.lerp(target.position, t)
            out.crouchScale = MathUtil.lerp(from.crouchScale, target.crouchScale, t)
            return out
        }
    }

    /// Total rewind a shot should get: half the round-trip plus the client's own
    /// interpolation delay, because that is what the shooter was actually looking at.
    public static func rewindAmount(roundTripTime: Float, interpolationDelay: Float) -> Float {
        MathUtil.clamp(roundTripTime * 0.5 + interpolationDelay, 0, maxRewindSeconds)
    }
}
