import Foundation

/// Client-side half of the netcode. Owns a local `MatchSimulation` used purely for
/// prediction, the interpolation buffer for everyone else, and the input stream going out.
public final class GameClientSession {
    public private(set) var state: NetConnectionState = .disconnected {
        didSet {
            guard state != oldValue else { return }
            events.emit(.networkStateChanged(state))
        }
    }
    public private(set) var localPlayer: PlayerID = .none
    public private(set) var matchInfo: NetMatchInfo?
    public private(set) var roundTripTime: Float = 0.08
    public private(set) var packetLoss: Float = 0

    public let events = EventBus()
    public let prediction = PredictionSystem()
    public let interpolation = InterpolationBuffer()
    public var predictedSimulation: MatchSimulation?
    public var onKicked: ((String) -> Void)?
    public var onMatchEnded: (([PlayerID: Int]) -> Void)?

    private var transport: NetTransport?
    private var lastBaseline: WorldSnapshot?
    private var pendingCommands: [InputCommand] = []
    private var sequence: UInt16 = 0
    private var pingTimer: Float = 0
    private var lastPingSent: Float = 0
    private var clientTime: Float = 0
    private var playerName: String = "Player"
    private var accountID: String = ""
    private var mapBounds = AABB(min: Vec3(-64, -8, -64), max: Vec3(64, 40, 64))

    public init() {}

    // MARK: - Connection

    public func connect(transport: NetTransport, name: String, accountID: String,
                        preferredTeam: Team = .none) {
        self.transport = transport
        self.playerName = name
        self.accountID = accountID
        transport.onData = { [weak self] _, data in self?.receive(data) }
        transport.onPeerDisconnected = { [weak self] _ in self?.state = .disconnected }
        state = .connecting
        let handshake = NetHandshake(playerName: name, accountID: accountID,
                                     preferredTeam: preferredTeam)
        transport.send(handshake.encode(), to: .host, reliable: true)
        state = .authenticating
    }

    public func disconnect() {
        var w = BitWriter(capacity: 8)
        w.write(NetMessageType.leave.rawValue)
        transport?.send(w.finish(), to: .host, reliable: true)
        transport = nil
        state = .disconnected
        prediction.reset()
        interpolation.reset()
    }

    // MARK: - Frame

    public func update(deltaTime: Float, input: InputCommand) {
        clientTime += deltaTime
        interpolation.advance(dt: deltaTime)
        guard state.isUsable else { return }

        sequence = sequence &+ 1
        var command = input
        command.sequence = sequence
        command.deltaTime = deltaTime

        // Predict locally so the controls feel instant.
        if let sim = predictedSimulation, var player = sim.player(localPlayer), player.isAlive {
            let ctx = MovementSystem.Context(world: sim.world, now: sim.time, events: events)
            MovementSystem.step(player: &player, input: command, ctx: ctx)
            sim.mutatePlayer(localPlayer) { $0 = player }
            prediction.record(command: command, player: player)
        }

        pendingCommands.append(command)
        if pendingCommands.count > 8 { pendingCommands.removeFirst(pendingCommands.count - 8) }

        let packet = NetInputPacket(commands: pendingCommands,
                                    lastAcknowledgedSnapshot: lastBaseline?.tick ?? 0,
                                    clientTime: clientTime)
        transport?.send(packet.encode(), to: .host, reliable: false)

        pingTimer += deltaTime
        if pingTimer > 1 {
            pingTimer = 0
            lastPingSent = clientTime
            var w = BitWriter(capacity: 16)
            w.write(NetMessageType.ping.rawValue)
            w.write(float: clientTime)
            transport?.send(w.finish(), to: .host, reliable: false)
        }
    }

    /// Interpolated world for rendering everything except the local player.
    public func renderSnapshot() -> WorldSnapshot? { interpolation.sample() }

    // MARK: - Receiving

    private func receive(_ data: Data) {
        var reader = BitReader(data: data)
        guard let type = NetMessageType(rawValue: reader.readUInt8()) else { return }

        switch type {
        case .handshakeAck:
            localPlayer = PlayerID(rawValue: reader.readUInt8())
            state = .connected
        case .matchInfo:
            guard let info = NetMatchInfo.decode(&reader) else { return }
            matchInfo = info
            localPlayer = info.yourPlayerID
            mapBounds = MapDatabase.mapOrDefault(info.mapID).bounds
            state = .inMatch
        case .snapshot:
            guard let snapshot = SnapshotCodec.decode(&reader, baseline: lastBaseline,
                                                      bounds: mapBounds) else {
                // Baseline desync: forget it and wait for a full snapshot.
                lastBaseline = nil
                return
            }
            lastBaseline = snapshot
            interpolation.insert(snapshot)
            reconcileLocalPlayer(with: snapshot)
        case .chatRelay:
            guard let message = NetChatMessage.decode(&reader) else { return }
            events.emit(.chat(player: message.sender, message: message.text,
                              teamOnly: message.teamOnly))
        case .pong:
            let sent = reader.readFloat()
            let sample = max(0, clientTime - sent)
            roundTripTime = MathUtil.damp(roundTripTime, sample, halfLife: 1.5, dt: 1)
        case .kick:
            let reason = reader.readString()
            onKicked?(reason)
            state = .failed
        case .matchEnd:
            handleMatchEnd(&reader)
        default:
            break
        }
    }

    private func reconcileLocalPlayer(with snapshot: WorldSnapshot) {
        guard let sim = predictedSimulation,
              let authoritative = snapshot.player(localPlayer),
              var player = sim.player(localPlayer) else { return }
        prediction.reconcile(player: &player, authoritative: authoritative,
                             acknowledgedSequence: sequence, world: sim.world,
                             events: events, now: sim.time)
        sim.mutatePlayer(localPlayer) { $0 = player }
    }

    private func handleMatchEnd(_ reader: inout BitReader) {
        _ = reader.read(bits: 2)
        _ = reader.readUInt16()
        _ = reader.readUInt16()
        let count = Int(reader.read(bits: 6))
        var xp: [PlayerID: Int] = [:]
        for _ in 0..<count {
            let id = PlayerID(rawValue: reader.readUInt8())
            _ = reader.readUInt16()
            _ = reader.readUInt16()
            _ = reader.readUInt16()
            xp[id] = Int(reader.readUInt16())
        }
        onMatchEnded?(xp)
    }

    // MARK: - Outgoing helpers

    public func sendChat(_ text: String, teamOnly: Bool) {
        let message = NetChatMessage(sender: localPlayer, text: text, teamOnly: teamOnly)
        transport?.send(message.encode(type: .chat), to: .host, reliable: true)
    }

    public func requestBuy(_ weapon: WeaponID) {
        var w = BitWriter(capacity: 32)
        w.write(NetMessageType.buyRequest.rawValue)
        w.write(string: weapon.value)
        transport?.send(w.finish(), to: .host, reliable: true)
    }

    public func requestTeam(_ team: Team) {
        var w = BitWriter(capacity: 8)
        w.write(NetMessageType.teamRequest.rawValue)
        w.write(UInt32(team.rawValue), bits: 2)
        transport?.send(w.finish(), to: .host, reliable: true)
    }

    /// Human-readable connection quality for the HUD.
    public var connectionQuality: ConnectionQuality {
        switch roundTripTime {
        case ..<0.06: return .excellent
        case ..<0.12: return .good
        case ..<0.2: return .fair
        default: return .poor
        }
    }
}

public enum ConnectionQuality: String, Sendable {
    case excellent, good, fair, poor

    public var bars: Int {
        switch self {
        case .excellent: return 4
        case .good: return 3
        case .fair: return 2
        case .poor: return 1
        }
    }

    public var colorHex: UInt32 {
        switch self {
        case .excellent, .good: return 0x4CAF50
        case .fair: return 0xFFB300
        case .poor: return 0xFF3D71
        }
    }
}
