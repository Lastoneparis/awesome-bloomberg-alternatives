import Foundation

/// Compact per-player state broadcast to clients. This is deliberately much smaller than
/// `PlayerState`: clients only need what they can see or render.
public struct PlayerSnapshot: Sendable, Equatable {
    public var id: PlayerID
    public var team: Team
    public var position: Vec3
    public var velocity: Vec3
    public var yaw: Float
    public var pitch: Float
    public var health: UInt8
    public var armor: UInt8
    public var isAlive: Bool
    public var stance: Stance
    public var weapon: WeaponID
    public var ammoInMagazine: UInt8
    public var isFiring: Bool
    public var isReloading: Bool
    public var isAiming: Bool
    public var kills: UInt8
    public var deaths: UInt8
    public var score: UInt16

    public init(from player: PlayerState) {
        id = player.id
        team = player.team
        position = player.position
        velocity = player.velocity
        yaw = player.angles.yaw
        pitch = player.angles.pitch
        health = UInt8(MathUtil.clamp(Int(player.health), 0, 255))
        armor = UInt8(MathUtil.clamp(Int(player.armor), 0, 255))
        isAlive = player.isAlive
        stance = player.stance
        weapon = player.slots[player.activeSlot]?.build.weapon ?? WeaponDatabase.defaultMelee
        ammoInMagazine = UInt8(MathUtil.clamp(player.slots[player.activeSlot]?.ammoInMagazine ?? 0, 0, 255))
        isFiring = player.action == .firing
        isReloading = player.action == .reloading
        isAiming = player.isAiming
        kills = UInt8(MathUtil.clamp(player.kills, 0, 255))
        deaths = UInt8(MathUtil.clamp(player.deaths, 0, 255))
        score = UInt16(MathUtil.clamp(player.score, 0, 65535))
    }

    public init(id: PlayerID, team: Team, position: Vec3, velocity: Vec3, yaw: Float, pitch: Float,
                health: UInt8, armor: UInt8, isAlive: Bool, stance: Stance, weapon: WeaponID,
                ammoInMagazine: UInt8, isFiring: Bool, isReloading: Bool, isAiming: Bool,
                kills: UInt8, deaths: UInt8, score: UInt16) {
        self.id = id; self.team = team; self.position = position; self.velocity = velocity
        self.yaw = yaw; self.pitch = pitch; self.health = health; self.armor = armor
        self.isAlive = isAlive; self.stance = stance; self.weapon = weapon
        self.ammoInMagazine = ammoInMagazine; self.isFiring = isFiring
        self.isReloading = isReloading; self.isAiming = isAiming
        self.kills = kills; self.deaths = deaths; self.score = score
    }

    /// Linear interpolation for rendering other players between snapshots.
    public func interpolated(to other: PlayerSnapshot, t: Float) -> PlayerSnapshot {
        var out = other
        out.position = position.lerp(other.position, t)
        out.velocity = velocity.lerp(other.velocity, t)
        out.yaw = MathUtil.lerpAngle(yaw, other.yaw, t)
        out.pitch = MathUtil.lerp(pitch, other.pitch, t)
        return out
    }

    /// Dead-reckoning when the next snapshot has not arrived yet. Capped hard so a
    /// stalled connection never sends players sliding through walls.
    public func extrapolated(by seconds: Float) -> PlayerSnapshot {
        var out = self
        let clamped = min(seconds, 0.2)
        out.position = position + velocity * clamped
        return out
    }
}

public struct ProjectileSnapshot: Sendable {
    public var entity: EntityID
    public var kind: GrenadeKind
    public var position: Vec3
    public var velocity: Vec3
}

public struct WorldSnapshot: Sendable {
    public var tick: UInt32
    public var serverTime: Float
    public var phase: MatchPhase
    public var phaseTimeRemaining: Float
    public var strikeScore: UInt16
    public var shieldScore: UInt16
    public var round: UInt8
    public var players: [PlayerSnapshot]
    public var projectiles: [ProjectileSnapshot]
    public var bombPlanted: Bool
    public var bombPosition: Vec3
    public var bombTimeRemaining: Float

    public init(tick: UInt32, serverTime: Float, phase: MatchPhase, phaseTimeRemaining: Float,
                strikeScore: UInt16, shieldScore: UInt16, round: UInt8,
                players: [PlayerSnapshot], projectiles: [ProjectileSnapshot],
                bombPlanted: Bool, bombPosition: Vec3, bombTimeRemaining: Float) {
        self.tick = tick; self.serverTime = serverTime; self.phase = phase
        self.phaseTimeRemaining = phaseTimeRemaining; self.strikeScore = strikeScore
        self.shieldScore = shieldScore; self.round = round; self.players = players
        self.projectiles = projectiles; self.bombPlanted = bombPlanted
        self.bombPosition = bombPosition; self.bombTimeRemaining = bombTimeRemaining
    }

    public init(from sim: MatchSimulation) {
        tick = sim.tick
        serverTime = sim.time
        phase = sim.state.phase
        phaseTimeRemaining = sim.state.phaseTimer.remaining
        strikeScore = UInt16(MathUtil.clamp(sim.state.score(.strike), 0, 65535))
        shieldScore = UInt16(MathUtil.clamp(sim.state.score(.shield), 0, 65535))
        round = UInt8(MathUtil.clamp(sim.state.round, 0, 255))
        players = sim.allPlayers().map(PlayerSnapshot.init(from:))
        projectiles = sim.projectiles.projectiles.map {
            ProjectileSnapshot(entity: $0.entity, kind: $0.kind,
                               position: $0.position, velocity: $0.velocity)
        }
        bombPlanted = sim.state.bomb.isPlanted && !sim.state.bomb.isDefused
        bombPosition = sim.state.bomb.position
        bombTimeRemaining = sim.state.bomb.timer.remaining
    }

    public func player(_ id: PlayerID) -> PlayerSnapshot? {
        players.first { $0.id == id }
    }
}

/// Delta-compressed snapshot encoding. Each player writes a 10-bit "changed" mask against
/// the client's last acknowledged snapshot; unchanged fields cost one bit.
public enum SnapshotCodec {
    private enum Field: Int, CaseIterable {
        case position = 0, velocity, angles, health, armor, alive, stance, weapon, ammo, flags, score
    }

    public static func encode(_ snapshot: WorldSnapshot, baseline: WorldSnapshot?,
                              bounds: AABB) -> Data {
        var w = BitWriter(capacity: 512)
        w.write(NetMessageType.snapshot.rawValue)
        w.write(snapshot.tick, bits: 32)
        w.write(baseline?.tick ?? 0, bits: 32)
        w.write(float: snapshot.serverTime)
        w.write(UInt32(snapshot.phase.rawValue), bits: 3)
        w.write(quantized: snapshot.phaseTimeRemaining, min: 0, max: 600, bits: 12)
        w.write(snapshot.strikeScore)
        w.write(snapshot.shieldScore)
        w.write(snapshot.round)
        w.write(snapshot.bombPlanted)
        if snapshot.bombPlanted {
            w.write(position: snapshot.bombPosition, bounds: bounds)
            w.write(quantized: snapshot.bombTimeRemaining, min: 0, max: 60, bits: 10)
        }

        w.write(UInt32(snapshot.players.count), bits: 6)
        for player in snapshot.players {
            let base = baseline?.player(player.id)
            w.write(player.id.rawValue)
            var mask: UInt32 = 0
            func mark(_ field: Field, _ changed: Bool) {
                if changed { mask |= (1 << UInt32(field.rawValue)) }
            }
            mark(.position, base == nil || base!.position.distanceSquared(to: player.position) > 0.0004)
            mark(.velocity, base == nil || base!.velocity.distanceSquared(to: player.velocity) > 0.01)
            mark(.angles, base == nil || abs(MathUtil.angleDelta(base!.yaw, player.yaw)) > 0.002
                 || abs(base!.pitch - player.pitch) > 0.002)
            mark(.health, base?.health != player.health)
            mark(.armor, base?.armor != player.armor)
            mark(.alive, base?.isAlive != player.isAlive)
            mark(.stance, base?.stance != player.stance)
            mark(.weapon, base?.weapon != player.weapon)
            mark(.ammo, base?.ammoInMagazine != player.ammoInMagazine)
            mark(.flags, base == nil || base!.isFiring != player.isFiring
                 || base!.isReloading != player.isReloading || base!.isAiming != player.isAiming)
            mark(.score, base == nil || base!.kills != player.kills
                 || base!.deaths != player.deaths || base!.score != player.score)
            w.write(mask, bits: Field.allCases.count)

            if mask & (1 << UInt32(Field.position.rawValue)) != 0 {
                w.write(position: player.position, bounds: bounds)
            }
            if mask & (1 << UInt32(Field.velocity.rawValue)) != 0 {
                w.write(quantized: player.velocity.x, min: -30, max: 30, bits: 12)
                w.write(quantized: player.velocity.y, min: -40, max: 40, bits: 12)
                w.write(quantized: player.velocity.z, min: -30, max: 30, bits: 12)
            }
            if mask & (1 << UInt32(Field.angles.rawValue)) != 0 {
                w.write(angle: player.yaw)
                w.write(quantized: player.pitch, min: -ViewAngles.maxPitch,
                        max: ViewAngles.maxPitch, bits: 12)
            }
            if mask & (1 << UInt32(Field.health.rawValue)) != 0 { w.write(player.health) }
            if mask & (1 << UInt32(Field.armor.rawValue)) != 0 { w.write(player.armor) }
            if mask & (1 << UInt32(Field.alive.rawValue)) != 0 { w.write(player.isAlive) }
            if mask & (1 << UInt32(Field.stance.rawValue)) != 0 {
                w.write(UInt32(player.stance.rawValue), bits: 3)
            }
            if mask & (1 << UInt32(Field.weapon.rawValue)) != 0 {
                w.write(string: player.weapon.value)
            }
            if mask & (1 << UInt32(Field.ammo.rawValue)) != 0 { w.write(player.ammoInMagazine) }
            if mask & (1 << UInt32(Field.flags.rawValue)) != 0 {
                w.write(player.isFiring); w.write(player.isReloading); w.write(player.isAiming)
                w.write(UInt32(player.team.rawValue), bits: 2)
            }
            if mask & (1 << UInt32(Field.score.rawValue)) != 0 {
                w.write(player.kills); w.write(player.deaths); w.write(player.score)
            }
        }

        w.write(UInt32(snapshot.projectiles.count), bits: 5)
        for p in snapshot.projectiles.prefix(31) {
            w.write(p.entity.rawValue)
            w.write(UInt32(p.kind.rawValue), bits: 3)
            w.write(position: p.position, bounds: bounds)
            w.write(quantized: p.velocity.x, min: -40, max: 40, bits: 10)
            w.write(quantized: p.velocity.y, min: -40, max: 40, bits: 10)
            w.write(quantized: p.velocity.z, min: -40, max: 40, bits: 10)
        }
        return w.finish()
    }

    public static func decode(_ reader: inout BitReader, baseline: WorldSnapshot?,
                              bounds: AABB) -> WorldSnapshot? {
        let tick = reader.readUInt32()
        let baselineTick = reader.readUInt32()
        let serverTime = reader.readFloat()
        let phase = MatchPhase(rawValue: UInt8(reader.read(bits: 3))) ?? .live
        let phaseRemaining = reader.readQuantized(min: 0, max: 600, bits: 12)
        let strike = reader.readUInt16()
        let shield = reader.readUInt16()
        let round = reader.readUInt8()
        let bombPlanted = reader.readBool()
        var bombPosition = Vec3.zero
        var bombTime: Float = 0
        if bombPlanted {
            bombPosition = reader.readPosition(bounds: bounds)
            bombTime = reader.readQuantized(min: 0, max: 60, bits: 10)
        }
        // A baseline mismatch means the client missed too much: the server will resend full.
        if let baseline, baselineTick != 0, baseline.tick != baselineTick { return nil }

        let playerCount = Int(reader.read(bits: 6))
        var players: [PlayerSnapshot] = []
        players.reserveCapacity(playerCount)
        for _ in 0..<playerCount {
            let id = PlayerID(rawValue: reader.readUInt8())
            let mask = reader.read(bits: Field.allCases.count)
            var snapshot = baseline?.player(id) ?? PlayerSnapshot(
                id: id, team: .none, position: .zero, velocity: .zero, yaw: 0, pitch: 0,
                health: 100, armor: 0, isAlive: true, stance: .standing,
                weapon: WeaponDatabase.defaultPrimary, ammoInMagazine: 30,
                isFiring: false, isReloading: false, isAiming: false,
                kills: 0, deaths: 0, score: 0)
            snapshot.id = id

            func has(_ field: Field) -> Bool { mask & (1 << UInt32(field.rawValue)) != 0 }
            if has(.position) { snapshot.position = reader.readPosition(bounds: bounds) }
            if has(.velocity) {
                snapshot.velocity = Vec3(reader.readQuantized(min: -30, max: 30, bits: 12),
                                         reader.readQuantized(min: -40, max: 40, bits: 12),
                                         reader.readQuantized(min: -30, max: 30, bits: 12))
            }
            if has(.angles) {
                snapshot.yaw = reader.readAngle()
                snapshot.pitch = reader.readQuantized(min: -ViewAngles.maxPitch,
                                                      max: ViewAngles.maxPitch, bits: 12)
            }
            if has(.health) { snapshot.health = reader.readUInt8() }
            if has(.armor) { snapshot.armor = reader.readUInt8() }
            if has(.alive) { snapshot.isAlive = reader.readBool() }
            if has(.stance) { snapshot.stance = Stance(rawValue: UInt8(reader.read(bits: 3))) ?? .standing }
            if has(.weapon) { snapshot.weapon = WeaponID(reader.readString()) }
            if has(.ammo) { snapshot.ammoInMagazine = reader.readUInt8() }
            if has(.flags) {
                snapshot.isFiring = reader.readBool()
                snapshot.isReloading = reader.readBool()
                snapshot.isAiming = reader.readBool()
                snapshot.team = Team(rawValue: UInt8(reader.read(bits: 2))) ?? .none
            }
            if has(.score) {
                snapshot.kills = reader.readUInt8()
                snapshot.deaths = reader.readUInt8()
                snapshot.score = reader.readUInt16()
            }
            players.append(snapshot)
        }

        let projectileCount = Int(reader.read(bits: 5))
        var projectiles: [ProjectileSnapshot] = []
        projectiles.reserveCapacity(projectileCount)
        for _ in 0..<projectileCount {
            let entity = EntityID(rawValue: reader.readUInt16())
            let kind = GrenadeKind(rawValue: UInt8(reader.read(bits: 3))) ?? .frag
            let position = reader.readPosition(bounds: bounds)
            let velocity = Vec3(reader.readQuantized(min: -40, max: 40, bits: 10),
                                reader.readQuantized(min: -40, max: 40, bits: 10),
                                reader.readQuantized(min: -40, max: 40, bits: 10))
            projectiles.append(ProjectileSnapshot(entity: entity, kind: kind,
                                                  position: position, velocity: velocity))
        }

        guard !reader.failed else { return nil }
        return WorldSnapshot(tick: tick, serverTime: serverTime, phase: phase,
                             phaseTimeRemaining: phaseRemaining, strikeScore: strike,
                             shieldScore: shield, round: round, players: players,
                             projectiles: projectiles, bombPlanted: bombPlanted,
                             bombPosition: bombPosition, bombTimeRemaining: bombTime)
    }
}
