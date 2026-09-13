import XCTest
@testable import CriticalStrikeCore

final class BitStreamTests: XCTestCase {
    func testRoundTripPrimitives() {
        var writer = BitWriter()
        writer.write(UInt32(0xDEADBEEF), bits: 32)
        writer.write(true)
        writer.write(false)
        writer.write(UInt32(37), bits: 6)
        writer.write(string: "Operator")
        writer.write(float: 3.14159)
        let data = writer.finish()

        var reader = BitReader(data: data)
        XCTAssertEqual(reader.read(bits: 32), 0xDEADBEEF)
        XCTAssertTrue(reader.readBool())
        XCTAssertFalse(reader.readBool())
        XCTAssertEqual(reader.read(bits: 6), 37)
        XCTAssertEqual(reader.readString(), "Operator")
        XCTAssertEqual(reader.readFloat(), 3.14159, accuracy: 0.00001)
        XCTAssertFalse(reader.failed)
    }

    func testQuantizationStaysWithinTolerance() {
        let bounds = AABB(min: Vec3(-50, -10, -50), max: Vec3(50, 30, 50))
        var writer = BitWriter()
        let original = Vec3(12.345, 3.21, -44.4)
        writer.write(position: original, bounds: bounds)
        var reader = BitReader(data: writer.finish())
        let decoded = reader.readPosition(bounds: bounds)
        // 16 bits over 100m is ~1.5mm; 14 bits over 40m is ~2.4mm.
        XCTAssertEqual(decoded.x, original.x, accuracy: 0.01)
        XCTAssertEqual(decoded.y, original.y, accuracy: 0.01)
        XCTAssertEqual(decoded.z, original.z, accuracy: 0.01)
    }

    func testAngleQuantizationIsBelowAimPrecision() {
        var writer = BitWriter()
        for angle in stride(from: Float(-3.1), through: 3.1, by: 0.13) {
            writer.write(angle: angle)
        }
        var reader = BitReader(data: writer.finish())
        for angle in stride(from: Float(-3.1), through: 3.1, by: 0.13) {
            // 12 bits over 2π is 0.0015 rad — well under one screen pixel at any FOV.
            XCTAssertEqual(reader.readAngle(), angle, accuracy: 0.002)
        }
    }

    func testReaderFailsGracefullyOnShortData() {
        var reader = BitReader(data: Data([0x01]))
        _ = reader.read(bits: 32)
        XCTAssertTrue(reader.failed)
    }
}

final class ProtocolTests: XCTestCase {
    func testInputCommandRoundTrip() {
        let original = InputCommand(tick: 12345, deltaTime: 0.0156,
                                    moveForward: 0.75, moveRight: -0.5,
                                    yaw: 1.23, pitch: -0.45,
                                    buttons: [.fire, .aim, .crouch],
                                    requestedSlot: .secondary, sequence: 999)
        var writer = BitWriter()
        original.encode(into: &writer)
        var reader = BitReader(data: writer.finish())
        guard let decoded = InputCommand.decode(from: &reader) else {
            return XCTFail("decode failed")
        }
        XCTAssertEqual(decoded.tick, original.tick)
        XCTAssertEqual(decoded.sequence, original.sequence)
        XCTAssertEqual(decoded.moveForward, original.moveForward, accuracy: 0.01)
        XCTAssertEqual(decoded.moveRight, original.moveRight, accuracy: 0.01)
        XCTAssertEqual(decoded.yaw, original.yaw, accuracy: 0.005)
        XCTAssertEqual(decoded.pitch, original.pitch, accuracy: 0.005)
        XCTAssertEqual(decoded.buttons, original.buttons)
        XCTAssertEqual(decoded.requestedSlot, .secondary)
    }

    func testHandshakeRoundTrip() {
        let handshake = NetHandshake(playerName: "Vector", accountID: "abc123",
                                     preferredTeam: .shield, loadoutHash: 42, clientBuild: 7)
        let data = handshake.encode()
        var reader = BitReader(data: data)
        XCTAssertEqual(reader.readUInt8(), NetMessageType.handshake.rawValue)
        guard let decoded = NetHandshake.decode(&reader) else { return XCTFail("decode failed") }
        XCTAssertEqual(decoded.playerName, "Vector")
        XCTAssertEqual(decoded.accountID, "abc123")
        XCTAssertEqual(decoded.preferredTeam, .shield)
        XCTAssertTrue(decoded.isCompatible)
    }

    func testInputPacketCarriesRedundantCommands() {
        let commands = (0..<12).map { index in
            InputCommand(tick: UInt32(index), sequence: UInt16(index))
        }
        let packet = NetInputPacket(commands: commands, lastAcknowledgedSnapshot: 77, clientTime: 1.5)
        var reader = BitReader(data: packet.encode())
        XCTAssertEqual(reader.readUInt8(), NetMessageType.input.rawValue)
        guard let decoded = NetInputPacket.decode(&reader) else { return XCTFail("decode failed") }
        // Only the most recent eight are sent — enough to survive a burst of loss without
        // bloating the packet.
        XCTAssertEqual(decoded.commands.count, 8)
        XCTAssertEqual(decoded.commands.last?.sequence, 11)
        XCTAssertEqual(decoded.lastAcknowledgedSnapshot, 77)
    }

    func testChatIsSanitized() {
        XCTAssertFalse(ChatFilter.sanitize("visit https://spam.example").contains("https://"))
        XCTAssertEqual(ChatFilter.sanitize("aaaaaaaaaaaaaa").count, 4)
        XCTAssertLessThanOrEqual(ChatFilter.sanitize(String(repeating: "x", count: 500)).count, 120)
    }
}

final class SnapshotTests: XCTestCase {
    private func makeSnapshot(tick: UInt32, playerCount: Int, offset: Float) -> WorldSnapshot {
        let players = (0..<playerCount).map { index in
            PlayerSnapshot(id: PlayerID(index), team: index % 2 == 0 ? .strike : .shield,
                           position: Vec3(Float(index) + offset, 0.1, -Float(index)),
                           velocity: Vec3(1, 0, 0), yaw: 0.5, pitch: -0.1,
                           health: 100, armor: 50, isAlive: true, stance: .standing,
                           weapon: "ar_vanguard", ammoInMagazine: 30,
                           isFiring: false, isReloading: false, isAiming: false,
                           kills: UInt8(index), deaths: 0, score: UInt16(index * 100))
        }
        return WorldSnapshot(tick: tick, serverTime: Float(tick) / 64, phase: .live,
                             phaseTimeRemaining: 120, strikeScore: 3, shieldScore: 5, round: 1,
                             players: players, projectiles: [], bombPlanted: false,
                             bombPosition: .zero, bombTimeRemaining: 0)
    }

    func testFullSnapshotRoundTrip() {
        let bounds = MapDatabase.vault.bounds
        let snapshot = makeSnapshot(tick: 100, playerCount: 10, offset: 0)
        let data = SnapshotCodec.encode(snapshot, baseline: nil, bounds: bounds)
        var reader = BitReader(data: data)
        XCTAssertEqual(reader.readUInt8(), NetMessageType.snapshot.rawValue)
        guard let decoded = SnapshotCodec.decode(&reader, baseline: nil, bounds: bounds) else {
            return XCTFail("decode failed")
        }
        XCTAssertEqual(decoded.tick, 100)
        XCTAssertEqual(decoded.players.count, 10)
        XCTAssertEqual(decoded.strikeScore, 3)
        XCTAssertEqual(decoded.players[3].kills, 3)
        XCTAssertEqual(decoded.players[3].position.x, snapshot.players[3].position.x, accuracy: 0.01)
    }

    func testDeltaEncodingIsSmallerThanFull() {
        let bounds = MapDatabase.vault.bounds
        let baseline = makeSnapshot(tick: 100, playerCount: 10, offset: 0)
        // Only a tiny change between frames, which is the common case.
        let next = makeSnapshot(tick: 101, playerCount: 10, offset: 0.02)

        let full = SnapshotCodec.encode(next, baseline: nil, bounds: bounds)
        let delta = SnapshotCodec.encode(next, baseline: baseline, bounds: bounds)
        XCTAssertLessThan(delta.count, full.count,
                          "Delta compression did not reduce the packet size")
    }

    func testDeltaDecodesAgainstItsBaseline() {
        let bounds = MapDatabase.vault.bounds
        let baseline = makeSnapshot(tick: 100, playerCount: 6, offset: 0)
        var next = makeSnapshot(tick: 101, playerCount: 6, offset: 0)
        next.players[2].health = 40
        next.players[2].position = Vec3(9, 0.1, -9)

        let data = SnapshotCodec.encode(next, baseline: baseline, bounds: bounds)
        var reader = BitReader(data: data)
        _ = reader.readUInt8()
        guard let decoded = SnapshotCodec.decode(&reader, baseline: baseline, bounds: bounds) else {
            return XCTFail("decode failed")
        }
        XCTAssertEqual(decoded.players[2].health, 40)
        XCTAssertEqual(decoded.players[2].position.x, 9, accuracy: 0.01)
        // Unchanged players must still carry their baseline values.
        XCTAssertEqual(decoded.players[0].health, 100)
    }

    func testSnapshotInterpolationIsMonotonic() {
        let a = makeSnapshot(tick: 0, playerCount: 2, offset: 0).players[0]
        var b = a
        b.position = Vec3(10, 0, 0)
        let mid = a.interpolated(to: b, t: 0.5)
        XCTAssertEqual(mid.position.x, 5, accuracy: 0.001)
        XCTAssertEqual(a.interpolated(to: b, t: 0).position.x, 0, accuracy: 0.001)
        XCTAssertEqual(a.interpolated(to: b, t: 1).position.x, 10, accuracy: 0.001)
    }

    func testExtrapolationIsBounded() {
        var snapshot = makeSnapshot(tick: 0, playerCount: 1, offset: 0).players[0]
        snapshot.velocity = Vec3(100, 0, 0)
        // Even a two-second stall must not fling the player 200m.
        let extrapolated = snapshot.extrapolated(by: 2.0)
        XCTAssertLessThanOrEqual(extrapolated.position.x - snapshot.position.x, 20.1)
    }
}

final class InterpolationBufferTests: XCTestCase {
    func testBufferPlaysBackInOrder() {
        let buffer = InterpolationBuffer()
        buffer.interpolationDelay = 0.1
        for tick in 0..<10 {
            var snapshot = WorldSnapshot(tick: UInt32(tick), serverTime: Float(tick) * 0.05,
                                         phase: .live, phaseTimeRemaining: 0,
                                         strikeScore: 0, shieldScore: 0, round: 1,
                                         players: [], projectiles: [], bombPlanted: false,
                                         bombPosition: .zero, bombTimeRemaining: 0)
            snapshot.players = [PlayerSnapshot(id: PlayerID(0), team: .strike,
                                               position: Vec3(Float(tick), 0, 0), velocity: .zero,
                                               yaw: 0, pitch: 0, health: 100, armor: 0,
                                               isAlive: true, stance: .standing,
                                               weapon: "ar_vanguard", ammoInMagazine: 30,
                                               isFiring: false, isReloading: false, isAiming: false,
                                               kills: 0, deaths: 0, score: 0)]
            buffer.insert(snapshot)
        }
        let sampled = buffer.sample()
        XCTAssertNotNil(sampled)
        XCTAssertEqual(sampled?.players.count, 1)
    }

    func testOutOfOrderSnapshotsAreDropped() {
        let buffer = InterpolationBuffer()
        let makeSnapshot: (UInt32) -> WorldSnapshot = { tick in
            WorldSnapshot(tick: tick, serverTime: Float(tick) * 0.05, phase: .live,
                          phaseTimeRemaining: 0, strikeScore: 0, shieldScore: 0, round: 1,
                          players: [], projectiles: [], bombPlanted: false,
                          bombPosition: .zero, bombTimeRemaining: 0)
        }
        buffer.insert(makeSnapshot(10))
        buffer.insert(makeSnapshot(5))    // late arrival
        XCTAssertEqual(buffer.snapshots.count, 1)
        XCTAssertEqual(buffer.snapshots.first?.tick, 10)
    }
}

final class LagCompensationTests: XCTestCase {
    func testRewindFindsAPastPosition() {
        let sim = MatchSimulation(map: MapDatabase.vault,
                                  mode: GameModeDatabase.mode(.teamDeathmatch), seed: 3)
        let mover = sim.addPlayer(name: "M", team: .shield, isBot: false, loadout: Loadout.starter())
        let shooter = sim.addPlayer(name: "S", team: .strike, isBot: false, loadout: Loadout.starter())
        sim.respawn(mover, force: true)
        sim.respawn(shooter, force: true)

        let compensator = LagCompensator()
        // Walk the target along +X, recording a frame each tick.
        for index in 0..<64 {
            sim.mutatePlayer(mover) { $0.position = Vec3(Float(index) * 0.1, 0, 0) }
            sim.step(deltaTime: GameClock.tickInterval)
            compensator.record(sim: sim)
        }
        let present = compensator.rewind(latency: 0, now: sim.time, excluding: shooter)
        let past = compensator.rewind(latency: 0.2, now: sim.time, excluding: shooter)

        let presentX = present.first { $0.player == mover }?.position.x ?? 0
        let pastX = past.first { $0.player == mover }?.position.x ?? 0
        XCTAssertGreaterThan(presentX, pastX, "Rewind did not move the target back in time")
    }

    func testRewindIsCapped() {
        let amount = LagCompensator.rewindAmount(roundTripTime: 5, interpolationDelay: 2)
        XCTAssertLessThanOrEqual(amount, LagCompensator.maxRewindSeconds)
    }
}

final class AntiCheatTests: XCTestCase {
    private func makePlayer() -> PlayerState {
        var player = PlayerState(id: PlayerID(0), name: "T", team: .strike, isBot: false,
                                 loadout: Loadout.starter())
        player.isAlive = true
        return player
    }

    func testAcceptsNormalInput() {
        let antiCheat = AntiCheat()
        let sim = MatchSimulation(map: MapDatabase.vault,
                                  mode: GameModeDatabase.mode(.teamDeathmatch))
        let command = InputCommand(deltaTime: GameClock.tickInterval, moveForward: 1, moveRight: 0.3)
        XCTAssertTrue(antiCheat.validate(command: command, player: makePlayer(), sim: sim).accepted)
    }

    func testRejectsOutOfRangeMovement() {
        let antiCheat = AntiCheat()
        let sim = MatchSimulation(map: MapDatabase.vault,
                                  mode: GameModeDatabase.mode(.teamDeathmatch))
        let command = InputCommand(deltaTime: GameClock.tickInterval, moveForward: 12)
        XCTAssertFalse(antiCheat.validate(command: command, player: makePlayer(), sim: sim).accepted)
    }

    func testRejectsImplausibleTimestep() {
        let antiCheat = AntiCheat()
        let sim = MatchSimulation(map: MapDatabase.vault,
                                  mode: GameModeDatabase.mode(.teamDeathmatch))
        let command = InputCommand(deltaTime: 0.9, moveForward: 1)
        XCTAssertFalse(antiCheat.validate(command: command, player: makePlayer(), sim: sim).accepted)
    }

    func testRejectsSustainedAimSnapping() {
        let antiCheat = AntiCheat()
        let sim = MatchSimulation(map: MapDatabase.vault,
                                  mode: GameModeDatabase.mode(.teamDeathmatch))
        let player = makePlayer()
        var rejected = false
        for index in 0..<40 {
            // Flip 180° every single tick — impossible on a touch screen.
            let command = InputCommand(deltaTime: GameClock.tickInterval,
                                       yaw: index % 2 == 0 ? 0 : .pi)
            if !antiCheat.validate(command: command, player: player, sim: sim).accepted {
                rejected = true
                break
            }
        }
        XCTAssertTrue(rejected, "Sustained aim snapping was never rejected")
    }

    func testRejectsNonFiniteInput() {
        let antiCheat = AntiCheat()
        let sim = MatchSimulation(map: MapDatabase.vault,
                                  mode: GameModeDatabase.mode(.teamDeathmatch))
        let command = InputCommand(deltaTime: GameClock.tickInterval, moveForward: .nan)
        XCTAssertFalse(antiCheat.validate(command: command, player: makePlayer(), sim: sim).accepted)
    }
}

final class TransportTests: XCTestCase {
    func testLoopbackDeliversWithLatency() {
        let (a, b) = LoopbackTransport.pair()
        a.latency = 0.05
        var received: Data?
        b.onData = { _, data in received = data }

        a.send(Data([1, 2, 3]), to: .host, reliable: true)
        b.pump(dt: 0.02)
        XCTAssertNil(received, "Packet arrived before its latency elapsed")
        b.pump(dt: 0.05)
        XCTAssertEqual(received, Data([1, 2, 3]))
    }
}
