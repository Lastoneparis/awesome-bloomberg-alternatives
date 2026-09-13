import Foundation

/// Client-side prediction and reconciliation for the local player.
///
/// The client simulates its own movement immediately so the stick feels instant, keeps
/// every unacknowledged input, and when the server's authoritative position arrives it
/// rewinds to that state and replays the inputs the server had not yet seen. If the
/// replayed result matches what the client already displayed, nothing visibly happens —
/// which is the case 99% of the time.
public final class PredictionSystem {
    public struct PendingInput {
        public var command: InputCommand
        public var predictedPosition: Vec3
        public var predictedVelocity: Vec3
    }

    public private(set) var pending: [PendingInput] = []
    public private(set) var lastAcknowledgedSequence: UInt16 = 0
    public private(set) var lastCorrectionDistance: Float = 0
    public private(set) var correctionCount: Int = 0

    /// Errors below this are smoothed away invisibly instead of snapping.
    public static let smoothingThreshold: Float = 0.35
    public static let maxPendingInputs = 128

    private var smoothingOffset: Vec3 = .zero

    public init() {}

    public func reset() {
        pending.removeAll(keepingCapacity: true)
        smoothingOffset = .zero
        lastCorrectionDistance = 0
        correctionCount = 0
    }

    public func record(command: InputCommand, player: PlayerState) {
        pending.append(PendingInput(command: command,
                                    predictedPosition: player.position,
                                    predictedVelocity: player.velocity))
        if pending.count > PredictionSystem.maxPendingInputs {
            pending.removeFirst(pending.count - PredictionSystem.maxPendingInputs)
        }
    }

    /// Applies an authoritative update and replays unacknowledged inputs.
    /// - Returns: true when a visible correction happened.
    @discardableResult
    public func reconcile(player: inout PlayerState, authoritative: PlayerSnapshot,
                          acknowledgedSequence: UInt16, world: CollisionWorld,
                          events: EventBus, now: Float) -> Bool {
        lastAcknowledgedSequence = acknowledgedSequence
        // Drop everything the server has already processed.
        pending.removeAll { sequenceIsOlderOrEqual($0.command.sequence, acknowledgedSequence) }

        let predictedAtAck = player.position
        player.position = authoritative.position
        player.velocity = authoritative.velocity
        player.health = Float(authoritative.health)
        player.armor = Float(authoritative.armor)
        player.isAlive = authoritative.isAlive
        player.stance = authoritative.stance

        // Replay.
        let ctx = MovementSystem.Context(world: world, now: now, events: EventBus())
        for entry in pending {
            MovementSystem.step(player: &player, input: entry.command, ctx: ctx)
        }

        let error = predictedAtAck.distance(to: player.position)
        lastCorrectionDistance = error
        guard error > 0.01 else { return false }

        if error < PredictionSystem.smoothingThreshold {
            // Keep rendering where the player thought they were and close the gap over
            // a few frames — the player never sees a teleport.
            smoothingOffset = predictedAtAck - player.position
            return false
        }
        correctionCount += 1
        smoothingOffset = .zero
        Log.debug("Prediction correction: \(error)m", category: "net")
        _ = events
        return true
    }

    /// Visual position for rendering: the corrected position plus the decaying error.
    public func renderPosition(for authoritative: Vec3, dt: Float) -> Vec3 {
        smoothingOffset = MathUtil.dampVec(smoothingOffset, .zero, halfLife: 0.06, dt: dt)
        return authoritative + smoothingOffset
    }

    private func sequenceIsOlderOrEqual(_ a: UInt16, _ b: UInt16) -> Bool {
        // Wrap-safe comparison for a 16-bit sequence space.
        let diff = Int16(bitPattern: a &- b)
        return diff <= 0
    }
}

/// Buffers remote snapshots and plays them back on a delay so other players move smoothly
/// even with jittery arrival times. 100ms of buffer costs a little aim lead and buys a lot
/// of stability on mobile networks.
public final class InterpolationBuffer {
    public var interpolationDelay: Float = 0.1
    public private(set) var snapshots: [WorldSnapshot] = []
    public private(set) var latestServerTime: Float = 0
    private var localClock: Float = 0
    private let maxSnapshots = 32

    public init() {}

    public func reset() {
        snapshots.removeAll(keepingCapacity: true)
        localClock = 0
        latestServerTime = 0
    }

    public func insert(_ snapshot: WorldSnapshot) {
        // Ignore snapshots that arrive out of order.
        if let last = snapshots.last, snapshot.tick <= last.tick { return }
        snapshots.append(snapshot)
        latestServerTime = snapshot.serverTime
        if snapshots.count > maxSnapshots { snapshots.removeFirst(snapshots.count - maxSnapshots) }
        // Nudge the local playback clock toward the buffer target rather than snapping,
        // which keeps motion smooth when latency drifts.
        let target = snapshot.serverTime - interpolationDelay
        if localClock == 0 {
            localClock = target
        } else {
            localClock += (target - localClock) * 0.08
        }
    }

    public func advance(dt: Float) {
        localClock += dt
    }

    /// Interpolated view of the world at the current playback time.
    public func sample() -> WorldSnapshot? {
        guard !snapshots.isEmpty else { return nil }
        guard snapshots.count > 1 else { return snapshots.last }

        var previous = snapshots[0]
        for snapshot in snapshots {
            if snapshot.serverTime > localClock {
                let span = snapshot.serverTime - previous.serverTime
                let t = span > 1e-5 ? MathUtil.clamp((localClock - previous.serverTime) / span, 0, 1) : 1
                return blend(previous, snapshot, t)
            }
            previous = snapshot
        }
        // Ran off the end of the buffer: extrapolate briefly instead of freezing.
        let lag = localClock - previous.serverTime
        var extrapolated = previous
        extrapolated.players = previous.players.map { $0.extrapolated(by: lag) }
        return extrapolated
    }

    private func blend(_ a: WorldSnapshot, _ b: WorldSnapshot, _ t: Float) -> WorldSnapshot {
        var out = b
        out.players = b.players.map { target in
            guard let from = a.player(target.id) else { return target }
            return from.interpolated(to: target, t: t)
        }
        out.projectiles = b.projectiles.map { target in
            guard let from = a.projectiles.first(where: { $0.entity == target.entity }) else { return target }
            var p = target
            p.position = from.position.lerp(target.position, t)
            return p
        }
        return out
    }

    /// Estimated one-way latency, for the HUD's connection indicator.
    public func estimatedDelay() -> Float {
        max(0, latestServerTime - localClock)
    }
}
