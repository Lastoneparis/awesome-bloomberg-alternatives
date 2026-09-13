import Foundation

/// Navigation graph. Maps do not hand-author nav data: it is baked at load time by
/// sampling a grid over the playable bounds, dropping each sample onto the floor and
/// linking neighbours that a player could actually walk between. Baking a 90x90m map
/// at 2m spacing is ~2000 nodes and takes a few milliseconds.
public final class NavGraph: @unchecked Sendable {
    public struct Node: Sendable {
        public var position: Vec3
        public var links: [Int32]
        public var isCover: Bool
        public var isOpen: Bool         // exposed to long sightlines
        public var callout: String
        public var objectiveIndex: Int?
    }

    public private(set) var nodes: [Node] = []
    private let cellSize: Float
    private let origin: Vec3
    private let dim: (x: Int, z: Int)
    private var lookup: [Int32]         // grid cell -> node index (-1 empty)

    public static let playerRadius: Float = 0.42
    public static let playerHeight: Float = 1.8
    public static let maxStepHeight: Float = 0.55

    public init(map: MapData, world: CollisionWorld, spacing: Float = 2.0) {
        self.cellSize = spacing
        self.origin = map.bounds.min
        let size = map.bounds.size
        self.dim = (max(1, Int(size.x / spacing)), max(1, Int(size.z / spacing)))
        self.lookup = Array(repeating: -1, count: dim.x * dim.z)
        bake(map: map, world: world)
    }

    private func gridIndex(_ ix: Int, _ iz: Int) -> Int { iz * dim.x + ix }

    private func bake(map: MapData, world: CollisionWorld) {
        let top = map.bounds.max.y
        var built: [Node] = []
        built.reserveCapacity(dim.x * dim.z)

        // 1. Sample the floor.
        for iz in 0..<dim.z {
            for ix in 0..<dim.x {
                let x = origin.x + (Float(ix) + 0.5) * cellSize
                let z = origin.z + (Float(iz) + 0.5) * cellSize
                guard let groundY = world.groundHeight(below: Vec3(x, top - 0.5, z),
                                                       maxDrop: top - map.bounds.min.y) else { continue }
                let feet = Vec3(x, groundY + 0.02, z)
                // Reject spots where a player would not fit.
                let body = AABB(min: feet + Vec3(-NavGraph.playerRadius, 0.1, -NavGraph.playerRadius),
                                max: feet + Vec3(NavGraph.playerRadius, NavGraph.playerHeight, NavGraph.playerRadius))
                if world.overlaps(box: body, mask: .solid) { continue }

                let eye = feet + Vec3(0, 1.6, 0)
                // "Cover" = at least one adjacent direction is blocked at chest height.
                var blocked = 0
                for dir in [Vec3(1, 0, 0), Vec3(-1, 0, 0), Vec3(0, 0, 1), Vec3(0, 0, -1)] {
                    if world.trace(from: eye - Vec3(0, 0.5, 0),
                                   to: eye - Vec3(0, 0.5, 0) + dir * 1.6, mask: .solid).hit { blocked += 1 }
                }
                lookup[gridIndex(ix, iz)] = Int32(built.count)
                built.append(Node(position: feet, links: [], isCover: blocked >= 1,
                                  isOpen: blocked == 0, callout: map.callout(at: feet),
                                  objectiveIndex: nil))
            }
        }

        // 2. Link 8-neighbourhood where the step is walkable and the path is clear.
        let neighbourOffsets: [(Int, Int)] = [(1, 0), (-1, 0), (0, 1), (0, -1),
                                              (1, 1), (1, -1), (-1, 1), (-1, -1)]
        for iz in 0..<dim.z {
            for ix in 0..<dim.x {
                let idx = lookup[gridIndex(ix, iz)]
                guard idx >= 0 else { continue }
                let from = built[Int(idx)]
                for (dx, dz) in neighbourOffsets {
                    let nx = ix + dx, nz = iz + dz
                    guard nx >= 0, nx < dim.x, nz >= 0, nz < dim.z else { continue }
                    let nIdx = lookup[gridIndex(nx, nz)]
                    guard nIdx >= 0 else { continue }
                    let to = built[Int(nIdx)]
                    guard abs(to.position.y - from.position.y) <= NavGraph.maxStepHeight else { continue }
                    // Trace at knee height so waist-high cover correctly blocks the link.
                    let a = from.position + Vec3(0, 0.9, 0)
                    let b = to.position + Vec3(0, 0.9, 0)
                    if world.trace(from: a, to: b, mask: .solid).hit { continue }
                    built[Int(idx)].links.append(nIdx)
                }
            }
        }

        // 3. Tag nodes that sit inside objectives so bots can path to them directly.
        func tag(_ zones: [ObjectiveZone]) {
            for zone in zones {
                for i in built.indices where zone.contains(built[i].position) {
                    built[i].objectiveIndex = zone.index
                }
            }
        }
        tag(map.bombSites)
        tag(map.capturePoints)
        tag(map.hardpoints)

        nodes = built
        Log.info("Baked nav graph: \(nodes.count) nodes, \(nodes.reduce(0) { $0 + $1.links.count }) links",
                 category: "nav")
    }

    public var isEmpty: Bool { nodes.isEmpty }

    public func nearestNode(to p: Vec3, maxDistance: Float = 12) -> Int? {
        var best = -1
        var bestD = maxDistance * maxDistance
        // Search outward from the containing cell before falling back to a linear scan.
        let ix = MathUtil.clamp(Int((p.x - origin.x) / cellSize), 0, dim.x - 1)
        let iz = MathUtil.clamp(Int((p.z - origin.z) / cellSize), 0, dim.z - 1)
        let ring = max(1, Int(maxDistance / cellSize))
        for dz in -ring...ring {
            for dx in -ring...ring {
                let nx = ix + dx, nz = iz + dz
                guard nx >= 0, nx < dim.x, nz >= 0, nz < dim.z else { continue }
                let idx = lookup[gridIndex(nx, nz)]
                guard idx >= 0 else { continue }
                let d = nodes[Int(idx)].position.distanceSquared(to: p)
                if d < bestD { bestD = d; best = Int(idx) }
            }
        }
        return best >= 0 ? best : nil
    }

    /// A* over the baked graph. Returns world positions, start excluded.
    /// A* over the baked graph.
    ///
    /// The open set is a binary heap and every score is an array indexed by node, because
    /// the obvious version is quadratic with a brutal constant: a linear scan for the best
    /// node, a dictionary lookup for each element of that scan, `openSet.contains` for
    /// every neighbour, and `remove(at:)` shifting the array on every expansion. On a
    /// hundred-metre map that is a couple of thousand nodes and millions of dictionary
    /// lookups per path — fine in a demo, not fine when ten bots repath during a firefight.
    ///
    /// Entries carry their own priority rather than reading it back from `fScore`, so
    /// lowering a node's score cannot corrupt the ordering of entries already in the heap.
    /// Stale entries are simply skipped when popped.
    public func findPath(from start: Vec3, to goal: Vec3, maxNodes: Int = 4000) -> [Vec3] {
        guard let s = nearestNode(to: start), let g = nearestNode(to: goal) else { return [] }
        if s == g { return [nodes[g].position] }

        let count = nodes.count
        var gScore = [Float](repeating: .greatestFiniteMagnitude, count: count)
        var cameFrom = [Int32](repeating: -1, count: count)
        var closed = [Bool](repeating: false, count: count)

        var heap: [(priority: Float, node: Int)] = []
        heap.reserveCapacity(64)

        func push(_ node: Int, _ priority: Float) {
            heap.append((priority, node))
            var index = heap.count - 1
            while index > 0 {
                let parent = (index - 1) / 2
                if heap[parent].priority <= heap[index].priority { break }
                heap.swapAt(parent, index)
                index = parent
            }
        }

        func pop() -> Int {
            let top = heap[0].node
            heap[0] = heap[heap.count - 1]
            heap.removeLast()
            var index = 0
            while true {
                let left = index * 2 + 1, right = left + 1
                var smallest = index
                if left < heap.count, heap[left].priority < heap[smallest].priority {
                    smallest = left
                }
                if right < heap.count, heap[right].priority < heap[smallest].priority {
                    smallest = right
                }
                if smallest == index { break }
                heap.swapAt(index, smallest)
                index = smallest
            }
            return top
        }

        gScore[s] = 0
        push(s, heuristic(s, g))
        var expanded = 0

        while !heap.isEmpty && expanded < maxNodes {
            let current = pop()
            if current == g { return reconstruct(cameFrom, from: g) }
            if closed[current] { continue }
            closed[current] = true
            expanded += 1

            for linkRaw in nodes[current].links {
                let n = Int(linkRaw)
                if closed[n] { continue }
                let step = nodes[current].position.distance(to: nodes[n].position)
                // Prefer cover: bots hugging walls read as far more competent.
                let penalty: Float = nodes[n].isOpen ? 0.6 : 0
                let tentative = gScore[current] + step + penalty
                if tentative < gScore[n] {
                    cameFrom[n] = Int32(current)
                    gScore[n] = tentative
                    push(n, tentative + heuristic(n, g))
                }
            }
        }
        return []
    }

    private func heuristic(_ a: Int, _ b: Int) -> Float {
        nodes[a].position.distance(to: nodes[b].position)
    }

    private func reconstruct(_ cameFrom: [Int32], from end: Int) -> [Vec3] {
        var path: [Vec3] = [nodes[end].position]
        var current = end
        while cameFrom[current] >= 0 {
            current = Int(cameFrom[current])
            path.append(nodes[current].position)
        }
        path.removeLast()               // drop the start node
        return path.reversed()
    }

    /// Nearest node flagged as cover, preferring ones away from a threat.
    public func nearestCover(to position: Vec3, awayFrom threat: Vec3, searchRadius: Float = 14,
                             world: CollisionWorld) -> Vec3? {
        var best: Vec3?
        var bestScore = -Float.greatestFiniteMagnitude
        for node in nodes where node.isCover {
            let d = node.position.distance(to: position)
            guard d < searchRadius else { continue }
            let hidden = !world.hasLineOfSight(from: node.position + Vec3(0, 1.5, 0),
                                               to: threat + Vec3(0, 1.5, 0))
            let score = (hidden ? 40 : 0) - d + node.position.distance(to: threat) * 0.25
            if score > bestScore { bestScore = score; best = node.position }
        }
        return best
    }

    public func nodes(forObjective index: Int) -> [Vec3] {
        nodes.filter { $0.objectiveIndex == index }.map(\.position)
    }

    public func randomNode(rng: inout DeterministicRandom) -> Vec3? {
        guard !nodes.isEmpty else { return nil }
        return nodes[rng.int(in: 0...(nodes.count - 1))].position
    }
}
