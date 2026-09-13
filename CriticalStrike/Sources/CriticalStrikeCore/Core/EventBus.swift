import Foundation

/// Everything the presentation layer cares about is emitted as a `GameEvent`.
/// The simulation never touches SceneKit / AVFoundation / SwiftUI directly — it just
/// appends events, and the app layer drains them each frame to spawn effects, sounds
/// and HUD updates. That separation is what makes the core unit-testable.
public enum GameEvent: Sendable {
    case matchStarted(mode: GameModeKind, map: MapID)
    case roundStarted(round: Int)
    case roundEnded(winner: Team, reason: RoundEndReason)
    case matchEnded(result: MatchResult)
    case warmupTick(secondsLeft: Int)

    case playerSpawned(player: PlayerID, position: Vec3, team: Team)
    case playerDied(victim: PlayerID, killer: PlayerID, weapon: WeaponID, headshot: Bool, wallbang: Bool)
    case playerDamaged(victim: PlayerID, attacker: PlayerID, amount: Float, hitbox: HitboxKind, position: Vec3)
    case playerHealed(player: PlayerID, amount: Float)
    case playerJoined(player: PlayerID, name: String, team: Team, isBot: Bool)
    case playerLeft(player: PlayerID)
    case teamChanged(player: PlayerID, team: Team)

    case weaponFired(player: PlayerID, weapon: WeaponID, origin: Vec3, direction: Vec3, ammoLeft: Int)
    case weaponReloadStarted(player: PlayerID, weapon: WeaponID, duration: Float)
    case weaponReloadFinished(player: PlayerID, weapon: WeaponID)
    case weaponSwitched(player: PlayerID, weapon: WeaponID, slot: LoadoutSlot)
    case weaponDryFire(player: PlayerID)
    case bulletImpact(position: Vec3, normal: Vec3, surface: SurfaceKind, penetrated: Bool)
    case bulletTracer(from: Vec3, to: Vec3, weapon: WeaponID)

    case grenadeThrown(player: PlayerID, kind: GrenadeKind, entity: EntityID, origin: Vec3, velocity: Vec3)
    case grenadeBounced(entity: EntityID, position: Vec3, surface: SurfaceKind)
    case grenadeDetonated(entity: EntityID, kind: GrenadeKind, position: Vec3)
    case flashed(player: PlayerID, intensity: Float, duration: Float)
    case smokeStarted(entity: EntityID, position: Vec3, radius: Float, duration: Float)
    case fireStarted(entity: EntityID, position: Vec3, radius: Float, duration: Float)

    case footstep(player: PlayerID, position: Vec3, surface: SurfaceKind, loud: Bool)
    case jumped(player: PlayerID, position: Vec3)
    case landed(player: PlayerID, position: Vec3, hardness: Float)

    case bombPlanted(player: PlayerID, site: Int, position: Vec3)
    case bombDefuseStarted(player: PlayerID, hasKit: Bool)
    case bombDefuseAborted(player: PlayerID)
    case bombDefused(player: PlayerID)
    case bombExploded(position: Vec3)
    case bombPickedUp(player: PlayerID)
    case bombDropped(position: Vec3)

    case objectiveCaptured(point: Int, team: Team, by: [PlayerID])
    case objectiveContested(point: Int)
    case objectiveProgress(point: Int, team: Team, progress: Float)

    case killStreak(player: PlayerID, count: Int)
    case multiKill(player: PlayerID, count: Int)
    case firstBlood(player: PlayerID)
    case assist(player: PlayerID, victim: PlayerID)
    case scoreChanged(strike: Int, shield: Int)
    case xpAwarded(player: PlayerID, amount: Int, reason: String)
    case currencyAwarded(amount: Int, kind: CurrencyKind, reason: String)

    case chat(player: PlayerID, message: String, teamOnly: Bool)
    case voiceLine(player: PlayerID, line: VoiceLine)
    case ping(player: PlayerID, position: Vec3, kind: PingKind)

    case pickupCollected(player: PlayerID, entity: EntityID, kind: PickupKind)
    case pickupSpawned(entity: EntityID, position: Vec3, kind: PickupKind)
    case weaponDropped(entity: EntityID, weapon: WeaponID, position: Vec3, ammo: Int)

    case networkStateChanged(NetConnectionState)
    case hitConfirmed(attacker: PlayerID, lethal: Bool, headshot: Bool, damage: Float)
}

public enum RoundEndReason: String, Codable, Sendable {
    case elimination, bombExploded, bombDefused, timeExpired, objectiveComplete, surrender, forfeit
}

public enum PingKind: UInt8, Codable, CaseIterable, Sendable {
    case generic, enemy, danger, going, needBackup, defend, bombHere
}

public enum VoiceLine: UInt8, Codable, CaseIterable, Sendable {
    case affirmative, negative, enemySpotted, needBackup, coveringFire, goGoGo, nice, sorry, taunt
}

/// Single-threaded, allocation-friendly event queue. The simulation writes, the app drains.
public final class EventBus: @unchecked Sendable {
    private var queue: [GameEvent] = []
    private var listeners: [(GameEvent) -> Void] = []
    private let lock = NSLock()

    public init() { queue.reserveCapacity(256) }

    public func emit(_ event: GameEvent) {
        lock.lock()
        queue.append(event)
        lock.unlock()
    }

    /// Registers a live listener (used by the audio engine and HUD, which want events as
    /// they happen rather than at drain time).
    public func subscribe(_ handler: @escaping (GameEvent) -> Void) {
        lock.lock()
        listeners.append(handler)
        lock.unlock()
    }

    /// Removes and returns everything queued since the last drain.
    @discardableResult
    public func drain() -> [GameEvent] {
        lock.lock()
        let events = queue
        queue.removeAll(keepingCapacity: true)
        let handlers = listeners
        lock.unlock()
        if !handlers.isEmpty {
            for e in events { for h in handlers { h(e) } }
        }
        return events
    }

    public func clear() {
        lock.lock()
        queue.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}
