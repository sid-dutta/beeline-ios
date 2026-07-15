import XCTest
@testable import BeelineCore

final class PackTests: XCTestCase {

    private static let pack: CampusPack = {
        do { return try CampusPack.bundled() } catch { fatalError("pack missing: \(error)") }
    }()

    private var pack: CampusPack { Self.pack }

    func testPackLoadsWithExpectedShape() {
        XCTAssertEqual(pack.packVersion, 1)
        XCTAssertGreaterThan(pack.buildings.count, 300)
        XCTAssertGreaterThan(pack.graph.nodes.count, 10_000)
        XCTAssertGreaterThan(pack.graph.edges.count, 10_000)
        XCTAssertGreaterThan(pack.rooms.count, 300)
        XCTAssertEqual(pack.bus.routes.count, 9)
    }

    func testBuildingIDsAreUnique() {
        let ids = pack.buildings.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate building ids break every id lookup")
    }

    func testGraphIndicesAreValid() {
        let count = pack.graph.nodes.count
        for (i, node) in pack.graph.nodes.enumerated() {
            XCTAssertEqual(node.id, i, "nodes must be densely numbered for array indexing")
        }
        for edge in pack.graph.edges {
            XCTAssertTrue((0..<count).contains(edge.a) && (0..<count).contains(edge.b))
            XCTAssertGreaterThan(edge.m, 0)
        }
    }

    func testEveryRoomBelongsToAKnownBuilding() {
        let ids = Set(pack.buildings.map(\.id))
        for room in pack.rooms {
            XCTAssertTrue(ids.contains(room.buildingId), "orphan room \(room.id)")
            XCTAssertFalse(room.meetings.isEmpty)
        }
    }

    func testTeachingBuildingsHaveRoutableEntrances() {
        let taught = Set(pack.rooms.map(\.buildingId))
        for id in taught {
            let building = pack.buildings.first { $0.id == id }
            XCTAssertNotNil(building, id)
            XCTAssertFalse(building?.routableEntrances.isEmpty ?? true, "\(building?.name ?? id) has no routable door")
        }
    }

    func testKeyBuildingsResolveAndAreRoutable() {
        let index = SearchIndex(pack: pack)
        let router = Router(graph: pack.graph)
        for (query, room) in [("Klaus", "1443"), ("Clough", "144"), ("Skiles", "202"), ("Howey", "L3")] {
            guard case .building(let b)? = index.search(query).first else {
                return XCTFail("\(query) did not resolve to a building")
            }
            XCTAssertFalse(b.routableEntrances.isEmpty, "\(b.name) unroutable")
            XCTAssertTrue(
                pack.rooms.contains { $0.buildingId == b.id && $0.room == room },
                "\(b.name) should host room \(room)"
            )
        }
        guard case .building(let klaus)? = index.search("Klaus").first,
              case .building(let clough)? = index.search("Clough").first else {
            return XCTFail("lookup failed")
        }
        let result = router.route(
            fromAny: klaus.routableEntrances.compactMap(\.node),
            toAny: clough.routableEntrances.compactMap(\.node)
        )
        XCTAssertNotNil(result)
        XCTAssertLessThan(result?.route.meters ?? .infinity, 600)
        XCTAssertGreaterThan(result?.route.meters ?? 0, 50)
    }

    func testBusRoutesHaveGeometryAndStops() {
        for route in pack.bus.routes {
            XCTAssertGreaterThan(route.polyline.count, 10, route.name)
            XCTAssertGreaterThan(route.stops.count, 5, route.name)
            XCTAssertTrue(route.color.hasPrefix("#"), route.name)
            XCTAssertEqual(route.stops.map(\.order), route.stops.map(\.order).sorted())
        }
        XCTAssertTrue(pack.bus.routes.contains { $0.name == "Red" })
    }
}
