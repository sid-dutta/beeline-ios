import XCTest
@testable import BeelineCore

final class TripPlannerTests: XCTestCase {

    /// A straight north-south footpath with 6 nodes ~110 m apart, and a bus
    /// route whose stops sit beside nodes 0, 2 and 5.
    private func fixture() -> (Router, [BusRoute]) {
        let nodes = (0..<6).map { GraphNode(id: $0, lat: 33.7700 + Double($0) * 0.001, lng: -84.3960) }
        let edges = (0..<5).map {
            GraphEdge(a: $0, b: $0 + 1, m: 111, kind: "path", cost: 111, accessible: true)
        }
        let router = Router(graph: Graph(nodes: nodes, edges: edges))

        let stops = [
            BusStop(id: 10, name: "South Stop", lat: 33.7700, lng: -84.3960, order: 0, secondsToNext: 60),
            BusStop(id: 11, name: "Mid Stop", lat: 33.7720, lng: -84.3960, order: 1, secondsToNext: 60),
            BusStop(id: 12, name: "North Stop", lat: 33.7750, lng: -84.3960, order: 2, secondsToNext: 60),
        ]
        let route = BusRoute(id: 1, name: "Red", color: "#ff0000", hours: [], polyline: [], stops: stops)
        return (router, [route])
    }

    private func arrivals(_ seconds: [Int], stop: Int = 10) -> [StopArrival] {
        seconds.map { StopArrival(routeID: 1, routeStopID: stop, vehicleID: 1, secondsToStop: $0, onRoute: true) }
    }

    // MARK: Walking baseline

    func testWalkOnlyWhenNoBusHelps() {
        let (router, routes) = fixture()
        let planner = TripPlanner(router: router, routes: routes)
        // No live arrivals at all → no bus option can be offered.
        let trips = planner.plan(fromLat: 33.7700, lng: -84.3960, toNodes: [5], destinationName: "Klaus")
        XCTAssertEqual(trips.count, 1)
        XCTAssertTrue(trips[0].isWalkOnly)
        XCTAssertGreaterThan(trips[0].totalSeconds, 0)
        XCTAssertEqual(trips[0].walkingMeters, 555, accuracy: 1)
    }

    func testBusOfferedWhenItSavesRealTime() {
        let (router, routes) = fixture()
        let planner = TripPlanner(router: router, routes: routes)
        // Bus arrives in 30 s and covers the whole way in 120 s; walking is ~410 s.
        let trips = planner.plan(
            fromLat: 33.7700, lng: -84.3960,
            toNodes: [5], destinationName: "Klaus",
            arrivals: arrivals([30])
        )
        XCTAssertEqual(trips.count, 2)
        XCTAssertEqual(trips[0].routeName, "Red", "the faster bus trip sorts first")
        XCTAssertTrue(trips[1].isWalkOnly)
        XCTAssertLessThan(trips[0].totalSeconds, trips[1].totalSeconds)
    }

    func testBusIsNotOfferedWhenTheSavingIsTrivial() {
        let (router, routes) = fixture()
        let planner = TripPlanner(router: router, routes: routes)
        // A bus 6 minutes out cannot beat a 7-minute walk by a useful margin.
        let trips = planner.plan(
            fromLat: 33.7700, lng: -84.3960,
            toNodes: [5], destinationName: "Klaus",
            arrivals: arrivals([360])
        )
        XCTAssertEqual(trips.count, 1)
        XCTAssertTrue(trips[0].isWalkOnly)
    }

    func testABusWeCannotReachIsNotOffered() {
        let (router, routes) = fixture()
        let planner = TripPlanner(router: router, routes: routes)
        // Start 3 nodes up the path: ~250 m, ~185 s of walking to the south
        // stop. A bus arriving in 10 s is already gone.
        let wait = planner.waitSeconds(routeID: 1, stopID: 10, afterWalking: 185, arrivals: arrivals([10]))
        XCTAssertNil(wait)
        // But one arriving after we get there is catchable, and the wait is
        // the difference.
        let ok = planner.waitSeconds(routeID: 1, stopID: 10, afterWalking: 185, arrivals: arrivals([10, 300]))
        XCTAssertEqual(ok ?? -1, 115, accuracy: 0.001)
    }

    // MARK: Ride mechanics

    func testRideSecondsSumsTheHops() {
        let (_, routes) = fixture()
        let planner = TripPlanner(router: Router(graph: Graph(nodes: [], edges: [])), routes: routes)
        let route = routes[0]
        XCTAssertEqual(planner.rideSeconds(route: route, from: route.stops[0], to: route.stops[2]) ?? 0, 120, accuracy: 0.001)
        XCTAssertEqual(planner.rideSeconds(route: route, from: route.stops[0], to: route.stops[1]) ?? 0, 60, accuracy: 0.001)
        XCTAssertNil(planner.rideSeconds(route: route, from: route.stops[0], to: route.stops[0]))
    }

    func testRideWrapsAroundALoopRoute() {
        let (_, routes) = fixture()
        let planner = TripPlanner(router: Router(graph: Graph(nodes: [], edges: [])), routes: routes)
        let route = routes[0]
        // North (order 2) back around to Mid (order 1) is two hops on a loop.
        XCTAssertEqual(planner.rideSeconds(route: route, from: route.stops[2], to: route.stops[1]) ?? 0, 120, accuracy: 0.001)
        XCTAssertEqual(planner.stopCount(route: route, from: route.stops[2], to: route.stops[1]), 2)
    }

    func testRideNeedsTimingData() {
        var stops = [
            BusStop(id: 1, name: "A", lat: 33.77, lng: -84.39, order: 0, secondsToNext: nil),
            BusStop(id: 2, name: "B", lat: 33.78, lng: -84.39, order: 1, secondsToNext: 60),
        ]
        let route = BusRoute(id: 9, name: "Ghost", color: "#000", hours: [], polyline: [], stops: stops)
        let planner = TripPlanner(router: Router(graph: Graph(nodes: [], edges: [])), routes: [route])
        XCTAssertNil(planner.rideSeconds(route: route, from: stops[0], to: stops[1]), "missing timing must not be guessed")
        stops[0].secondsToNext = 45
        let fixed = BusRoute(id: 9, name: "Ghost", color: "#000", hours: [], polyline: [], stops: stops)
        XCTAssertEqual(planner.rideSeconds(route: fixed, from: stops[0], to: stops[1]) ?? 0, 45, accuracy: 0.001)
    }

    func testRidePathFollowsTheStopsInOrder() {
        let (_, routes) = fixture()
        let planner = TripPlanner(router: Router(graph: Graph(nodes: [], edges: [])), routes: routes)
        let route = routes[0]
        let path = planner.ridePath(route: route, from: route.stops[0], to: route.stops[2])
        XCTAssertEqual(path.count, 3)
        XCTAssertEqual(path.first?.lat, 33.7700)
        XCTAssertEqual(path.last?.lat, 33.7750)
    }

    // MARK: Trip shape

    func testBusTripHasWalkWaitRideWalk() {
        let (router, routes) = fixture()
        let planner = TripPlanner(router: router, routes: routes)
        let trips = planner.plan(
            fromLat: 33.7700, lng: -84.3960,
            toNodes: [5], destinationName: "Klaus",
            arrivals: arrivals([30])
        )
        guard let bus = trips.first(where: { !$0.isWalkOnly }) else { return XCTFail("expected a bus trip") }
        XCTAssertEqual(bus.legs.count, 4)
        if case .wait(let seconds, let name, _) = bus.legs[1] {
            XCTAssertEqual(seconds, 30, accuracy: 1)
            XCTAssertEqual(name, "Red")
        } else {
            XCTFail("second leg should be the wait")
        }
        if case .ride(_, _, let board, let alight, _, let stops, _) = bus.legs[2] {
            XCTAssertEqual(board, "South Stop")
            XCTAssertEqual(alight, "North Stop")
            XCTAssertEqual(stops, 2)
        } else {
            XCTFail("third leg should be the ride")
        }
        XCTAssertFalse(bus.coordinates.isEmpty)
        XCTAssertEqual(bus.minutes, max(1, Int((bus.totalSeconds / 60).rounded())))
    }

    func testUnreachableStartYieldsNothing() {
        let (router, routes) = fixture()
        let planner = TripPlanner(router: router, routes: routes)
        XCTAssertTrue(planner.plan(fromLat: 34.5, lng: -84.0, toNodes: [5], destinationName: "Klaus").isEmpty)
    }
}
