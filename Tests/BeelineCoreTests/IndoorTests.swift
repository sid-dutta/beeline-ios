import XCTest
@testable import BeelineCore

final class IndoorTests: XCTestCase {

    private func graph(accessibleStairs: Bool = false) -> IndoorGraph {
        let floor1 = IndoorFloor(
            level: 1,
            nodes: [
                IndoorNode(id: "e", x: 0.5, y: 0.95, kind: .entrance, name: "the main entrance"),
                IndoorNode(id: "c1", x: 0.5, y: 0.7, kind: .corridor),
                IndoorNode(id: "c2", x: 0.5, y: 0.4, kind: .corridor),
                IndoorNode(id: "r101", x: 0.2, y: 0.7, kind: .room, room: "101"),
                IndoorNode(id: "s1", x: 0.8, y: 0.4, kind: .stairs, accessible: accessibleStairs),
                IndoorNode(id: "l1", x: 0.9, y: 0.4, kind: .elevator),
            ],
            edges: [["e", "c1"], ["c1", "c2"], ["c1", "r101"], ["c2", "s1"], ["c2", "l1"]],
            image: "test-1.png", width: 800, height: 1000
        )
        let floor2 = IndoorFloor(
            level: 2,
            nodes: [
                IndoorNode(id: "s2", x: 0.8, y: 0.4, kind: .stairs, accessible: accessibleStairs),
                IndoorNode(id: "l2", x: 0.9, y: 0.4, kind: .elevator),
                IndoorNode(id: "c3", x: 0.5, y: 0.4, kind: .corridor),
                IndoorNode(id: "r201", x: 0.2, y: 0.4, kind: .room, room: "201"),
            ],
            edges: [["s2", "c3"], ["l2", "c3"], ["c3", "r201"]],
            image: "test-2.png", width: 800, height: 1000
        )
        return IndoorGraph(
            buildingId: "test",
            floors: [floor1, floor2],
            links: [
                [.int(1), .string("s1"), .int(2), .string("s2")],
                [.int(1), .string("l1"), .int(2), .string("l2")],
            ]
        )
    }

    func testRoomLookupAcrossFloors() {
        let g = graph()
        XCTAssertEqual(g.floor(forRoom: "101")?.level, 1)
        XCTAssertEqual(g.floor(forRoom: "201")?.level, 2)
        XCTAssertNil(g.floor(forRoom: "999"))
        XCTAssertEqual(g.rooms, ["101", "201"])
    }

    func testDecodesTheFormatThePipelineWrites() throws {
        let json = """
        {"building_id":"b156","source":"traced","links":[[1,"s1",2,"s2"]],
         "floors":[{"level":1,"image":"k1.png","width":900,"height":1200,
           "nodes":[{"id":"e1","x":0.5,"y":0.9,"kind":"entrance","room":null,"name":null,"accessible":true},
                    {"id":"s1","x":0.8,"y":0.4,"kind":"stairs","accessible":false}],
           "edges":[["e1","s1"]]},
          {"level":2,"nodes":[{"id":"s2","x":0.8,"y":0.4,"kind":"stairs"},
                              {"id":"r1","x":0.2,"y":0.4,"kind":"room","room":"2443"}],
           "edges":[["s2","r1"]]}]}
        """
        let g = try IndoorGraph.decode(Data(json.utf8))
        XCTAssertEqual(g.buildingId, "b156")
        XCTAssertEqual(g.floors.count, 2)
        XCTAssertEqual(g.floor(level: 1)?.image, "k1.png")
        XCTAssertEqual(g.floor(level: 1)?.node("s1")?.accessible, false)
        XCTAssertEqual(g.connections.count, 1)
        XCTAssertEqual(g.connections.first?.from, NodeRef(level: 1, id: "s1"))
        XCTAssertEqual(g.floor(forRoom: "2443")?.level, 2)
    }

    func testAnUnknownNodeKindDegradesToCorridor() throws {
        let json = """
        {"building_id":"x","floors":[{"level":1,"nodes":[
          {"id":"a","x":0.1,"y":0.1,"kind":"teleporter"}],"edges":[]}],"links":[]}
        """
        let g = try IndoorGraph.decode(Data(json.utf8))
        XCTAssertEqual(g.floor(level: 1)?.node("a")?.kind, .corridor)
    }

    func testRoutesWithinAFloor() {
        let router = IndoorRouter(graph: graph())
        let path = router.pathToRoom("101")
        XCTAssertEqual(path?.nodes.map(\.id), ["e", "c1", "r101"])
        XCTAssertEqual(path?.levels, [1])
        XCTAssertFalse(path?.usesStairs ?? true)
    }

    func testRoutesAcrossFloorsPreferringStairs() {
        let router = IndoorRouter(graph: graph())
        guard let path = router.pathToRoom("201") else { return XCTFail("no path") }
        XCTAssertEqual(path.levels, [1, 2])
        XCTAssertTrue(path.usesStairs, "stairs are cheaper than the lift")
        XCTAssertFalse(path.usesElevator)
        XCTAssertEqual(path.nodes.map(\.id), ["e", "c1", "c2", "s1", "s2", "c3", "r201"])
    }

    func testAccessibleRoutingTakesTheLiftInsteadOfStairs() {
        let router = IndoorRouter(graph: graph())
        guard let path = router.pathToRoom("201", accessible: true) else { return XCTFail("no path") }
        XCTAssertTrue(path.usesElevator)
        XCTAssertFalse(path.usesStairs)
        XCTAssertEqual(path.levels, [1, 2])
    }

    func testAccessibleRoutingFailsWhenOnlyStairsConnect() {
        var g = graph()
        g.floors[0].nodes.removeAll { $0.id == "l1" }
        g.floors[0].edges.removeAll { $0.contains("l1") }
        g.floors[1].nodes.removeAll { $0.id == "l2" }
        g.floors[1].edges.removeAll { $0.contains("l2") }
        g.links = [[.int(1), .string("s1"), .int(2), .string("s2")]]

        let router = IndoorRouter(graph: g)
        XCTAssertNotNil(router.pathToRoom("201"))
        XCTAssertNil(router.pathToRoom("201", accessible: true))
    }

    func testStairsMarkedStepFreeAreAllowed() {
        let router = IndoorRouter(graph: graph(accessibleStairs: true))
        let path = router.pathToRoom("201", accessible: true)
        XCTAssertTrue(path?.usesElevator ?? false)
    }

    func testUnknownRoomAndUnreachableNode() {
        let router = IndoorRouter(graph: graph())
        XCTAssertNil(router.pathToRoom("999"))
        XCTAssertNil(router.path(from: NodeRef(level: 1, id: "e"), to: NodeRef(level: 9, id: "nope")))
    }

    func testSameNodeIsAZeroCostPath() {
        let router = IndoorRouter(graph: graph())
        let ref = NodeRef(level: 1, id: "e")
        let path = router.path(from: ref, to: ref)
        XCTAssertEqual(path?.cost, 0)
        XCTAssertEqual(path?.nodes, [ref])
    }

    func testDirectionsNameTheEntranceAndTheRoom() {
        let g = graph()
        let router = IndoorRouter(graph: g)
        guard let path = router.pathToRoom("101") else { return XCTFail("no path") }
        let steps = IndoorDirections.steps(for: path, in: g, room: "101")
        XCTAssertEqual(steps.first?.kind, .enter)
        XCTAssertEqual(steps.first?.text, "Enter at the main entrance")
        XCTAssertEqual(steps.last?.kind, .arrive)
        XCTAssertTrue(steps.last?.text.hasPrefix("Room 101") ?? false, steps.last?.text ?? "")
    }

    func testDirectionsCallTheTurnFromTheTracedGeometry() {
        let g = graph()
        let router = IndoorRouter(graph: g)
        guard let path = router.pathToRoom("101") else { return XCTFail("no path") }
        let steps = IndoorDirections.steps(for: path, in: g, room: "101")
        XCTAssertTrue(steps.last?.text.contains("on your left") ?? false, steps.last?.text ?? "")
    }

    func testDirectionsAnnounceTheFloorChange() {
        let g = graph()
        let router = IndoorRouter(graph: g)
        guard let path = router.pathToRoom("201") else { return XCTFail("no path") }
        let steps = IndoorDirections.steps(for: path, in: g, room: "201")
        guard let vertical = steps.first(where: { if case .stairs = $0.kind { return true } else { return false } }) else {
            return XCTFail("expected a stairs step, got \(steps.map(\.text))")
        }
        XCTAssertEqual(vertical.text, "Take the stairs up to the 2nd floor")
        XCTAssertEqual(steps.last?.level, 2)
    }

    func testDirectionsSayLiftWhenRoutingStepFree() {
        let g = graph()
        let router = IndoorRouter(graph: g)
        guard let path = router.pathToRoom("201", accessible: true) else { return XCTFail("no path") }
        let steps = IndoorDirections.steps(for: path, in: g, room: "201")
        XCTAssertTrue(steps.contains { $0.text.contains("Take the lift up to the 2nd floor") }, steps.map(\.text).description)
    }

    func testBearingAndTurnMathInImageSpace() {
        let up = IndoorNode(id: "a", x: 0.5, y: 0.9, kind: .corridor)
        let north = IndoorNode(id: "b", x: 0.5, y: 0.4, kind: .corridor)
        let east = IndoorNode(id: "c", x: 0.9, y: 0.9, kind: .corridor)
        XCTAssertEqual(IndoorDirections.bearing(from: up, to: north), 0, accuracy: 0.001)
        XCTAssertEqual(IndoorDirections.bearing(from: up, to: east), 90, accuracy: 0.001)
        XCTAssertEqual(IndoorDirections.turn(from: 350, to: 20), 30, accuracy: 0.001)
        XCTAssertEqual(IndoorDirections.turn(from: 20, to: 350), -30, accuracy: 0.001)
    }

    func testOrdinalNames() {
        XCTAssertEqual(IndoorDirections.ordinal(0), "basement")
        XCTAssertEqual(IndoorDirections.ordinal(1), "1st floor")
        XCTAssertEqual(IndoorDirections.ordinal(3), "3rd floor")
        XCTAssertEqual(IndoorDirections.ordinal(5), "5th floor")
    }
}
