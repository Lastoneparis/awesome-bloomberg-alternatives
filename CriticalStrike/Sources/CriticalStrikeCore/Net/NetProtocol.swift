import Foundation

public enum NetConnectionState: String, Sendable {
    case disconnected, resolving, connecting, authenticating, connected, inMatch, reconnecting, failed

    public var isUsable: Bool { self == .connected || self == .inMatch }
}

public enum NetMessageType: UInt8, Sendable {
    // Client → server
    case handshake = 1
    case input = 2
    case chat = 3
    case loadoutChange = 4
    case teamRequest = 5
    case buyRequest = 6
    case ping = 7
    case voiceLine = 8
    case mapPing = 9
    case ready = 10
    case leave = 11

    // Server → client
    case handshakeAck = 64
    case matchInfo = 65
    case snapshot = 66
    case events = 67
    case chatRelay = 68
    case playerJoined = 69
    case playerLeft = 70
    case matchEnd = 71
    case pong = 72
    case kick = 73
    case correction = 74
}

public struct NetHandshake: Sendable {
    public var protocolVersion: UInt16
    public var playerName: String
    public var accountID: String
    public var preferredTeam: Team
    public var loadoutHash: UInt32
    public var clientBuild: UInt16

    public static let currentProtocolVersion: UInt16 = 7

    public init(playerName: String, accountID: String, preferredTeam: Team = .none,
                loadoutHash: UInt32 = 0, clientBuild: UInt16 = 1) {
        self.protocolVersion = NetHandshake.currentProtocolVersion
        self.playerName = playerName; self.accountID = accountID
        self.preferredTeam = preferredTeam; self.loadoutHash = loadoutHash
        self.clientBuild = clientBuild
    }

    public func encode() -> Data {
        var w = BitWriter(capacity: 64)
        w.write(NetMessageType.handshake.rawValue)
        w.write(protocolVersion)
        w.write(string: playerName)
        w.write(string: accountID)
        w.write(UInt32(preferredTeam.rawValue), bits: 2)
        w.write(loadoutHash, bits: 32)
        w.write(clientBuild)
        return w.finish()
    }

    public static func decode(_ reader: inout BitReader) -> NetHandshake? {
        let version = reader.readUInt16()
        let name = reader.readString()
        let account = reader.readString()
        let team = Team(rawValue: UInt8(reader.read(bits: 2))) ?? .none
        let hash = reader.readUInt32()
        let build = reader.readUInt16()
        guard !reader.failed else { return nil }
        var h = NetHandshake(playerName: name, accountID: account, preferredTeam: team,
                             loadoutHash: hash, clientBuild: build)
        h.protocolVersion = version
        return h
    }

    public var isCompatible: Bool { protocolVersion == NetHandshake.currentProtocolVersion }
}

public struct NetMatchInfo: Sendable {
    public var mapID: MapID
    public var mode: GameModeKind
    public var yourPlayerID: PlayerID
    public var serverTick: UInt32
    public var tickRate: UInt8

    public init(mapID: MapID, mode: GameModeKind, yourPlayerID: PlayerID,
                serverTick: UInt32, tickRate: UInt8 = UInt8(GameClock.tickRate)) {
        self.mapID = mapID; self.mode = mode; self.yourPlayerID = yourPlayerID
        self.serverTick = serverTick; self.tickRate = tickRate
    }

    public func encode() -> Data {
        var w = BitWriter(capacity: 48)
        w.write(NetMessageType.matchInfo.rawValue)
        w.write(string: mapID.value)
        w.write(string: mode.rawValue)
        w.write(yourPlayerID.rawValue)
        w.write(serverTick, bits: 32)
        w.write(tickRate)
        return w.finish()
    }

    public static func decode(_ reader: inout BitReader) -> NetMatchInfo? {
        let map = reader.readString()
        let modeRaw = reader.readString()
        let pid = reader.readUInt8()
        let tick = reader.readUInt32()
        let rate = reader.readUInt8()
        guard !reader.failed, let mode = GameModeKind(rawValue: modeRaw) else { return nil }
        return NetMatchInfo(mapID: MapID(map), mode: mode, yourPlayerID: PlayerID(rawValue: pid),
                            serverTick: tick, tickRate: rate)
    }
}

public extension InputCommand {
    /// Inputs are sent unreliably and redundantly: each packet carries the last few
    /// commands so a single dropped datagram never stalls the server's view of you.
    func encode(into w: inout BitWriter) {
        w.write(tick, bits: 32)
        w.write(sequence)
        w.write(quantized: deltaTime, min: 0, max: 0.1, bits: 8)
        w.write(quantized: moveForward, min: -1, max: 1, bits: 8)
        w.write(quantized: moveRight, min: -1, max: 1, bits: 8)
        w.write(angle: yaw)
        w.write(quantized: pitch, min: -ViewAngles.maxPitch, max: ViewAngles.maxPitch, bits: 12)
        w.write(UInt32(buttons.rawValue), bits: 13)
        if let slot = requestedSlot {
            w.write(true)
            w.write(UInt32(slot.rawValue), bits: 3)
        } else {
            w.write(false)
        }
    }

    static func decode(from r: inout BitReader) -> InputCommand? {
        let tick = r.readUInt32()
        let sequence = r.readUInt16()
        let dt = r.readQuantized(min: 0, max: 0.1, bits: 8)
        let forward = r.readQuantized(min: -1, max: 1, bits: 8)
        let right = r.readQuantized(min: -1, max: 1, bits: 8)
        let yaw = r.readAngle()
        let pitch = r.readQuantized(min: -ViewAngles.maxPitch, max: ViewAngles.maxPitch, bits: 12)
        let buttons = InputButtons(rawValue: UInt16(r.read(bits: 13)))
        var slot: LoadoutSlot?
        if r.readBool() {
            slot = LoadoutSlot(rawValue: UInt8(r.read(bits: 3)))
        }
        guard !r.failed else { return nil }
        return InputCommand(tick: tick, deltaTime: dt, moveForward: forward, moveRight: right,
                            yaw: yaw, pitch: pitch, buttons: buttons,
                            requestedSlot: slot, sequence: sequence).sanitized()
    }
}

public struct NetInputPacket: Sendable {
    public var commands: [InputCommand]
    public var lastAcknowledgedSnapshot: UInt32
    public var clientTime: Float

    public init(commands: [InputCommand], lastAcknowledgedSnapshot: UInt32, clientTime: Float) {
        self.commands = commands
        self.lastAcknowledgedSnapshot = lastAcknowledgedSnapshot
        self.clientTime = clientTime
    }

    public func encode() -> Data {
        var w = BitWriter(capacity: 128)
        w.write(NetMessageType.input.rawValue)
        w.write(lastAcknowledgedSnapshot, bits: 32)
        w.write(float: clientTime)
        let sent = commands.suffix(8)
        w.write(UInt32(sent.count), bits: 4)
        for c in sent { c.encode(into: &w) }
        return w.finish()
    }

    public static func decode(_ reader: inout BitReader) -> NetInputPacket? {
        let ack = reader.readUInt32()
        let clientTime = reader.readFloat()
        let count = Int(reader.read(bits: 4))
        var commands: [InputCommand] = []
        commands.reserveCapacity(count)
        for _ in 0..<count {
            guard let c = InputCommand.decode(from: &reader) else { return nil }
            commands.append(c)
        }
        guard !reader.failed else { return nil }
        return NetInputPacket(commands: commands, lastAcknowledgedSnapshot: ack, clientTime: clientTime)
    }
}

public struct NetChatMessage: Sendable {
    public var sender: PlayerID
    public var text: String
    public var teamOnly: Bool

    public init(sender: PlayerID, text: String, teamOnly: Bool) {
        self.sender = sender; self.text = text; self.teamOnly = teamOnly
    }

    public func encode(type: NetMessageType) -> Data {
        var w = BitWriter(capacity: 64)
        w.write(type.rawValue)
        w.write(sender.rawValue)
        w.write(teamOnly)
        w.write(string: String(text.prefix(31)))
        return w.finish()
    }

    public static func decode(_ reader: inout BitReader) -> NetChatMessage? {
        let sender = reader.readUInt8()
        let teamOnly = reader.readBool()
        let text = reader.readString()
        guard !reader.failed else { return nil }
        return NetChatMessage(sender: PlayerID(rawValue: sender), text: text, teamOnly: teamOnly)
    }
}
