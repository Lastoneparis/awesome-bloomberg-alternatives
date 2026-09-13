import Foundation

public enum MapDatabase {
    public static let all: [MapData] = [sandstorm, refinery, downtown, vault, frostline]

    private static let index: [MapID: MapData] = {
        var m = [MapID: MapData](); for x in all { m[x.id] = x }; return m
    }()

    public static func map(_ id: MapID) -> MapData? { index[id] }
    public static func mapOrDefault(_ id: MapID) -> MapData { index[id] ?? sandstorm }
    public static func maps(for mode: GameModeKind) -> [MapData] { all.filter { $0.supports(mode) } }
    public static func randomMap(for mode: GameModeKind, rng: inout DeterministicRandom) -> MapData {
        let pool = maps(for: mode)
        return rng.pick(pool) ?? sandstorm
    }

    // ══════════════════════════════════════════════════════════════════════
    // SANDSTORM — the flagship 5v5 bomb map. Three lanes (A long, mid, B tunnels),
    // deliberately asymmetric so both sides have a different opening.
    // ══════════════════════════════════════════════════════════════════════
    public static let sandstorm: MapData = {
        var a = MapAuthor()
        let bounds = AABB(min: Vec3(-46, -2, -46), max: Vec3(46, 26, 46))

        a.floor(x: -45...45, z: -45...45, surface: .sand)
        a.skyboxClip(bounds: bounds)

        // Perimeter town walls
        a.wall(from: Vec3(-45, 0, -45), to: Vec3(45, 0, -45), height: 8, thickness: 1, surface: .concrete)
        a.wall(from: Vec3(-45, 0, 45), to: Vec3(45, 0, 45), height: 8, thickness: 1, surface: .concrete)
        a.wall(from: Vec3(-45, 0, -45), to: Vec3(-45, 0, 45), height: 8, thickness: 1, surface: .concrete)
        a.wall(from: Vec3(45, 0, -45), to: Vec3(45, 0, 45), height: 8, thickness: 1, surface: .concrete)

        // ── A site (east): raised platform behind a low wall, one long approach ──
        a.block(x: 20...38, z: -34...(-18), height: 1.2, surface: .concrete)      // site platform
        a.wall(from: Vec3(20, 1.2, -34), to: Vec3(20, 1.2, -22), height: 1.4, thickness: 0.5, surface: .concrete)
        a.crateStack(at: Vec3(26, 1.2, -30), columns: 2, rows: 2, size: 1.3)
        a.crate(at: Vec3(33, 1.2, -22), size: 1.4, height: 1.4)
        a.room(x: 30...42, z: -44...(-34), height: 5, doors: [.south], windows: [.west], ceiling: true,
               surface: .concrete)                                                // A house
        a.stairs(x: 36...40, z: -34...(-30), from: 0, to: 3.2, steps: 8)          // to A balcony
        a.block(x: 30...42, z: -34...(-31), y: 3.2, height: 0.3, surface: .wood)  // balcony deck

        // A long: a corridor of shipping containers
        a.block(x: 18...20, z: -16...16, height: 3.2, surface: .metal)
        a.crate(at: Vec3(24, 0, -8), size: 2.2, height: 2.2, surface: .metal)
        a.crate(at: Vec3(31, 0, 2), size: 2.2, height: 2.2, surface: .metal)

        // ── Mid: open plaza with a fountain and two pillars, sniper duel territory ──
        a.block(x: -3...3, z: -3...3, height: 1.0, surface: .tile)                // fountain base
        a.block(x: -1...1, z: -1...1, y: 1.0, height: 1.6, surface: .tile)
        a.block(x: -12...(-10), z: -10...(-8), height: 5, surface: .concrete)     // pillar
        a.block(x: 10...12, z: 8...10, height: 5, surface: .concrete)             // pillar
        a.wall(from: Vec3(-16, 0, 14), to: Vec3(16, 0, 14), height: 1.3, thickness: 0.6, surface: .concrete)
        a.wall(from: Vec3(-16, 0, -14), to: Vec3(16, 0, -14), height: 1.3, thickness: 0.6, surface: .concrete)

        // ── B site (west): tunnels into a covered warehouse ──
        a.room(x: -40...(-20), z: 16...36, height: 6, doors: [.north, .east], windows: [.south],
               ceiling: true, surface: .concrete)
        a.crateStack(at: Vec3(-34, 0, 26), columns: 2, rows: 2, size: 1.4, surface: .metal)
        a.crate(at: Vec3(-25, 0, 20), size: 1.6, height: 1.6, surface: .wood)
        a.block(x: -30...(-26), z: 30...34, height: 2.4, surface: .wood)          // plant-behind box
        // B tunnels
        a.wall(from: Vec3(-20, 0, 4), to: Vec3(-20, 0, 16), height: 4, thickness: 0.6)
        a.wall(from: Vec3(-14, 0, 4), to: Vec3(-14, 0, 16), height: 4, thickness: 0.6)
        a.block(x: -20...(-14), z: 4...16, y: 4, height: 0.4, surface: .concrete) // tunnel roof

        // ── Buildings framing the lanes ──
        a.room(x: -14...(-2), z: -40...(-28), height: 5, doors: [.east, .south], windows: [.north],
               ceiling: true, surface: .concrete)
        a.room(x: 4...16, z: 28...40, height: 5, doors: [.west, .north], windows: [.east],
               ceiling: true, surface: .concrete)

        // ── Spawns ──
        a.spawnCluster(center: Vec3(0, 0, -40), yaw: 180, team: .strike, count: 5, spread: 2.2)
        a.spawnCluster(center: Vec3(0, 0, 40), yaw: 0, team: .shield, count: 5, spread: 2.2)
        for i in 0..<8 {
            let angle = Float(i) / 8 * 2 * .pi
            a.spawn(Vec3(cos(angle) * 30, 0, sin(angle) * 30), yaw: Float(i) * 45, team: .none)
        }

        // ── Lighting ──
        a.light(Vec3(0, 9, 0), intensity: 1100, range: 30, shadows: true)
        a.light(Vec3(29, 6, -26), intensity: 900, range: 24, colorHex: 0xFFD9A0)
        a.light(Vec3(-30, 6, 26), intensity: 900, range: 24, colorHex: 0xFFD9A0)
        a.light(Vec3(-17, 4, 10), intensity: 500, range: 14, colorHex: 0xB9D6FF)

        // ── Pickups & props ──
        a.pickup(.armor, at: Vec3(0, 1.2, 6))
        a.pickup(.health, at: Vec3(-24, 0, 22))
        a.pickup(.health, at: Vec3(28, 1.2, -26))
        a.pickup(.ammo, at: Vec3(12, 0, -4))
        a.pickup(.ammo, at: Vec3(-12, 0, 4))
        a.pickup(.powerupDamage, at: Vec3(0, 2.6, 0))
        a.prop("prop_palm", at: Vec3(-8, 0, 20), scale: 1.2)
        a.prop("prop_palm", at: Vec3(9, 0, -20), scale: 1.1)
        a.prop("prop_market_stall", at: Vec3(-6, 0, -6), yaw: 35, collides: true, surface: .fabric)
        a.prop("prop_truck", at: Vec3(16, 0, 22), yaw: 100, collides: true)
        a.prop("prop_barrel", at: Vec3(22, 0, -14), collides: true)

        // ── Callouts ──
        a.callout("A Site", x: 18...42, z: -38...(-16))
        a.callout("A Long", x: 16...38, z: -16...16)
        a.callout("A House", x: 28...44, z: -46...(-32))
        a.callout("Mid", x: -16...16, z: -16...16)
        a.callout("B Site", x: -42...(-18), z: 14...38)
        a.callout("B Tunnels", x: -22...(-12), z: 2...18)
        a.callout("CT Spawn", x: -12...12, z: 32...46)
        a.callout("T Spawn", x: -12...12, z: -46...(-32))

        return MapData(
            id: "map_sandstorm", name: "Sandstorm",
            summary: "A sun-bleached market town. Long A, tight B tunnels, and a mid that punishes the impatient.",
            bounds: bounds,
            environment: MapEnvironment(skyName: "sky_desert_noon", ambientColorHex: 0x6B6350,
                                        ambientIntensity: 320, fogColorHex: 0xD9C39A,
                                        fogStart: 55, fogEnd: 210, fogDensity: 0.45,
                                        sunDirection: Vec3(-0.35, -0.88, -0.32), sunColorHex: 0xFFE8B8,
                                        sunIntensity: 1650, musicTrack: "mus_sandstorm",
                                        ambienceLoop: "amb_desert_wind"),
            brushes: a.brushes, props: a.props, lights: a.lights, spawns: a.spawns,
            bombSites: [ObjectiveZone(index: 0, name: "A", center: Vec3(28, 1.2, -26), radius: 8),
                        ObjectiveZone(index: 1, name: "B", center: Vec3(-30, 0, 26), radius: 8)],
            capturePoints: [ObjectiveZone(index: 0, name: "A", center: Vec3(28, 1.2, -26), radius: 6),
                            ObjectiveZone(index: 1, name: "B", center: Vec3(0, 0, 0), radius: 6),
                            ObjectiveZone(index: 2, name: "C", center: Vec3(-30, 0, 26), radius: 6)],
            hardpoints: [ObjectiveZone(index: 0, name: "Plaza", center: Vec3(0, 0, 0), radius: 7),
                         ObjectiveZone(index: 1, name: "A Site", center: Vec3(28, 1.2, -26), radius: 7),
                         ObjectiveZone(index: 2, name: "B Site", center: Vec3(-30, 0, 26), radius: 7),
                         ObjectiveZone(index: 3, name: "Market", center: Vec3(-8, 0, -34), radius: 6)],
            pickups: a.pickups, callouts: a.callouts,
            supportedModes: GameModeKind.allCases, recommendedPlayers: PlayerRange(8, 10))
    }()

    // ══════════════════════════════════════════════════════════════════════
    // REFINERY — vertical industrial map. Catwalks over the floor, two bomb sites
    // stacked at different heights so grenades and verticality matter.
    // ══════════════════════════════════════════════════════════════════════
    public static let refinery: MapData = {
        var a = MapAuthor()
        let bounds = AABB(min: Vec3(-38, -2, -38), max: Vec3(38, 30, 38))

        a.floor(x: -37...37, z: -37...37, surface: .metal)
        a.skyboxClip(bounds: bounds)
        a.wall(from: Vec3(-37, 0, -37), to: Vec3(37, 0, -37), height: 12, thickness: 1, surface: .metal)
        a.wall(from: Vec3(-37, 0, 37), to: Vec3(37, 0, 37), height: 12, thickness: 1, surface: .metal)
        a.wall(from: Vec3(-37, 0, -37), to: Vec3(-37, 0, 37), height: 12, thickness: 1, surface: .metal)
        a.wall(from: Vec3(37, 0, -37), to: Vec3(37, 0, 37), height: 12, thickness: 1, surface: .metal)

        // Storage tanks (hard cover, penetrable at the seams)
        for (cx, cz) in [(-18, -12), (14, -20), (-8, 18), (22, 10)] {
            a.block(x: Float(cx) - 4...Float(cx) + 4, z: Float(cz) - 4...Float(cz) + 4,
                    height: 7, surface: .metal)
        }

        // Central gantry: raised walkway crossing the whole map
        a.block(x: -30...30, z: -1.5...1.5, y: 5, height: 0.4, surface: .metal)
        a.wall(from: Vec3(-30, 5.4, -1.5), to: Vec3(30, 5.4, -1.5), height: 1.1, thickness: 0.2, surface: .metal)
        a.wall(from: Vec3(-30, 5.4, 1.5), to: Vec3(30, 5.4, 1.5), height: 1.1, thickness: 0.2, surface: .metal)
        a.stairs(x: -30...(-26), z: -6...(-1.5), from: 0, to: 5, steps: 10, surface: .metal)
        a.stairs(x: 26...30, z: 1.5...6, from: 0, to: 5, steps: 10, surface: .metal)

        // A site — upper platform
        a.block(x: 16...32, z: -32...(-18), y: 3, height: 0.5, surface: .metal)
        a.stairs(x: 16...20, z: -18...(-12), from: 0, to: 3, steps: 7, surface: .metal)
        a.wall(from: Vec3(16, 3.5, -18), to: Vec3(32, 3.5, -18), height: 1.2, thickness: 0.3, surface: .metal)
        a.crateStack(at: Vec3(24, 3.5, -26), columns: 2, rows: 1, size: 1.4, surface: .metal)

        // B site — ground level under the pipes
        a.room(x: -32...(-16), z: 16...32, height: 6, doors: [.north, .east], windows: [.south],
               ceiling: true, surface: .metal)
        a.crate(at: Vec3(-26, 0, 24), size: 1.6, height: 1.6, surface: .metal)
        a.crate(at: Vec3(-20, 0, 28), size: 1.4, height: 1.4, surface: .wood)
        a.block(x: -34...(-14), z: 14...16, y: 5, height: 0.4, surface: .metal)   // pipe bridge

        // Connectors
        a.room(x: -8...8, z: -24...(-10), height: 5, doors: [.north, .south], windows: [.east, .west],
               ceiling: true, surface: .concrete)
        a.room(x: -8...8, z: 10...24, height: 5, doors: [.north, .south], windows: [.east, .west],
               ceiling: true, surface: .concrete)

        a.spawnCluster(center: Vec3(-28, 0, -30), yaw: 135, team: .strike, count: 5, spread: 2.0)
        a.spawnCluster(center: Vec3(28, 0, 30), yaw: -45, team: .shield, count: 5, spread: 2.0)
        for i in 0..<8 {
            let ang = Float(i) / 8 * 2 * .pi
            a.spawn(Vec3(cos(ang) * 24, 0, sin(ang) * 24), yaw: Float(i) * 45, team: .none)
        }

        a.light(Vec3(0, 10, 0), intensity: 1300, range: 36, colorHex: 0xBFD4FF, shadows: true)
        a.light(Vec3(24, 6, -25), intensity: 800, range: 20, colorHex: 0xFFC46B)
        a.light(Vec3(-24, 5, 24), intensity: 800, range: 20, colorHex: 0xFFC46B)
        a.light(Vec3(0, 7, -17), intensity: 600, range: 16, colorHex: 0x8FE3FF)

        a.pickup(.armor, at: Vec3(0, 5.6, 0))
        a.pickup(.health, at: Vec3(-24, 0, 20))
        a.pickup(.health, at: Vec3(24, 3.5, -24))
        a.pickup(.ammo, at: Vec3(0, 0, -17))
        a.pickup(.ammo, at: Vec3(0, 0, 17))
        a.pickup(.powerupShield, at: Vec3(-18, 0, -12))
        a.prop("prop_pipe_run", at: Vec3(0, 8, -20), yaw: 90)
        a.prop("prop_pipe_run", at: Vec3(0, 8, 20), yaw: 90)
        a.prop("prop_forklift", at: Vec3(10, 0, 6), yaw: 20, collides: true)
        a.prop("prop_barrel", at: Vec3(-12, 0, 4), collides: true)
        a.prop("prop_barrel", at: Vec3(-10.5, 0, 5.4), collides: true)

        a.callout("A Site", x: 14...34, z: -34...(-16))
        a.callout("B Site", x: -34...(-14), z: 14...34)
        a.callout("Catwalk", x: -32...32, z: -3...3)
        a.callout("North Connector", x: -10...10, z: -26...(-8))
        a.callout("South Connector", x: -10...10, z: 8...26)
        a.callout("Tanks", x: -24...(-12), z: -18...(-6))

        return MapData(
            id: "map_refinery", name: "Refinery",
            summary: "Stacked catwalks over a live fuel plant. Whoever owns the gantry owns the round.",
            bounds: bounds,
            environment: MapEnvironment(skyName: "sky_overcast", ambientColorHex: 0x4B5560,
                                        ambientIntensity: 240, fogColorHex: 0x8E9AA6,
                                        fogStart: 30, fogEnd: 150, fogDensity: 0.8,
                                        sunDirection: Vec3(0.2, -0.9, 0.38), sunColorHex: 0xD8E4F2,
                                        sunIntensity: 900, musicTrack: "mus_refinery",
                                        ambienceLoop: "amb_industrial"),
            brushes: a.brushes, props: a.props, lights: a.lights, spawns: a.spawns,
            bombSites: [ObjectiveZone(index: 0, name: "A", center: Vec3(24, 3.5, -25), radius: 7),
                        ObjectiveZone(index: 1, name: "B", center: Vec3(-24, 0, 24), radius: 7)],
            capturePoints: [ObjectiveZone(index: 0, name: "A", center: Vec3(24, 3.5, -25), radius: 5.5),
                            ObjectiveZone(index: 1, name: "B", center: Vec3(0, 5.4, 0), radius: 5.5),
                            ObjectiveZone(index: 2, name: "C", center: Vec3(-24, 0, 24), radius: 5.5)],
            hardpoints: [ObjectiveZone(index: 0, name: "Gantry", center: Vec3(0, 5.4, 0), radius: 6),
                         ObjectiveZone(index: 1, name: "A Platform", center: Vec3(24, 3.5, -25), radius: 6),
                         ObjectiveZone(index: 2, name: "B Floor", center: Vec3(-24, 0, 24), radius: 6)],
            pickups: a.pickups, callouts: a.callouts,
            supportedModes: GameModeKind.allCases, recommendedPlayers: PlayerRange(8, 10))
    }()

    // ══════════════════════════════════════════════════════════════════════
    // DOWNTOWN — night-time street grid. Symmetric, respawn-friendly, built for TDM/DOM.
    // ══════════════════════════════════════════════════════════════════════
    public static let downtown: MapData = {
        var a = MapAuthor()
        let bounds = AABB(min: Vec3(-40, -2, -40), max: Vec3(40, 28, 40))

        a.floor(x: -39...39, z: -39...39, surface: .concrete)
        a.skyboxClip(bounds: bounds)

        // City blocks on a 3x3 grid with streets between them.
        let blockCenters: [(Float, Float, Float)] = [
            (-24, -24, 9), (0, -24, 7), (24, -24, 9),
            (-24, 0, 7),               (24, 0, 7),
            (-24, 24, 9), (0, 24, 7), (24, 24, 9)
        ]
        for (cx, cz, h) in blockCenters {
            a.room(x: cx - 8...cx + 8, z: cz - 8...cz + 8, height: h,
                   doors: [.north, .south], windows: [.east, .west], ceiling: true, surface: .concrete)
            a.light(Vec3(cx, h - 1.2, cz), intensity: 420, range: 13, colorHex: 0xFFDCA8)
        }

        // Central plaza with a raised monument
        a.block(x: -5...5, z: -5...5, height: 0.6, surface: .tile)
        a.block(x: -1.5...1.5, z: -1.5...1.5, y: 0.6, height: 4, surface: .concrete)
        a.crate(at: Vec3(-6, 0, 6), size: 1.4, height: 1.4)
        a.crate(at: Vec3(6, 0, -6), size: 1.4, height: 1.4)

        // Street furniture for cover
        for (x, z) in [(-12, -12), (12, -12), (-12, 12), (12, 12), (0, -14), (0, 14), (-14, 0), (14, 0)] {
            a.crate(at: Vec3(Float(x), 0, Float(z)), size: 1.6, height: 1.3, surface: .metal)
        }
        for x in stride(from: Float(-36), through: 36, by: 12) {
            a.prop("prop_streetlight", at: Vec3(x, 0, -11.5), collides: true)
            a.prop("prop_streetlight", at: Vec3(x, 0, 11.5), collides: true)
            a.light(Vec3(x, 5.2, -11.5), intensity: 320, range: 11, colorHex: 0xCFE4FF)
            a.light(Vec3(x, 5.2, 11.5), intensity: 320, range: 11, colorHex: 0xCFE4FF)
        }
        a.prop("prop_car", at: Vec3(-18, 0, 4), yaw: 90, collides: true)
        a.prop("prop_car", at: Vec3(18, 0, -4), yaw: 90, collides: true)
        a.prop("prop_bus", at: Vec3(4, 0, -20), yaw: 0, collides: true)
        a.prop("prop_neon_sign", at: Vec3(-16, 6, -16), yaw: 45)

        a.spawnCluster(center: Vec3(0, 0, -34), yaw: 180, team: .strike, count: 6, spread: 2.4)
        a.spawnCluster(center: Vec3(0, 0, 34), yaw: 0, team: .shield, count: 6, spread: 2.4)
        for i in 0..<10 {
            let ang = Float(i) / 10 * 2 * .pi
            a.spawn(Vec3(cos(ang) * 28, 0, sin(ang) * 28), yaw: Float(i) * 36, team: .none)
        }

        a.light(Vec3(0, 12, 0), intensity: 700, range: 34, colorHex: 0x9FB6FF, shadows: true)
        a.pickup(.armor, at: Vec3(0, 0.6, 0))
        a.pickup(.health, at: Vec3(-24, 0, 0))
        a.pickup(.health, at: Vec3(24, 0, 0))
        a.pickup(.ammo, at: Vec3(0, 0, -24))
        a.pickup(.ammo, at: Vec3(0, 0, 24))
        a.pickup(.powerupSpeed, at: Vec3(-24, 0, 24))
        a.pickup(.powerupDamage, at: Vec3(24, 0, -24))

        a.callout("Plaza", x: -8...8, z: -8...8)
        a.callout("North Street", x: -39...39, z: -16...(-8))
        a.callout("South Street", x: -39...39, z: 8...16)
        a.callout("West Block", x: -34...(-14), z: -34...34)
        a.callout("East Block", x: 14...34, z: -34...34)

        return MapData(
            id: "map_downtown", name: "Downtown",
            summary: "Neon-lit city grid. Symmetric sightlines, endless flanks, no safe rotation.",
            bounds: bounds,
            environment: MapEnvironment(skyName: "sky_night_city", ambientColorHex: 0x2B3550,
                                        ambientIntensity: 190, fogColorHex: 0x1B2438,
                                        fogStart: 25, fogEnd: 120, fogDensity: 1.1,
                                        sunDirection: Vec3(0.3, -0.9, -0.3), sunColorHex: 0x7C8CC4,
                                        sunIntensity: 420, bloomThreshold: 0.62,
                                        musicTrack: "mus_downtown", ambienceLoop: "amb_city_night"),
            brushes: a.brushes, props: a.props, lights: a.lights, spawns: a.spawns,
            bombSites: [ObjectiveZone(index: 0, name: "A", center: Vec3(24, 0, -24), radius: 7),
                        ObjectiveZone(index: 1, name: "B", center: Vec3(-24, 0, 24), radius: 7)],
            capturePoints: [ObjectiveZone(index: 0, name: "A", center: Vec3(-24, 0, -24), radius: 6),
                            ObjectiveZone(index: 1, name: "B", center: Vec3(0, 0.6, 0), radius: 6),
                            ObjectiveZone(index: 2, name: "C", center: Vec3(24, 0, 24), radius: 6)],
            hardpoints: [ObjectiveZone(index: 0, name: "Plaza", center: Vec3(0, 0.6, 0), radius: 7),
                         ObjectiveZone(index: 1, name: "North Street", center: Vec3(0, 0, -24), radius: 6),
                         ObjectiveZone(index: 2, name: "South Street", center: Vec3(0, 0, 24), radius: 6),
                         ObjectiveZone(index: 3, name: "West Block", center: Vec3(-24, 0, 0), radius: 6)],
            pickups: a.pickups, callouts: a.callouts,
            supportedModes: GameModeKind.allCases, recommendedPlayers: PlayerRange(8, 12))
    }()

    // ══════════════════════════════════════════════════════════════════════
    // VAULT — tiny indoor arena for FFA / Gun Game / OITC. Sub-10-second engagements.
    // ══════════════════════════════════════════════════════════════════════
    public static let vault: MapData = {
        var a = MapAuthor()
        let bounds = AABB(min: Vec3(-22, -2, -22), max: Vec3(22, 16, 22))

        a.floor(x: -21...21, z: -21...21, surface: .tile)
        a.skyboxClip(bounds: bounds, height: 14)
        a.room(x: -21...21, z: -21...21, height: 6, ceiling: true, surface: .concrete)

        // Central vault block with four approaches
        a.block(x: -5...5, z: -5...5, height: 3.4, surface: .metal)
        a.stairs(x: -5...5, z: 5...9, from: 0, to: 3.4, steps: 7, surface: .metal)
        a.stairs(x: -5...5, z: -9...(-5), from: 3.4, to: 0, steps: 7, surface: .metal)

        // Ring of pillars and low cover
        for i in 0..<8 {
            let ang = Float(i) / 8 * 2 * .pi
            let p = Vec3(cos(ang) * 13, 0, sin(ang) * 13)
            if i % 2 == 0 {
                a.block(x: p.x - 1...p.x + 1, z: p.z - 1...p.z + 1, height: 6, surface: .concrete)
            } else {
                a.crate(at: p, size: 1.5, height: 1.3, surface: .metal)
            }
            a.light(Vec3(p.x * 0.7, 5.2, p.z * 0.7), intensity: 380, range: 12, colorHex: 0xFFE2B0)
        }

        // Side rooms
        a.room(x: -20...(-12), z: -20...(-12), height: 5, doors: [.east, .south], ceiling: true)
        a.room(x: 12...20, z: 12...20, height: 5, doors: [.west, .north], ceiling: true)

        for i in 0..<10 {
            let ang = Float(i) / 10 * 2 * .pi
            a.spawn(Vec3(cos(ang) * 17, 0, sin(ang) * 17), yaw: Float(i) * 36 + 180, team: .none)
        }
        a.spawnCluster(center: Vec3(0, 0, -18), yaw: 180, team: .strike, count: 4, spread: 2.0)
        a.spawnCluster(center: Vec3(0, 0, 18), yaw: 0, team: .shield, count: 4, spread: 2.0)

        a.light(Vec3(0, 5.5, 0), intensity: 900, range: 24, colorHex: 0xFFF0D0, shadows: true)
        a.pickup(.armor, at: Vec3(0, 3.4, 0))
        a.pickup(.health, at: Vec3(-16, 0, -16))
        a.pickup(.health, at: Vec3(16, 0, 16))
        a.pickup(.ammo, at: Vec3(-16, 0, 16))
        a.pickup(.ammo, at: Vec3(16, 0, -16))
        a.pickup(.powerupDamage, at: Vec3(0, 3.4, 8))
        a.prop("prop_server_rack", at: Vec3(-9, 0, 2), yaw: 90, collides: true)
        a.prop("prop_server_rack", at: Vec3(9, 0, -2), yaw: 90, collides: true)

        a.callout("Vault", x: -6...6, z: -6...6)
        a.callout("North Wing", x: -21...21, z: -21...(-8))
        a.callout("South Wing", x: -21...21, z: 8...21)

        return MapData(
            id: "map_vault", name: "Vault",
            summary: "A sealed bank floor. No sightline longer than 20 metres — reload at your own risk.",
            bounds: bounds,
            environment: MapEnvironment(skyName: "sky_indoor", ambientColorHex: 0x3E4450,
                                        ambientIntensity: 300, fogColorHex: 0x2A2F38,
                                        fogStart: 18, fogEnd: 70, fogDensity: 0.5,
                                        sunDirection: Vec3(0, -1, 0), sunColorHex: 0xBFC8D8,
                                        sunIntensity: 300, musicTrack: "mus_vault",
                                        ambienceLoop: "amb_hum"),
            brushes: a.brushes, props: a.props, lights: a.lights, spawns: a.spawns,
            bombSites: [ObjectiveZone(index: 0, name: "A", center: Vec3(-16, 0, -16), radius: 5),
                        ObjectiveZone(index: 1, name: "B", center: Vec3(16, 0, 16), radius: 5)],
            capturePoints: [ObjectiveZone(index: 0, name: "A", center: Vec3(-16, 0, -16), radius: 4.5),
                            ObjectiveZone(index: 1, name: "B", center: Vec3(0, 3.4, 0), radius: 4.5),
                            ObjectiveZone(index: 2, name: "C", center: Vec3(16, 0, 16), radius: 4.5)],
            hardpoints: [ObjectiveZone(index: 0, name: "Vault", center: Vec3(0, 3.4, 0), radius: 5),
                         ObjectiveZone(index: 1, name: "North Wing", center: Vec3(-14, 0, -14), radius: 5),
                         ObjectiveZone(index: 2, name: "South Wing", center: Vec3(14, 0, 14), radius: 5)],
            pickups: a.pickups, callouts: a.callouts,
            supportedModes: [.teamDeathmatch, .freeForAll, .gunGame, .oneInTheChamber,
                             .killConfirmed, .hardpoint, .domination, .zombies, .training],
            recommendedPlayers: PlayerRange(4, 8))
    }()

    // ══════════════════════════════════════════════════════════════════════
    // FROSTLINE — long-range snow map with a frozen river down the middle.
    // ══════════════════════════════════════════════════════════════════════
    public static let frostline: MapData = {
        var a = MapAuthor()
        let bounds = AABB(min: Vec3(-50, -4, -34), max: Vec3(50, 30, 34))

        a.floor(x: -49...49, z: -33...33, surface: .dirt)
        a.floor(x: -49...49, z: -5...5, y: -0.4, thickness: 0.6, surface: .water)   // frozen river
        a.skyboxClip(bounds: bounds)

        // Ridge lines north and south create the long duel lanes.
        a.block(x: -49...49, z: -33...(-28), height: 6, surface: .dirt)
        a.block(x: -49...49, z: 28...33, height: 6, surface: .dirt)

        // Two watchtowers — the sniper perches
        for side: Float in [-1, 1] {
            a.room(x: 26 * side - 4...26 * side + 4, z: -22...(-14), height: 4, doors: [.south],
                   ceiling: false, surface: .wood)
            a.stairs(x: 26 * side - 2...26 * side + 2, z: -14...(-10), from: 0, to: 4, steps: 8, surface: .wood)
            a.block(x: 26 * side - 4...26 * side + 4, z: -22...(-14), y: 4, height: 0.4, surface: .wood)
            a.wall(from: Vec3(26 * side - 4, 4.4, -22), to: Vec3(26 * side + 4, 4.4, -22),
                   height: 1.0, thickness: 0.3, surface: .wood)
        }

        // Cabins and cover scattered across the middle band
        a.room(x: -10...2, z: 10...20, height: 4.5, doors: [.north, .east], windows: [.west],
               ceiling: true, surface: .wood)
        a.room(x: 4...16, z: -20...(-10), height: 4.5, doors: [.south, .west], windows: [.east],
               ceiling: true, surface: .wood)
        for (x, z) in [(-30, 12), (-18, -8), (0, -18), (12, 16), (30, 8), (-6, 0), (18, -2), (-38, -4), (38, 2)] {
            a.crate(at: Vec3(Float(x), 0, Float(z)), size: 1.6, height: 1.4, surface: .wood)
        }
        for (x, z) in [(-34, 20), (-22, 24), (22, -24), (36, -18), (8, 24), (-12, -24)] {
            a.prop("prop_pine", at: Vec3(Float(x), 0, Float(z)), scale: 1.4, collides: true, surface: .wood)
            a.block(x: Float(x) - 0.4...Float(x) + 0.4, z: Float(z) - 0.4...Float(z) + 0.4,
                    height: 5, surface: .wood, blocksVision: false)
        }

        a.spawnCluster(center: Vec3(-44, 0, 0), yaw: -90, team: .strike, count: 5, spread: 2.4)
        a.spawnCluster(center: Vec3(44, 0, 0), yaw: 90, team: .shield, count: 5, spread: 2.4)
        for i in 0..<8 {
            a.spawn(Vec3(Float(i - 4) * 10, 0, i % 2 == 0 ? -24 : 24), yaw: i % 2 == 0 ? 0 : 180, team: .none)
        }

        a.light(Vec3(0, 14, 0), intensity: 900, range: 50, colorHex: 0xCFE6FF, shadows: true)
        a.light(Vec3(-26, 5, -18), intensity: 420, range: 14, colorHex: 0xFFC98A)
        a.light(Vec3(26, 5, -18), intensity: 420, range: 14, colorHex: 0xFFC98A)

        a.pickup(.armor, at: Vec3(0, 0, 0))
        a.pickup(.health, at: Vec3(-26, 0, -18))
        a.pickup(.health, at: Vec3(26, 0, -18))
        a.pickup(.ammo, at: Vec3(-4, 0, 15))
        a.pickup(.ammo, at: Vec3(10, 0, -15))
        a.pickup(.powerupShield, at: Vec3(0, 0, 24))

        a.callout("River", x: -49...49, z: -6...6)
        a.callout("West Tower", x: -32...(-20), z: -24...(-8))
        a.callout("East Tower", x: 20...32, z: -24...(-8))
        a.callout("North Ridge", x: -49...49, z: -33...(-20))
        a.callout("South Ridge", x: -49...49, z: 20...33)
        a.callout("Cabins", x: -12...18, z: -22...22)

        return MapData(
            id: "map_frostline", name: "Frostline",
            summary: "A frozen border crossing. Bring a scope — or bring smoke.",
            bounds: bounds,
            environment: MapEnvironment(skyName: "sky_snow_storm", ambientColorHex: 0x7E8EA0,
                                        ambientIntensity: 340, fogColorHex: 0xC3D2E0,
                                        fogStart: 35, fogEnd: 160, fogDensity: 1.4,
                                        sunDirection: Vec3(0.25, -0.8, 0.55), sunColorHex: 0xE6F0FF,
                                        sunIntensity: 1050, bloomThreshold: 0.9,
                                        musicTrack: "mus_frostline", ambienceLoop: "amb_blizzard"),
            brushes: a.brushes, props: a.props, lights: a.lights, spawns: a.spawns,
            bombSites: [ObjectiveZone(index: 0, name: "A", center: Vec3(-26, 0, -18), radius: 7),
                        ObjectiveZone(index: 1, name: "B", center: Vec3(26, 0, -18), radius: 7)],
            capturePoints: [ObjectiveZone(index: 0, name: "A", center: Vec3(-30, 0, 0), radius: 6),
                            ObjectiveZone(index: 1, name: "B", center: Vec3(0, 0, 0), radius: 6),
                            ObjectiveZone(index: 2, name: "C", center: Vec3(30, 0, 0), radius: 6)],
            hardpoints: [ObjectiveZone(index: 0, name: "River", center: Vec3(0, 0, 0), radius: 7),
                         ObjectiveZone(index: 1, name: "West Tower", center: Vec3(-26, 0, -18), radius: 6),
                         ObjectiveZone(index: 2, name: "East Tower", center: Vec3(26, 0, -18), radius: 6),
                         ObjectiveZone(index: 3, name: "Cabins", center: Vec3(-4, 0, 15), radius: 6)],
            pickups: a.pickups, callouts: a.callouts,
            supportedModes: GameModeKind.allCases, recommendedPlayers: PlayerRange(8, 12))
    }()
}
