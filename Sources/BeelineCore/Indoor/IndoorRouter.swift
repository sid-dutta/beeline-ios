import Foundation

public struct IndoorRouter: Sendable {

    // Costs are in traced-image units (0-1 across a floor), not meters.
    public static let stairsCost = 0.6
    public static let elevatorCost = 0.75

    public struct Path: Sendable, Equatable {
        public var nodes: [NodeRef]
        public var cost: Double
        public var usesStairs: Bool
        public var usesElevator: Bool

        public var levels: [Int] {
            var seen: [Int] = []
            for node in nodes where seen.last != node.level { seen.append(node.level) }
            return seen
        }
    }

    private let graph: IndoorGraph
    private let nodesByRef: [NodeRef: IndoorNode]
    private let adjacency: [NodeRef: [(NodeRef, Double, Bool)]]

    public init(graph: IndoorGraph) {
        self.graph = graph

        var nodes: [NodeRef: IndoorNode] = [:]
        for floor in graph.floors {
            for node in floor.nodes {
                nodes[NodeRef(level: floor.level, id: node.id)] = node
            }
        }
        self.nodesByRef = nodes

        var adjacency: [NodeRef: [(NodeRef, Double, Bool)]] = [:]
        for floor in graph.floors {
            for edge in floor.edges where edge.count == 2 {
                let a = NodeRef(level: floor.level, id: edge[0])
                let b = NodeRef(level: floor.level, id: edge[1])
                guard let na = nodes[a], let nb = nodes[b] else { continue }
                let d = hypot(na.x - nb.x, na.y - nb.y)
                adjacency[a, default: []].append((b, d, false))
                adjacency[b, default: []].append((a, d, false))
            }
        }
        for (from, to) in graph.connections {
            guard let node = nodes[from], nodes[to] != nil else { continue }
            let cost = node.kind == .elevator ? Self.elevatorCost : Self.stairsCost
            adjacency[from, default: []].append((to, cost, true))
            adjacency[to, default: []].append((from, cost, true))
        }
        self.adjacency = adjacency
    }

    public func node(_ ref: NodeRef) -> IndoorNode? { nodesByRef[ref] }

    public var entrances: [NodeRef] {
        graph.floors.flatMap { floor in
            floor.nodes.filter { $0.kind == .entrance }.map { NodeRef(level: floor.level, id: $0.id) }
        }
    }

    public func roomRef(_ number: String) -> NodeRef? {
        for floor in graph.floors {
            if let node = floor.room(number) { return NodeRef(level: floor.level, id: node.id) }
        }
        return nil
    }

    public func path(from start: NodeRef, to goal: NodeRef, accessible: Bool = false) -> Path? {
        guard nodesByRef[start] != nil, nodesByRef[goal] != nil else { return nil }
        if start == goal {
            return Path(nodes: [start], cost: 0, usesStairs: false, usesElevator: false)
        }

        var best: [NodeRef: Double] = [start: 0]
        var cameFrom: [NodeRef: NodeRef] = [:]
        var visited: Set<NodeRef> = []
        var frontier: [(NodeRef, Double)] = [(start, 0)]

        while !frontier.isEmpty {
            frontier.sort { $0.1 > $1.1 }
            let (current, cost) = frontier.removeLast()
            if current == goal { break }
            if !visited.insert(current).inserted { continue }

            for (next, step, _) in adjacency[current] ?? [] {
                guard let node = nodesByRef[next] else { continue }
                if accessible, node.kind == .stairs || !node.accessible { continue }
                let candidate = cost + step
                if candidate < best[next] ?? .infinity {
                    best[next] = candidate
                    cameFrom[next] = current
                    frontier.append((next, candidate))
                }
            }
        }

        guard let total = best[goal] else { return nil }
        var path = [goal]
        var cursor = goal
        while cursor != start {
            guard let previous = cameFrom[cursor] else { return nil }
            path.append(previous)
            cursor = previous
        }
        path.reverse()

        let kinds = path.compactMap { nodesByRef[$0]?.kind }
        return Path(
            nodes: path,
            cost: total,
            usesStairs: kinds.contains(.stairs),
            usesElevator: kinds.contains(.elevator)
        )
    }

    public func pathToRoom(_ number: String, accessible: Bool = false) -> Path? {
        guard let goal = roomRef(number) else { return nil }
        return entrances
            .compactMap { path(from: $0, to: goal, accessible: accessible) }
            .min { $0.cost < $1.cost }
    }
}
