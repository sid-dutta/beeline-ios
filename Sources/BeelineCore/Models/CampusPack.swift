import Foundation

// The data pack is produced by `beeline-api`'s pipeline. Keys are snake_case
// on disk and decoded with `.convertFromSnakeCase`, so property names here
// must match the converted form exactly.

public struct Coordinate: Codable, Hashable, Sendable {
    public var lat: Double
    public var lng: Double

    public init(lat: Double, lng: Double) {
        self.lat = lat
        self.lng = lng
    }

    /// Polygons and polylines are stored as `[[lat, lng], …]`.
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        lat = try c.decode(Double.self)
        lng = try c.decode(Double.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(lat)
        try c.encode(lng)
    }
}

public struct Entrance: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var lat: Double
    public var lng: Double
    public var accessible: Bool
    public var main: Bool
    public var name: String?
    public var source: String
    /// Walking-graph node this door is tied to; nil if it couldn't be attached.
    public var node: Int?
}

public struct Building: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var shortName: String
    public var aliases: [String]
    public var bldgNum: String?
    public var kind: String?
    public var levels: Int?
    public var lat: Double
    public var lng: Double
    public var polygon: [Coordinate]
    public var entrances: [Entrance]

    public var routableEntrances: [Entrance] { entrances.filter { $0.node != nil } }
}

public struct Meeting: Codable, Hashable, Sendable {
    public var course: String
    public var section: String
    public var crn: String
    public var title: String
    public var days: String
    /// Minutes since midnight.
    public var start: Int
    public var end: Int
    public var scheduleType: String
    public var instructors: [String]
}

public struct Room: Codable, Hashable, Sendable, Identifiable {
    public var buildingId: String
    public var room: String
    public var meetings: [Meeting]

    public var id: String { "\(buildingId)/\(room)" }
}

public struct Place: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: String
    public var lat: Double
    public var lng: Double
}

public struct GraphNode: Codable, Hashable, Sendable {
    public var id: Int
    public var lat: Double
    public var lng: Double

    public init(id: Int, lat: Double, lng: Double) {
        self.id = id
        self.lat = lat
        self.lng = lng
    }
}

public struct GraphEdge: Codable, Hashable, Sendable {
    public var a: Int
    public var b: Int
    /// Real length in meters.
    public var m: Double
    /// path | steps | road | link
    public var kind: String
    /// Meters × a preference multiplier; what the router minimizes.
    public var cost: Double
    public var accessible: Bool

    public init(a: Int, b: Int, m: Double, kind: String, cost: Double, accessible: Bool) {
        self.a = a
        self.b = b
        self.m = m
        self.kind = kind
        self.cost = cost
        self.accessible = accessible
    }
}

public struct Graph: Codable, Hashable, Sendable {
    public var nodes: [GraphNode]
    public var edges: [GraphEdge]

    public init(nodes: [GraphNode], edges: [GraphEdge]) {
        self.nodes = nodes
        self.edges = edges
    }
}

public struct BusStop: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var lat: Double
    public var lng: Double
    public var order: Int
    public var secondsToNext: Int?
}

public struct BusRoute: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var color: String
    public var hours: [String]
    public var polyline: [Coordinate]
    public var stops: [BusStop]
}

public struct BusData: Codable, Hashable, Sendable {
    public var routes: [BusRoute]

    public init(routes: [BusRoute]) {
        self.routes = routes
    }
}

public struct CampusPack: Codable, Sendable {
    public var packVersion: Int
    public var generatedAt: String
    public var term: String
    public var buildings: [Building]
    public var places: [Place]
    public var rooms: [Room]
    public var graph: Graph
    public var bus: BusData

    /// An empty pack, so the app can render a blank map instead of crashing
    /// if the bundled resource is ever missing.
    public static let empty = CampusPack(
        packVersion: 0,
        generatedAt: "",
        term: "",
        buildings: [],
        places: [],
        rooms: [],
        graph: Graph(nodes: [], edges: []),
        bus: BusData(routes: [])
    )

    public init(
        packVersion: Int,
        generatedAt: String,
        term: String,
        buildings: [Building],
        places: [Place],
        rooms: [Room],
        graph: Graph,
        bus: BusData
    ) {
        self.packVersion = packVersion
        self.generatedAt = generatedAt
        self.term = term
        self.buildings = buildings
        self.places = places
        self.rooms = rooms
        self.graph = graph
        self.bus = bus
    }

    public static func decode(_ data: Data) throws -> CampusPack {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CampusPack.self, from: data)
    }

    /// The pack bundled with this build of the app.
    public static func bundled() throws -> CampusPack {
        guard let url = Bundle.module.url(forResource: "campus", withExtension: "json") else {
            throw PackError.missingResource
        }
        return try decode(try Data(contentsOf: url))
    }

    public enum PackError: Error, LocalizedError {
        case missingResource
        public var errorDescription: String? { "The campus data pack is missing from the app bundle." }
    }
}
