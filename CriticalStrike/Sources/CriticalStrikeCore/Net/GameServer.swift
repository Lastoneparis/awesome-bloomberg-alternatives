import Foundation

/// Authoritative match host. Owns the one true `MatchSimulation`, consumes client inputs,
/// runs bots, and broadcasts delta-compressed snapshots at `GameClock.snapshotRate`.
///
/// It never trusts a client for anything except intent: movement, aim and button presses
/// are re-simulated here, and hits are resolved against lag-compensated volumes the server
/// itself recorded.
public final class GameServer {
    public struct Client {
        public var peer: PeerID
        public var player: PlayerID
        public var name: String
        public var accountID: String
        public var lastAcknowledgedSnapshot: UInt32 = 0
        public var lastInputSequence: UInt16 = 0
        public var roundTripTime: Float = 0.08
        public var lastPacketTime: Float = 0
        public var baseline: WorldSnapshot?
        public var strikes: Int = 0          // anti-cheat violations
    }

    public let sim: MatchSimulation
    public let botDirector: BotDirector
    public private(set) var clients: [PeerID: Client] = [:]
    public var transport: NetTransport?
    public var onMatchEnded: ((MatchResult) -> Void)?
    public var maxViolationsBeforeKick = 5

    private let lagCompensator = LagCompensator()
    private let antiCheat = AntiCheat()
    private var snapshotAccumulator: Float = 0
    private var clock = GameClock()

    public init(map: MapData, mode: GameModeData, botDifficulty: BotDifficulty = .regular,
                seed: UInt64 = 0xC0FFEE) {
        sim = MatchSimulation(map: map, mode: mode, seed: seed)
        botDirector = BotDirector(difficulty: botDifficulty, seed: seed &+ 1)
        sim.onMatchEnded = { [weak self] result in
            self?.broadcastMatchEnd(result)
            self?.onMatchEnded?(result)
        }
    }

    public func attach(transport: NetTransport) {
        self.transport = transport
        transport.onData = { [weak self] peer, data in self?.receive(data, from: peer) }
        transport.onPeerDisconnected = { [weak self] peer in self?.dropClient(peer) }
    }

    public func fillWithBots() {
        botDirector.fillMatch(sim)
    }

    // MARK: - Frame

    /// Advances the server by real elapsed time, running whole simulation ticks.
    public func update(deltaTime: Float) {
        let steps = clock.advance(deltaTime: deltaTime)
        for _ in 0..<steps {
            clock.consumeTick()
            botDirector.step(sim: sim, dt: GameClock.tickInterval)
            sim.step(deltaTime: GameClock.tickInterval)
            lagCompensator.record(sim: sim)
        }

        snapshotAccumulator += deltaTime
        let snapshotInterval = 1.0 / Float(GameClock.snapshotRate)
        if snapshotAccumulator >= snapshotInterval {
            snapshotAccumulator -= snapshotInterval
            broadcastSnapshots()
        }
        // Drop clients that stopped talking.
        for (peer, client) in clients where sim.time - client.lastPacketTime > 20 {
            Log.info("Client \(client.name) timed out", category: "net")
            dropClient(peer)
        }
    }

    // MARK: - Receiving

    private func receive(_ data: Data, from peer: PeerID) {
        var reader = BitReader(data: data)
        let typeRaw = reader.readUInt8()
        guard let type = NetMessageType(rawValue: typeRaw) else { return }

        switch type {
        case .handshake:
            guard let handshake = NetHandshake.decode(&reader) else { return }
            accept(handshake, from: peer)
        case .input:
            guard let packet = NetInputPacket.decode(&reader) else { return }
            apply(packet, from: peer)
        case .chat:
            guard let message = NetChatMessage.decode(&reader) else { return }
            relayChat(message, from: peer)
        case .buyRequest:
            guard let client = clients[peer] else { return }
            let weapon = WeaponID(reader.readString())
            _ = sim.buy(client.player, weapon: weapon)
        case .teamRequest:
            guard let client = clients[peer] else { return }
            let team = Team(rawValue: UInt8(reader.read(bits: 2))) ?? .none
            sim.setTeam(client.player, team: team)
        case .ping:
            var w = BitWriter(capacity: 16)
            w.write(NetMessageType.pong.rawValue)
            w.write(float: reader.readFloat())
            transport?.send(w.finish(), to: peer, reliable: false)
        case .leave:
            dropClient(peer)
        default:
            break
        }
        clients[peer]?.lastPacketTime = sim.time
    }

    private func accept(_ handshake: NetHandshake, from peer: PeerID) {
        guard handshake.isCompatible else {
            var w = BitWriter(capacity: 32)
            w.write(NetMessageType.kick.rawValue)
            w.write(string: "Version mismatch")
            transport?.send(w.finish(), to: peer, reliable: true)
            transport?.disconnect(peer)
            return
        }
        // Take a bot's slot so the roster size stays constant.
        let team = pickTeam(preferred: handshake.preferredTeam)
        _ = botDirector.makeRoomForHuman(sim, team: team)
        let playerID = sim.addPlayer(name: handshake.playerName, team: team,
                                     isBot: false, loadout: Loadout.starter())
        clients[peer] = Client(peer: peer, player: playerID, name: handshake.playerName,
                               accountID: handshake.accountID, lastPacketTime: sim.time)

        var ack = BitWriter(capacity: 16)
        ack.write(NetMessageType.handshakeAck.rawValue)
        ack.write(playerID.rawValue)
        transport?.send(ack.finish(), to: peer, reliable: true)

        let info = NetMatchInfo(mapID: sim.map.id, mode: sim.state.mode.kind,
                                yourPlayerID: playerID, serverTick: sim.tick)
        transport?.send(info.encode(), to: peer, reliable: true)
        Log.info("Client \(handshake.playerName) joined as \(playerID.rawValue)", category: "net")
    }

    private func pickTeam(preferred: Team) -> Team {
        guard sim.state.mode.kind.isTeamBased else { return .none }
        let strike = sim.teamCount(.strike)
        let shield = sim.teamCount(.shield)
        if preferred != .none {
            let count = preferred == .strike ? strike : shield
            if count < sim.state.mode.teamSize { return preferred }
        }
        return strike <= shield ? .strike : .shield
    }

    private func apply(_ packet: NetInputPacket, from peer: PeerID) {
        guard var client = clients[peer] else { return }
        client.lastAcknowledgedSnapshot = packet.lastAcknowledgedSnapshot

        for command in packet.commands {
            // Ignore commands the server already consumed (they are resent for redundancy).
            guard sequenceIsNewer(command.sequence, client.lastInputSequence) else { continue }
            client.lastInputSequence = command.sequence

            if let player = sim.player(client.player) {
                let verdict = antiCheat.validate(command: command, player: player, sim: sim)
                if !verdict.accepted {
                    client.strikes += 1
                    Log.warn("Rejected input from \(client.name): \(verdict.reason)", category: "anticheat")
                    if client.strikes >= maxViolationsBeforeKick {
                        clients[peer] = client
                        kick(peer, reason: "Invalid input")
                        return
                    }
                    continue
                }
            }
            sim.setInput(command, for: client.player)
        }
        clients[peer] = client
    }

    private func relayChat(_ message: NetChatMessage, from peer: PeerID) {
        guard let client = clients[peer] else { return }
        let relay = NetChatMessage(sender: client.player,
                                   text: ChatFilter.sanitize(message.text),
                                   teamOnly: message.teamOnly)
        let data = relay.encode(type: .chatRelay)
        if message.teamOnly, let senderTeam = sim.player(client.player)?.team {
            for (otherPeer, other) in clients where sim.player(other.player)?.team == senderTeam {
                transport?.send(data, to: otherPeer, reliable: true)
            }
        } else {
            for otherPeer in clients.keys { transport?.send(data, to: otherPeer, reliable: true) }
        }
        sim.events.emit(.chat(player: client.player, message: relay.text, teamOnly: relay.teamOnly))
    }

    // MARK: - Sending

    private func broadcastSnapshots() {
        guard let transport else { return }
        let snapshot = WorldSnapshot(from: sim)
        for (peer, storedClient) in clients {
            var client = storedClient
            let data = SnapshotCodec.encode(snapshot, baseline: client.baseline, bounds: sim.map.bounds)
            transport.send(data, to: peer, reliable: false)
            // The baseline only advances once the client acknowledges it.
            if client.lastAcknowledgedSnapshot >= (client.baseline?.tick ?? 0) {
                client.baseline = snapshot
            }
            clients[peer] = client
        }
    }

    private func broadcastMatchEnd(_ result: MatchResult) {
        guard let transport else { return }
        var w = BitWriter(capacity: 128)
        w.write(NetMessageType.matchEnd.rawValue)
        w.write(UInt32(result.winner.rawValue), bits: 2)
        w.write(UInt16(MathUtil.clamp(result.strikeScore, 0, 65535)))
        w.write(UInt16(MathUtil.clamp(result.shieldScore, 0, 65535)))
        w.write(UInt32(result.results.count), bits: 6)
        for r in result.results {
            w.write(r.player.rawValue)
            w.write(UInt16(MathUtil.clamp(r.kills, 0, 65535)))
            w.write(UInt16(MathUtil.clamp(r.deaths, 0, 65535)))
            w.write(UInt16(MathUtil.clamp(r.score, 0, 65535)))
            w.write(UInt16(MathUtil.clamp(r.xpEarned, 0, 65535)))
        }
        transport.broadcast(w.finish(), reliable: true)
    }

    public func kick(_ peer: PeerID, reason: String) {
        var w = BitWriter(capacity: 32)
        w.write(NetMessageType.kick.rawValue)
        w.write(string: reason)
        transport?.send(w.finish(), to: peer, reliable: true)
        dropClient(peer)
    }

    private func dropClient(_ peer: PeerID) {
        guard let client = clients[peer] else { return }
        sim.removePlayer(client.player)
        clients[peer] = nil
        transport?.disconnect(peer)
        // Backfill with a bot so the match stays full.
        if sim.state.mode.kind.isTeamBased {
            let team: Team = sim.teamCount(.strike) <= sim.teamCount(.shield) ? .strike : .shield
            botDirector.addBot(to: sim, team: team)
        }
    }

    /// Resolves a shot using the shooter's rewound view of the world.
    public func compensatedTargets(for player: PlayerID, roundTripTime: Float,
                                   interpolationDelay: Float) -> [HitVolume] {
        let rewind = LagCompensator.rewindAmount(roundTripTime: roundTripTime,
                                                 interpolationDelay: interpolationDelay)
        return lagCompensator.rewind(latency: rewind, now: sim.time, excluding: player)
    }

    private func sequenceIsNewer(_ a: UInt16, _ b: UInt16) -> Bool {
        Int16(bitPattern: a &- b) > 0
    }
}

/// Minimal profanity/spam guard. A shipping build would call a moderation service, but the
/// client still needs a local pass so nothing unfiltered is ever rendered.
public enum ChatFilter {
    private static let blocked = ["<script", "http://", "https://"]

    public static func sanitize(_ text: String) -> String {
        var out = text.trimmingCharacters(in: .whitespacesAndNewlines)
        out = String(out.prefix(120))
        for token in blocked {
            out = out.replacingOccurrences(of: token, with: "***", options: .caseInsensitive)
        }
        // Collapse spam like "aaaaaaaaaaa".
        var collapsed = ""
        var lastChar: Character?
        var repeatCount = 0
        for ch in out {
            if ch == lastChar {
                repeatCount += 1
                if repeatCount >= 4 { continue }
            } else {
                repeatCount = 0
                lastChar = ch
            }
            collapsed.append(ch)
        }
        return collapsed
    }
}
