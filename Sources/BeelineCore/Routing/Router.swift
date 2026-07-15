import Foundation

public final class Router: Sendable {
    public struct Route: Sendable, Equatable {
        public var nodeIDs: [Int]
        public var coordinates: [Coordinate]
        public var meters: Double
        public var hasSteps: Bool
        public var roadMeters: Double

        public var minutes: Double {
            (meters / 1.35 / 60 * 2).rounded(.up) / 2
        }
    }

    private struct Adjacent {
        let to: Int
        let edge: Int
    }

    private let nodes: [GraphNode]
    private let edges: [GraphEdge]
    private let adjacency: [[Adjacent]]

    public init(graph: Graph) {
        nodes = graph.nodes
        edges = graph.edges
        var adj = [[Adjacent]](repeating: [], count: graph.nodes.count)
        for (i, e) in graph.edges.enumerated() {
            adj[e.a].append(Adjacent(to: e.b, edge: i))
            adj[e.b].append(Adjacent(to: e.a, edge: i))
        }
        adjacency = adj
    }

    public var nodeCount: Int { nodes.count }

    public func coordinate(of node: Int) -> Coordinate {
        Coordinate(lat: nodes[node].lat, lng: nodes[node].lng)
    }

    public func nearestNode(lat: Double, lng: Double, maxMeters: Double = 120) -> Int? {
        var best: (Int, Double)?
        for n in nodes {
            if abs(n.lat - lat) > 0.002 || abs(n.lng - lng) > 0.002 { continue }
            let d = Geo.distanceMeters(lat, lng, n.lat, n.lng)
            if d <= maxMeters, best == nil || d < best!.1 { best = (n.id, d) }
        }
        return best?.0
    }

    public func route(from start: Int, to goal: Int, accessible: Bool = false) -> Route? {
        guard start != goal else {
            return Route(nodeIDs: [start], coordinates: [coordinate(of: start)], meters: 0, hasSteps: false, roadMeters: 0)
        }
        let goalNode = nodes[goal]
        func h(_ n: Int) -> Double {
            Geo.distanceMeters(nodes[n].lat, nodes[n].lng, goalNode.lat, goalNode.lng)
        }

        var gScore = [Double](repeating: .infinity, count: nodes.count)
        var cameFrom = [Int](repeating: -1, count: nodes.count)
        var cameVia = [Int](repeating: -1, count: nodes.count)
        var closed = [Bool](repeating: false, count: nodes.count)
        var open = BinaryHeap()

        gScore[start] = 0
        open.push(start, priority: h(start))

        while let current = open.pop() {
            if current == goal { break }
            if closed[current] { continue }
            closed[current] = true
            for next in adjacency[current] {
                let e = edges[next.edge]
                if accessible && !e.accessible { continue }
                let tentative = gScore[current] + e.cost
                if tentative < gScore[next.to] {
                    gScore[next.to] = tentative
                    cameFrom[next.to] = current
                    cameVia[next.to] = next.edge
                    open.push(next.to, priority: tentative + h(next.to))
                }
            }
        }

        guard gScore[goal].isFinite else { return nil }

        var path = [goal]
        var meters = 0.0, roadMeters = 0.0, hasSteps = false
        var cursor = goal
        while cursor != start {
            let e = edges[cameVia[cursor]]
            meters += e.m
            if e.kind == "road" { roadMeters += e.m }
            if e.kind == "steps" { hasSteps = true }
            cursor = cameFrom[cursor]
            path.append(cursor)
        }
        path.reverse()
        return Route(
            nodeIDs: path,
            coordinates: path.map(coordinate(of:)),
            meters: meters,
            hasSteps: hasSteps,
            roadMeters: roadMeters
        )
    }

    public func route(fromAny starts: [Int], toAny goals: [Int], accessible: Bool = false) -> (route: Route, start: Int, goal: Int)? {
        var best: (Route, Int, Int)?
        for s in starts {
            for g in goals {
                if let r = route(from: s, to: g, accessible: accessible), best == nil || r.meters < best!.0.meters {
                    best = (r, s, g)
                }
            }
        }
        return best.map { (route: $0.0, start: $0.1, goal: $0.2) }
    }
}

struct BinaryHeap {
    private var items: [(node: Int, priority: Double)] = []

    mutating func push(_ node: Int, priority: Double) {
        items.append((node, priority))
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            if items[parent].priority <= items[i].priority { break }
            items.swapAt(parent, i)
            i = parent
        }
    }

    mutating func pop() -> Int? {
        guard !items.isEmpty else { return nil }
        let top = items[0].node
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var smallest = i
                if l < items.count, items[l].priority < items[smallest].priority { smallest = l }
                if r < items.count, items[r].priority < items[smallest].priority { smallest = r }
                if smallest == i { break }
                items.swapAt(i, smallest)
                i = smallest
            }
        }
        return top
    }
}
