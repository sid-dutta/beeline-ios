import XCTest
@testable import BeelineCore

final class RoutingTests: XCTestCase {

    private func ladder() -> Graph {
        let nodes = [
            GraphNode(id: 0, lat: 33.7750, lng: -84.3960),
            GraphNode(id: 1, lat: 33.7755, lng: -84.3960),
            GraphNode(id: 2, lat: 33.7760, lng: -84.3960),
            GraphNode(id: 3, lat: 33.7755, lng: -84.3950),
        ]
        let edges = [
            GraphEdge(a: 0, b: 1, m: 55, kind: "path", cost: 55, accessible: true),
            GraphEdge(a: 1, b: 2, m: 55, kind: "steps", cost: 63, accessible: false),
            GraphEdge(a: 0, b: 3, m: 105, kind: "road", cost: 147, accessible: true),
            GraphEdge(a: 3, b: 2, m: 105, kind: "road", cost: 147, accessible: true),
        ]
        return Graph(nodes: nodes, edges: edges)
    }

    func testShortestRouteUsesCostNotRawDistance() {
        let router = Router(graph: ladder())
        let route = router.route(from: 0, to: 2)
        XCTAssertNotNil(route)
        XCTAssertEqual(route?.nodeIDs, [0, 1, 2])
        XCTAssertEqual(route?.meters ?? 0, 110, accuracy: 0.001)
        XCTAssertTrue(route?.hasSteps ?? false)
    }

    func testAccessibleRoutingAvoidsSteps() {
        let router = Router(graph: ladder())
        let route = router.route(from: 0, to: 2, accessible: true)
        XCTAssertEqual(route?.nodeIDs, [0, 3, 2])
        XCTAssertFalse(route?.hasSteps ?? true)
        XCTAssertEqual(route?.roadMeters ?? 0, 210, accuracy: 0.001)
    }

    func testUnreachableGoalReturnsNil() {
        var graph = ladder()
        graph.nodes.append(GraphNode(id: 4, lat: 33.79, lng: -84.39))
        XCTAssertNil(Router(graph: graph).route(from: 0, to: 4))
    }

    func testSameNodeRouteIsEmptyButValid() {
        let route = Router(graph: ladder()).route(from: 1, to: 1)
        XCTAssertEqual(route?.meters, 0)
        XCTAssertEqual(route?.nodeIDs, [1])
    }

    func testRouteBetweenSetsPicksClosestPair() {
        let router = Router(graph: ladder())
        let result = router.route(fromAny: [0, 3], toAny: [2])
        XCTAssertEqual(result?.start, 3, "starting from the node nearer the goal wins")
        XCTAssertEqual(result?.route.meters ?? 0, 105, accuracy: 0.001)
    }

    func testNearestNodeRespectsRadius() {
        let router = Router(graph: ladder())
        XCTAssertEqual(router.nearestNode(lat: 33.7751, lng: -84.3960, maxMeters: 50), 0)
        XCTAssertNil(router.nearestNode(lat: 33.7900, lng: -84.3960, maxMeters: 50))
    }

    func testWalkingTimeRoundsToHalfMinutes() {
        let route = Router.Route(nodeIDs: [], coordinates: [], meters: 405, hasSteps: false, roadMeters: 0)
        XCTAssertEqual(route.minutes, 5.0, accuracy: 0.001)
    }

    func testDirectionsProduceDepartTurnArrive() {
        let path = [
            Coordinate(lat: 33.7750, lng: -84.3960),
            Coordinate(lat: 33.7760, lng: -84.3960),
            Coordinate(lat: 33.7760, lng: -84.3950),
        ]
        let steps = Directions.steps(for: path, destinationName: "Klaus", entranceName: "the west door")
        XCTAssertEqual(steps.count, 3)
        XCTAssertEqual(steps[0].kind, .depart)
        XCTAssertTrue(steps[0].text.contains("north"), steps[0].text)
        XCTAssertEqual(steps[1].kind, .right)
        XCTAssertEqual(steps[2].kind, .arrive)
        XCTAssertEqual(steps[2].text, "Enter Klaus at the west door")
    }

    func testDirectionsMergeInsignificantWiggles() {
        let path = [
            Coordinate(lat: 33.7750, lng: -84.3960),
            Coordinate(lat: 33.7755, lng: -84.3960),
            Coordinate(lat: 33.7760, lng: -84.39595),
        ]
        let steps = Directions.steps(for: path, destinationName: "Skiles")
        XCTAssertEqual(steps.count, 2, "one leg plus arrival")
        XCTAssertEqual(steps.last?.text, "Arrive at Skiles")
    }

    func testDistanceFormatting() {
        XCTAssertEqual(Directions.format(20), "70 ft")
        XCTAssertEqual(Directions.format(100), "350 ft")
        XCTAssertEqual(Directions.format(2000), "1.2 mi")
    }

    func testBearingAndTurnAngle() {
        XCTAssertEqual(Geo.bearing(33.775, -84.396, 33.776, -84.396), 0, accuracy: 0.5)
        XCTAssertEqual(Geo.bearing(33.775, -84.396, 33.775, -84.395), 90, accuracy: 0.5)
        XCTAssertEqual(Geo.turnAngle(from: 350, to: 10), 20, accuracy: 0.001)
        XCTAssertEqual(Geo.turnAngle(from: 10, to: 350), -20, accuracy: 0.001)
        XCTAssertEqual(Geo.compassName(0), "north")
        XCTAssertEqual(Geo.compassName(225), "southwest")
    }

    func testPointInPolygon() {
        let square = [
            Coordinate(lat: 0, lng: 0), Coordinate(lat: 0, lng: 1),
            Coordinate(lat: 1, lng: 1), Coordinate(lat: 1, lng: 0),
        ]
        XCTAssertTrue(Geo.contains(square, lat: 0.5, lng: 0.5))
        XCTAssertFalse(Geo.contains(square, lat: 1.5, lng: 0.5))
    }
}
