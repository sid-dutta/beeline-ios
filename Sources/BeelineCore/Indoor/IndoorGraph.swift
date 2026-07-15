import Foundation

/// A hand-traced indoor graph, matching the format `beeline-api` produces.
///
/// Positions are 0–1 across whatever image was traced, so a graph survives
/// the image being re-rendered, and a floor with no image still routes — it
/// just can't be drawn.

public struct IndoorNode: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case corridor, door, room, stairs, elevator, entrance, restroom

        /// Kinds that carry you between floors.
        public var isVertical: Bool { self == .stairs || self == .elevator }
    }

    public var id: String
    public var x: Double
    public var y: Double
    public var kind: Kind
    public var room: String?
    public var name: String?
    public var accessible: Bool

    public init(
        id: String, x: Double, y: Double, kind: Kind,
        room: String? = nil, name: String? = nil, accessible: Bool = true
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.kind = kind
        self.room = room
        self.name = name
        self.accessible = accessible
    }

    // A graph traced against an older build may use a kind we don't know;
    // treat it as a plain corridor rather than failing the whole file.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .corridor
        room = try c.decodeIfPresent(String.self, forKey: .room)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        accessible = try c.decodeIfPresent(Bool.self, forKey: .accessible) ?? true
    }
}

public struct IndoorFloor: Codable, Hashable, Sendable, Identifiable {
    public var level: Int
    public var nodes: [IndoorNode]
    public var edges: [[String]]
    public var image: String?
    public var width: Int?
    public var height: Int?

    public var id: Int { level }

    public init(level: Int, nodes: [IndoorNode], edges: [[String]], image: String? = nil, width: Int? = nil, height: Int? = nil) {
        self.level = level
        self.nodes = nodes
        self.edges = edges
        self.image = image
        self.width = width
        self.height = height
    }

    public func node(_ id: String) -> IndoorNode? { nodes.first { $0.id == id } }

    public func room(_ number: String) -> IndoorNode? {
        nodes.first { $0.kind == .room && $0.room?.caseInsensitiveCompare(number) == .orderedSame }
    }
}

public struct IndoorGraph: Codable, Hashable, Sendable, Identifiable {
    public var buildingId: String
    public var floors: [IndoorFloor]
    /// `[fromLevel, fromNode, toLevel, toNode]` — the same stairwell or lift
    /// seen on two floors. Stored as strings so the JSON stays simple.
    public var links: [[LinkComponent]]
    public var source: String

    public var id: String { buildingId }

    public init(buildingId: String, floors: [IndoorFloor], links: [[LinkComponent]] = [], source: String = "traced") {
        self.buildingId = buildingId
        self.floors = floors
        self.links = links
        self.source = source
    }

    public func floor(level: Int) -> IndoorFloor? { floors.first { $0.level == level } }

    /// The floor a room is on, straight from the traced graph.
    public func floor(forRoom room: String) -> IndoorFloor? {
        floors.first { $0.room(room) != nil }
    }

    public var rooms: [String] {
        floors.flatMap { $0.nodes.compactMap(\.room) }.sorted()
    }

    /// Vertical links as typed pairs.
    public var connections: [(from: NodeRef, to: NodeRef)] {
        links.compactMap { link in
            guard link.count == 4,
                  let fromLevel = link[0].intValue, let toLevel = link[2].intValue else { return nil }
            return (
                NodeRef(level: fromLevel, id: link[1].stringValue),
                NodeRef(level: toLevel, id: link[3].stringValue)
            )
        }
    }

    // `links` and `source` are optional in the file format.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        buildingId = try c.decode(String.self, forKey: .buildingId)
        floors = try c.decodeIfPresent([IndoorFloor].self, forKey: .floors) ?? []
        links = try c.decodeIfPresent([[LinkComponent]].self, forKey: .links) ?? []
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "traced"
    }

    public static func decode(_ data: Data) throws -> IndoorGraph {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(IndoorGraph.self, from: data)
    }
}

/// A node on a particular floor.
public struct NodeRef: Hashable, Sendable {
    public var level: Int
    public var id: String

    public init(level: Int, id: String) {
        self.level = level
        self.id = id
    }
}

/// A link entry holds an Int level and a String node id in one array, so it
/// decodes as either.
public enum LinkComponent: Codable, Hashable, Sendable {
    case int(Int)
    case string(String)

    public var intValue: Int? {
        switch self {
        case .int(let value): value
        case .string(let value): Int(value)
        }
    }

    public var stringValue: String {
        switch self {
        case .int(let value): String(value)
        case .string(let value): value
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let value = try? c.decode(Int.self) { self = .int(value) }
        else { self = .string(try c.decode(String.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let value): try c.encode(value)
        case .string(let value): try c.encode(value)
        }
    }
}
