import Foundation

/// Collision and navigation data for a map, built once and shared.
///
/// Both are pure functions of a map's immutable geometry, and both are read-only after
/// construction — `findPath` keeps every piece of its scratch state on the stack — so
/// there is no reason for each match to rebake them. Baking the nav mesh is the expensive
/// part of starting one: a ground trace, a fit test and four cover traces for every cell
/// of a two-metre grid over the whole map, which is a couple of thousand traces before a
/// single player has spawned.
///
/// A server hosting back-to-back rounds on the same map paid that every round, and the
/// test suite paid it for every simulation it constructed.
public enum MapWorldCache {
    private static let lock = NSLock()
    private static var worlds: [String: CollisionWorld] = [:]
    private static var navs: [String: NavGraph] = [:]

    /// Keyed by id *and* brush count: authored maps in tests reuse ids freely, and handing
    /// one of those a collision world baked from different geometry would be far worse
    /// than rebuilding.
    private static func key(_ map: MapData) -> String {
        "\(map.id.value)#\(map.brushes.count)"
    }

    public static func world(for map: MapData) -> CollisionWorld {
        lock.lock()
        defer { lock.unlock() }
        if let cached = worlds[key(map)] { return cached }
        let world = CollisionWorld(map: map)
        worlds[key(map)] = world
        return world
    }

    public static func nav(for map: MapData, world: CollisionWorld) -> NavGraph {
        lock.lock()
        defer { lock.unlock() }
        if let cached = navs[key(map)] { return cached }
        let nav = NavGraph(map: map, world: world)
        navs[key(map)] = nav
        return nav
    }

    /// Everything cached, dropped. Nothing in the game needs this — the data cannot go
    /// stale, because a `MapData` cannot change — but a long-lived tool that walks every
    /// map can use it to give the memory back.
    public static func clear() {
        lock.lock()
        defer { lock.unlock() }
        worlds.removeAll()
        navs.removeAll()
    }

    public static var cachedMapCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return worlds.count
    }
}
