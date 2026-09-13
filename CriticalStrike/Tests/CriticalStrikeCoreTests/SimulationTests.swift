import XCTest
@testable import CriticalStrikeCore

/// Helper that spins up a real simulation on a real map.
private func makeSimulation(mode: GameModeKind = .teamDeathmatch,
                            map: MapData = MapDatabase.vault) -> MatchSimulation {
    MatchSimulation(map: map, mode: GameModeDatabase.mode(mode), seed: 42)
}

final class CollisionTests: XCTestCase {
    func testGroundIsFoundUnderEverySpawn() {
        for map in MapDatabase.all {
            let world = CollisionWorld(map: map)
            for spawn in map.spawns {
                let ground = world.groundHeight(below: spawn.position + Vec3(0, 3, 0), maxDrop: 40)
                XCTAssertNotNil(ground, "\(map.name) has a spawn with no floor beneath it")
            }
        }
    }

    func testSpawnsAreNotInsideGeometry() {
        for map in MapDatabase.all {
            let world = CollisionWorld(map: map)
            for spawn in map.spawns {
                let body = AABB(min: spawn.position + Vec3(-0.4, 0.15, -0.4),
                                max: spawn.position + Vec3(0.4, 1.75, 0.4))
                XCTAssertFalse(world.overlaps(box: body, mask: .solid),
                               "\(map.name) has a spawn embedded in geometry at \(spawn.position)")
            }
        }
    }

    func testWallsBlockLineOfSight() {
        let map = MapDatabase.vault
        let world = CollisionWorld(map: map)
        // The central vault block sits at the origin and is 3.4m tall.
        XCTAssertFalse(world.hasLineOfSight(from: Vec3(-12, 1.5, 0), to: Vec3(12, 1.5, 0)))
        // Above it, the sightline is clear.
        XCTAssertTrue(world.hasLineOfSight(from: Vec3(-12, 5.0, 0), to: Vec3(12, 5.0, 0)))
    }

    func testSweepStopsAtWalls() {
        let map = MapDatabase.vault
        let world = CollisionWorld(map: map)
        let box = AABB(center: Vec3(0, 1, 8), size: Vec3(0.8, 1.8, 0.8))
        let result = world.sweep(box: box, delta: Vec3(0, 0, -20), mask: .solid)
        XCTAssertTrue(result.hit)
        XCTAssertLessThan(result.fraction, 1)
    }
}

final class NavigationTests: XCTestCase {
    /// Baked once per map for the whole suite. Baking is thousands of ray traces and these
    /// tests used to pay for it three times over.
    private static let graphs: [(map: MapData, nav: NavGraph)] = MapDatabase.all.map { map in
        let world = CollisionWorld(map: map)
        return (map, NavGraph(map: map, world: world, spacing: 2.5))
    }

    func testEveryMapBakesAUsableNavGraph() {
        for (map, nav) in NavigationTests.graphs {
            XCTAssertFalse(nav.isEmpty, "\(map.name) produced an empty nav graph")
            XCTAssertGreaterThan(nav.nodes.count, 40, "\(map.name) nav graph is suspiciously small")
        }
    }

    func testPathExistsBetweenOpposingSpawns() {
        for (map, nav) in NavigationTests.graphs {
            guard let attacker = map.spawns(for: .strike).first,
                  let defender = map.spawns(for: .shield).first else { continue }
            let path = nav.findPath(from: attacker.position, to: defender.position)
            XCTAssertFalse(path.isEmpty,
                           "\(map.name): no path between the two team spawns — the map is split")
        }
    }

    func testPathToObjectivesExists() {
        guard let entry = NavigationTests.graphs.first(where: { $0.map.id == MapDatabase.sandstorm.id })
        else { return XCTFail("sandstorm missing") }
        guard let spawn = entry.map.spawns(for: .strike).first else { return XCTFail("no spawn") }
        for site in entry.map.bombSites {
            let path = entry.nav.findPath(from: spawn.position, to: site.center)
            XCTAssertFalse(path.isEmpty, "No route from spawn to bomb site \(site.name)")
        }
    }

    /// A path is only useful if you can actually walk it. The A* was rewritten around a
    /// binary heap and array-indexed scores; this pins the part that matters — that
    /// consecutive waypoints are still linked nodes, and that the route ends where asked.
    func testPathsAreConnectedAndReachTheGoal() {
        for (map, nav) in NavigationTests.graphs {
            guard let attacker = map.spawns(for: .strike).first,
                  let defender = map.spawns(for: .shield).first else { continue }
            let path = nav.findPath(from: attacker.position, to: defender.position)
            guard path.count > 1 else { continue }

            // Every step must be within one link's reach of the previous one.
            for (a, b) in zip(path, path.dropFirst()) {
                XCTAssertLessThan(a.distance(to: b), 6,
                                  "\(map.name): \(a) and \(b) are not adjacent nav nodes")
            }
            let end = path[path.count - 1]
            XCTAssertLessThan(end.distance(to: defender.position), 12,
                              "\(map.name): the path stops short of the goal")
        }
    }

    func testPathingToAnUnreachablePointFailsCleanly() {
        guard let entry = NavigationTests.graphs.first else { return XCTFail("no maps") }
        let outside = entry.map.bounds.max + Vec3(500, 0, 500)
        XCTAssertTrue(entry.nav.findPath(from: entry.map.spawns.first?.position ?? .zero,
                                         to: outside).isEmpty)
    }
}

final class MovementTests: XCTestCase {
    private func player() -> PlayerState {
        var state = PlayerState(id: PlayerID(0), name: "T", team: .strike, isBot: false,
                                loadout: Loadout.starter())
        state.isAlive = true
        state.position = Vec3(0, 0.05, 8)
        return state
    }

    func testPlayerAcceleratesTowardsRunSpeed() {
        let map = MapDatabase.vault
        let world = CollisionWorld(map: map)
        let events = EventBus()
        var state = player()
        var input = InputCommand(deltaTime: GameClock.tickInterval, moveForward: 1)

        for _ in 0..<64 {
            let ctx = MovementSystem.Context(world: world, now: 0, events: events)
            MovementSystem.step(player: &state, input: input, ctx: ctx)
            input.tick += 1
        }
        let speed = state.velocity.horizontalLength
        XCTAssertGreaterThan(speed, MovementSystem.runSpeed * 0.85)
        XCTAssertLessThanOrEqual(speed, MovementSystem.sprintSpeed * 1.05)
    }

    func testPlayerStopsWhenInputStops() {
        let world = CollisionWorld(map: MapDatabase.vault)
        let events = EventBus()
        var state = player()
        var input = InputCommand(deltaTime: GameClock.tickInterval, moveForward: 1)
        for _ in 0..<32 {
            MovementSystem.step(player: &state, input: input,
                                ctx: MovementSystem.Context(world: world, now: 0, events: events))
        }
        input.moveForward = 0
        for _ in 0..<64 {
            MovementSystem.step(player: &state, input: input,
                                ctx: MovementSystem.Context(world: world, now: 0, events: events))
        }
        XCTAssertLessThan(state.velocity.horizontalLength, 0.2)
    }

    func testPlayerCannotWalkThroughWalls() {
        let map = MapDatabase.vault
        let world = CollisionWorld(map: map)
        let events = EventBus()
        var state = player()
        state.position = Vec3(0, 0.05, 9)
        // Drive straight into the central block for two seconds.
        let input = InputCommand(deltaTime: GameClock.tickInterval, moveForward: 1,
                                 yaw: .pi)     // face -Z
        for _ in 0..<128 {
            MovementSystem.step(player: &state, input: input,
                                ctx: MovementSystem.Context(world: world, now: 0, events: events))
        }
        let body = AABB(min: state.position + Vec3(-0.4, 0.1, -0.4),
                        max: state.position + Vec3(0.4, 1.7, 0.4))
        XCTAssertFalse(world.overlaps(box: body, mask: .solid),
                       "Player ended up inside geometry at \(state.position)")
    }

    func testGravityPullsAirbornePlayersDown() {
        let world = CollisionWorld(map: MapDatabase.vault)
        let events = EventBus()
        var state = player()
        state.position = Vec3(0, 6, 12)
        state.onGround = false
        let input = InputCommand(deltaTime: GameClock.tickInterval)
        for _ in 0..<64 {
            MovementSystem.step(player: &state, input: input,
                                ctx: MovementSystem.Context(world: world, now: 0, events: events))
        }
        XCTAssertLessThan(state.position.y, 6)
        XCTAssertTrue(state.onGround, "Player never landed")
    }

    func testCrouchingLowersTheHitbox() {
        XCTAssertLessThan(Stance.crouching.eyeHeight, Stance.standing.eyeHeight)
        let standing = HitboxLayout.bounds(at: .zero, crouchScale: Stance.standing.heightScale)
        let crouched = HitboxLayout.bounds(at: .zero, crouchScale: Stance.crouching.heightScale)
        XCTAssertLessThan(crouched.max.y, standing.max.y)
    }
}

final class WeaponSystemTests: XCTestCase {
    private func makeContext(_ sim: MatchSimulation, shooter: PlayerID) -> WeaponStepContext {
        WeaponStepContext(world: sim.world, targets: sim.hitVolumes(excluding: shooter),
                          now: sim.time, friendlyFire: false, events: sim.events,
                          mode: sim.state.mode.kind)
    }

    func testFiringConsumesAmmoAndRespectsFireRate() {
        let sim = makeSimulation()
        let id = sim.addPlayer(name: "Tester", team: .strike, isBot: false, loadout: Loadout.starter())
        sim.respawn(id, force: true)
        var rng = DeterministicRandom(seed: 1)
        var player = sim.player(id)!
        let startingAmmo = player.slots[.primary]!.ammoInMagazine

        let input = InputCommand(deltaTime: GameClock.tickInterval, buttons: [.fire])
        _ = WeaponSystem.step(player: &player, input: input,
                              ctx: makeContext(sim, shooter: id), rng: &rng)
        XCTAssertEqual(player.slots[.primary]!.ammoInMagazine, startingAmmo - 1)

        // Immediately firing again must be blocked by the cooldown.
        _ = WeaponSystem.step(player: &player, input: input,
                              ctx: makeContext(sim, shooter: id), rng: &rng)
        XCTAssertEqual(player.slots[.primary]!.ammoInMagazine, startingAmmo - 1)
    }

    func testReloadRefillsFromReserve() {
        let sim = makeSimulation()
        let id = sim.addPlayer(name: "Tester", team: .strike, isBot: false, loadout: Loadout.starter())
        sim.respawn(id, force: true)
        var rng = DeterministicRandom(seed: 2)
        var player = sim.player(id)!
        var slot = player.slots[.primary]!
        slot.ammoInMagazine = 3
        player.slots[.primary] = slot
        let reserveBefore = slot.reserveAmmo

        var input = InputCommand(deltaTime: GameClock.tickInterval, buttons: [.reload])
        _ = WeaponSystem.step(player: &player, input: input, ctx: makeContext(sim, shooter: id), rng: &rng)
        XCTAssertEqual(player.action, .reloading)

        input.buttons = []
        for _ in 0..<300 {
            _ = WeaponSystem.step(player: &player, input: input,
                                  ctx: makeContext(sim, shooter: id), rng: &rng)
            if player.action == .ready { break }
        }
        let after = player.slots[.primary]!
        XCTAssertEqual(after.ammoInMagazine, after.resolvedWeapon.magazineSize)
        XCTAssertLessThan(after.reserveAmmo, reserveBefore)
    }

    func testSemiAutomaticNeedsATriggerRelease() {
        let sim = makeSimulation()
        var loadout = Loadout.starter()
        loadout.primary = WeaponBuild(weapon: "snp_specter")   // semi-automatic
        let id = sim.addPlayer(name: "Tester", team: .strike, isBot: false, loadout: loadout)
        sim.respawn(id, force: true)
        var rng = DeterministicRandom(seed: 3)
        var player = sim.player(id)!
        let start = player.slots[.primary]!.ammoInMagazine

        // Hold the trigger for a long time: only one shot may come out.
        let held = InputCommand(deltaTime: GameClock.tickInterval, buttons: [.fire])
        for _ in 0..<120 {
            _ = WeaponSystem.step(player: &player, input: held,
                                  ctx: makeContext(sim, shooter: id), rng: &rng)
        }
        XCTAssertEqual(player.slots[.primary]!.ammoInMagazine, start - 1,
                       "A semi-automatic weapon fired more than once on a held trigger")
    }

    func testRecoilAccumulatesAndRecovers() {
        var player = PlayerState(id: PlayerID(0), name: "T", team: .strike, isBot: false,
                                 loadout: Loadout.starter())
        player.isAlive = true
        let weapon = WeaponDatabase.weaponOrDefault("ar_vanguard")
        var rng = DeterministicRandom(seed: 4)

        for index in 0..<10 {
            RecoilSystem.applyShot(player: &player, weapon: weapon, shotIndex: index, rng: &rng)
        }
        XCTAssertGreaterThan(player.recoilOffset.pitch, 0, "Recoil did not climb")
        XCTAssertGreaterThan(player.currentSpread, 0, "Spread did not bloom")

        for _ in 0..<300 {
            RecoilSystem.decay(player: &player, weapon: weapon, dt: GameClock.tickInterval)
        }
        XCTAssertEqual(player.recoilOffset.pitch, 0, accuracy: 0.002)
        XCTAssertEqual(player.currentSpread, 0, accuracy: 0.0001)
    }

    func testSpreadIsWorseWhileMovingAndBetterWhileCrouched() {
        let weapon = WeaponDatabase.weaponOrDefault("ar_vanguard")
        var still = PlayerState(id: PlayerID(0), name: "T", team: .strike, isBot: false,
                                loadout: Loadout.starter())
        still.isAlive = true
        still.onGround = true

        var moving = still
        moving.velocity = Vec3(MovementSystem.runSpeed, 0, 0)

        var crouched = still
        crouched.stance = .crouching

        var airborne = still
        airborne.onGround = false

        let base = RecoilSystem.effectiveSpread(player: still, weapon: weapon)
        XCTAssertGreaterThan(RecoilSystem.effectiveSpread(player: moving, weapon: weapon), base)
        XCTAssertLessThan(RecoilSystem.effectiveSpread(player: crouched, weapon: weapon), base)
        XCTAssertGreaterThan(RecoilSystem.effectiveSpread(player: airborne, weapon: weapon), base)
    }
}

final class BallisticsTests: XCTestCase {
    func testBulletHitsAnExposedTarget() {
        let map = MapDatabase.vault
        let world = CollisionWorld(map: map)
        let weapon = WeaponDatabase.weaponOrDefault("ar_vanguard")
        let target = HitVolume(player: PlayerID(1), team: .shield, position: Vec3(0, 0, -10),
                               crouchScale: 1, isAlive: true)
        let result = BallisticsSystem.fireBullet(origin: Vec3(0, 1.6, 0), direction: Vec3(0, 0, -1),
                                                 weapon: weapon, shooter: PlayerID(0),
                                                 shooterTeam: .strike, friendlyFire: false,
                                                 world: world, targets: [target])
        XCTAssertEqual(result.hits.count, 1)
        XCTAssertEqual(result.hits.first?.victim, PlayerID(1))
    }

    func testFriendlyFireOffProtectsTeammates() {
        let world = CollisionWorld(map: MapDatabase.vault)
        let weapon = WeaponDatabase.weaponOrDefault("ar_vanguard")
        let friend = HitVolume(player: PlayerID(1), team: .strike, position: Vec3(0, 0, -10),
                               crouchScale: 1, isAlive: true)
        let result = BallisticsSystem.fireBullet(origin: Vec3(0, 1.6, 0), direction: Vec3(0, 0, -1),
                                                 weapon: weapon, shooter: PlayerID(0),
                                                 shooterTeam: .strike, friendlyFire: false,
                                                 world: world, targets: [friend])
        XCTAssertTrue(result.hits.isEmpty)
    }

    func testHeadshotsRegisterOnTheHeadHitbox() {
        let world = CollisionWorld(map: MapDatabase.vault)
        let weapon = WeaponDatabase.weaponOrDefault("ar_vanguard")
        let target = HitVolume(player: PlayerID(1), team: .shield, position: Vec3(0, 0, -10),
                               crouchScale: 1, isAlive: true)
        // Eye height 1.68 is the centre of the head box.
        let result = BallisticsSystem.fireBullet(origin: Vec3(0, 1.68, 0), direction: Vec3(0, 0, -1),
                                                 weapon: weapon, shooter: PlayerID(0),
                                                 shooterTeam: .strike, friendlyFire: false,
                                                 world: world, targets: [target])
        XCTAssertEqual(result.hits.first?.hitbox, .head)
    }

    func testThickWallsStopWeakRounds() {
        let map = MapDatabase.vault
        let world = CollisionWorld(map: map)
        let pistol = WeaponDatabase.weaponOrDefault("pst_sidearm")
        // Shoot through the central vault block at a target on the far side.
        let target = HitVolume(player: PlayerID(1), team: .shield, position: Vec3(0, 0, -12),
                               crouchScale: 1, isAlive: true)
        let result = BallisticsSystem.fireBullet(origin: Vec3(0, 1.2, 12), direction: Vec3(0, 0, -1),
                                                 weapon: pistol, shooter: PlayerID(0),
                                                 shooterTeam: .strike, friendlyFire: false,
                                                 world: world, targets: [target])
        XCTAssertTrue(result.hits.isEmpty, "A pistol penetrated a solid metal block")
    }

    func testBackstabDetection() {
        // Victim faces -Z; attacker stands behind at +Z.
        XCTAssertTrue(BallisticsSystem.isBackstab(attackerPosition: Vec3(0, 0, 2),
                                                  victimPosition: .zero, victimYaw: 0))
        XCTAssertFalse(BallisticsSystem.isBackstab(attackerPosition: Vec3(0, 0, -2),
                                                   victimPosition: .zero, victimYaw: 0))
    }
}

final class MatchFlowTests: XCTestCase {
    func testMatchRunsAndProducesAResult() {
        let sim = makeSimulation(mode: .teamDeathmatch)
        let director = BotDirector(difficulty: .regular, seed: 9)
        let local = sim.addPlayer(name: "Player", team: .strike, isBot: false,
                                  loadout: Loadout.starter())
        sim.localPlayer = local
        director.fillMatch(sim)
        XCTAssertGreaterThan(sim.allPlayers().count, 2)

        var finished: MatchResult?
        sim.onMatchEnded = { finished = $0 }
        sim.startMatch()

        // Ten simulated minutes at 64Hz. Bots alone should reach the score limit or the
        // time limit; either way the match must terminate cleanly.
        for _ in 0..<(64 * 60 * 10) {
            director.step(sim: sim, dt: GameClock.tickInterval)
            sim.step(deltaTime: GameClock.tickInterval)
            if finished != nil { break }
        }

        XCTAssertNotNil(finished, "The match never ended")
        if let finished {
            XCTAssertFalse(finished.results.isEmpty)
            XCTAssertGreaterThan(finished.results.reduce(0) { $0 + $1.kills }, 0,
                                 "Nobody scored a single kill in ten minutes")
        }
    }

    func testBotsActuallyMoveAndShoot() {
        let sim = makeSimulation(mode: .freeForAll)
        let director = BotDirector(difficulty: .veteran, seed: 11)
        director.fillMatch(sim)
        sim.startMatch()

        let startPositions = sim.allPlayers().map(\.position)
        var shotsObserved = 0
        sim.events.subscribe { event in
            if case .weaponFired = event { shotsObserved += 1 }
        }
        for _ in 0..<(64 * 30) {
            director.step(sim: sim, dt: GameClock.tickInterval)
            sim.step(deltaTime: GameClock.tickInterval)
            _ = sim.events.drain()
        }
        let moved = zip(startPositions, sim.allPlayers().map(\.position))
            .contains { $0.distance(to: $1) > 3 }
        XCTAssertTrue(moved, "No bot moved more than 3 metres in 30 seconds")
        XCTAssertGreaterThan(shotsObserved, 0, "No bot fired a shot in 30 seconds")
    }

    func testBombModeRunsARoundToCompletion() {
        let sim = MatchSimulation(map: MapDatabase.sandstorm,
                                  mode: GameModeDatabase.mode(.bombDefusal), seed: 5)
        let director = BotDirector(difficulty: .hardened, seed: 13)
        director.fillMatch(sim)
        sim.startMatch()

        var roundEnded = false
        sim.events.subscribe { event in
            if case .roundEnded = event { roundEnded = true }
        }
        for _ in 0..<(64 * 200) {
            director.step(sim: sim, dt: GameClock.tickInterval)
            sim.step(deltaTime: GameClock.tickInterval)
            _ = sim.events.drain()
            if roundEnded { break }
        }
        XCTAssertTrue(roundEnded, "A bomb defusal round never resolved")
    }

    func testKillingAPlayerScoresAndRespawns() {
        let sim = makeSimulation(mode: .teamDeathmatch)
        let attacker = sim.addPlayer(name: "A", team: .strike, isBot: false, loadout: Loadout.starter())
        let victim = sim.addPlayer(name: "V", team: .shield, isBot: false, loadout: Loadout.starter())
        sim.startMatch()
        sim.respawn(attacker, force: true)
        sim.respawn(victim, force: true)

        sim.killPlayer(victim, killer: attacker, weapon: "ar_vanguard", headshot: true, wallbang: false)
        XCTAssertEqual(sim.player(attacker)?.kills, 1)
        XCTAssertEqual(sim.player(victim)?.deaths, 1)
        XCTAssertFalse(sim.player(victim)?.isAlive ?? true)
        XCTAssertEqual(sim.state.score(.strike), 1)

        // The respawn timer should bring them back.
        for _ in 0..<(64 * 10) {
            sim.step(deltaTime: GameClock.tickInterval)
            if sim.player(victim)?.isAlive == true { break }
        }
        XCTAssertTrue(sim.player(victim)?.isAlive ?? false, "Victim never respawned")
    }

    func testSpawnSelectionAvoidsEnemies() {
        let sim = makeSimulation(mode: .teamDeathmatch, map: MapDatabase.sandstorm)
        let enemy = sim.addPlayer(name: "E", team: .shield, isBot: true, loadout: Loadout.starter())
        let player = sim.addPlayer(name: "P", team: .strike, isBot: false, loadout: Loadout.starter())
        sim.respawn(enemy, force: true)

        guard let enemyState = sim.player(enemy), let playerState = sim.player(player) else {
            return XCTFail("missing players")
        }
        let chosen = sim.selectSpawn(for: playerState)
        // The chosen spawn should not be the one closest to the enemy.
        let closest = MapDatabase.sandstorm.spawns(for: .strike)
            .min { $0.position.distance(to: enemyState.position)
                 < $1.position.distance(to: enemyState.position) }
        if let closest, MapDatabase.sandstorm.spawns(for: .strike).count > 1 {
            XCTAssertNotEqual(chosen.position, closest.position,
                              "Spawn selection picked the spawn nearest the enemy")
        }
    }
}

/// Every shipped map, built for real.
///
/// The whole suite used to die on its first test with "Range requires lowerBound <=
/// upperBound", because Vault has a descending staircase and `stairs()` put each step's
/// base above its tread — an inverted AABB, which the collision grid walks as a range.
/// Nothing exercised map construction directly, so the crash surfaced through whichever
/// test happened to touch a map first.
final class MapIntegrityTests: XCTestCase {

    func testEveryMapBuilds() {
        XCTAssertEqual(MapDatabase.all.count, 5)
        for map in MapDatabase.all {
            XCTAssertFalse(map.brushes.isEmpty, "\(map.id.value) has no geometry")
            XCTAssertFalse(map.spawns.isEmpty, "\(map.id.value) has no spawns")
        }
    }

    func testEveryBrushIsWellFormed() {
        // Collected, then asserted once. Six assertions per brush across five maps is tens
        // of thousands of trips through XCTest's reporting machinery, and it buys nothing:
        // one failure naming the offending brushes says more than the first of thousands.
        var malformed: [String] = []
        for map in MapDatabase.all {
            for (index, brush) in map.brushes.enumerated() {
                let box = brush.box
                let ordered = box.min.x <= box.max.x && box.min.y <= box.max.y
                    && box.min.z <= box.max.z
                let finite = box.min.x.isFinite && box.min.y.isFinite && box.min.z.isFinite
                    && box.max.x.isFinite && box.max.y.isFinite && box.max.z.isFinite
                if !ordered || !finite {
                    malformed.append("\(map.id.value)[\(index)] \(box.min) … \(box.max)")
                }
            }
        }
        XCTAssertTrue(malformed.isEmpty,
                      "malformed brushes: \(malformed.prefix(10).joined(separator: ", "))")
    }

    func testAABBOrdersItsCorners() {
        let inverted = AABB(min: Vec3(5, 9, 2), max: Vec3(-1, 3, 7))
        XCTAssertEqual(inverted.min, Vec3(-1, 3, 2))
        XCTAssertEqual(inverted.max, Vec3(5, 9, 7))
        XCTAssertEqual(inverted.size, Vec3(6, 6, 5))
    }

    func testWorldDataIsSharedBetweenMatchesOnTheSameMap() {
        // Two simulations on one map must get the same baked world, or every match restart
        // pays for a couple of thousand ray traces it does not need.
        let mode = GameModeDatabase.mode(.teamDeathmatch)
        let first = MatchSimulation(map: MapDatabase.vault, mode: mode)
        let second = MatchSimulation(map: MapDatabase.vault, mode: mode)
        XCTAssertTrue(first.world === second.world)
        XCTAssertTrue(first.nav === second.nav)

        // A different map must not get the first one's geometry.
        let other = MatchSimulation(map: MapDatabase.sandstorm, mode: mode)
        XCTAssertFalse(first.world === other.world)
    }

    func testAuthoredMapsDoNotInheritACachedWorld() {
        // Tests author maps and reuse ids freely; handing one of those a world baked from
        // different geometry would be much worse than rebuilding it.
        var author = MapAuthor()
        author.block(x: -4...4, z: -4...4, height: 1)
        let bounds = AABB(min: Vec3(-10, -2, -10), max: Vec3(10, 10, 10))
        let small = MapData(id: "map_vault", name: "Tiny", summary: "",
                            bounds: bounds, brushes: author.brushes)
        XCTAssertFalse(MapWorldCache.world(for: small) === MapWorldCache.world(for: MapDatabase.vault))
    }

    func testCollisionWorldBuildsForEveryMap() {
        // Building the grid is what actually crashed: it walks min-cell to max-cell as a
        // range, so an inverted brush is a trap rather than a harmless oddity.
        //
        // Queried around a spawn rather than over `map.bounds`. A whole-map query visits
        // every cell and pushes every brush through a Set — millions of operations in an
        // unoptimised build, to prove something a two-metre box proves just as well.
        for map in MapDatabase.all {
            let world = MapWorldCache.world(for: map)
            guard let spawn = map.spawns.first else {
                XCTFail("\(map.id.value) has no spawns")
                continue
            }
            let nearby = AABB(center: spawn.position + Vec3(0, 1, 0), size: Vec3(4, 4, 4))
            XCTAssertFalse(world.candidates(in: nearby).isEmpty,
                           "\(map.id.value): no geometry near a spawn point")
            // And the player is standing on something.
            XCTAssertNotNil(world.groundHeight(below: spawn.position + Vec3(0, 2, 0)),
                            "\(map.id.value): a spawn has no floor under it")
        }
    }

    func testDescendingStairsProduceWellFormedSteps() {
        var author = MapAuthor()
        author.stairs(x: -5...5, z: -9...(-5), from: 3.4, to: 0, steps: 7)
        author.stairs(x: -5...5, z: 5...9, from: 0, to: 3.4, steps: 7)
        XCTAssertEqual(author.brushes.count, 14)
        for brush in author.brushes {
            XCTAssertLessThan(brush.box.min.y, brush.box.max.y)
            XCTAssertLessThan(brush.box.min.z, brush.box.max.z)
        }
        // The descending flight must actually descend.
        let descending = author.brushes.prefix(7).map(\.box.max.y)
        XCTAssertGreaterThan(descending.first!, descending.last!)
    }

    func testEverySpawnIsInsideTheMapBounds() {
        var outside: [String] = []
        for map in MapDatabase.all {
            for spawn in map.spawns where !map.bounds.contains(spawn.position) {
                outside.append("\(map.id.value) at \(spawn.position)")
            }
        }
        XCTAssertTrue(outside.isEmpty, "spawns outside their map: \(outside.joined(separator: ", "))")
    }
}
