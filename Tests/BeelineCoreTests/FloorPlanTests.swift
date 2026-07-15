import XCTest
@testable import BeelineCore

final class FloorPlanTests: XCTestCase {

    private static let pack: CampusPack = (try? CampusPack.bundled()) ?? .empty
    private var pack: CampusPack { Self.pack }

    private var clough: FloorPlan {
        guard let plan = pack.floorplans.first else {
            fatalError("the pack should ship at least one floor plan")
        }
        return plan
    }

    func testCloughPlanHasFiveFloors() {
        XCTAssertEqual(clough.floors.map(\.level).sorted(), [1, 2, 3, 4, 5])
        XCTAssertEqual(clough.floor(level: 1)?.name, "First Floor")
        XCTAssertEqual(clough.source, "Georgia Tech Library")
    }

    func testEveryFloorImageIsBundled() {
        for floor in clough.floors {
            XCTAssertNotNil(floor.imageURL, "missing image for \(floor.name)")
            XCTAssertGreaterThan(floor.width, 0)
            XCTAssertGreaterThan(floor.height, 0)
        }
    }

    func testRoomPositionsAreNormalized() {
        for floor in clough.floors {
            for room in floor.rooms where room.isPositioned {
                XCTAssertTrue((0...1).contains(room.x!), "\(room.room) x out of range")
                XCTAssertTrue((0...1).contains(room.y!), "\(room.room) y out of range")
            }
        }
    }

    func testPlanKnowsWhichFloorARoomIsOn() {
        // Straight from the published plan, not the room-number rule.
        XCTAssertEqual(clough.floor(forRoom: "152")?.level, 1)
        XCTAssertEqual(clough.floor(forRoom: "278")?.level, 2)
        XCTAssertEqual(clough.floor(forRoom: "589")?.level, 5)
        XCTAssertNil(clough.floor(forRoom: "9999"))
    }

    func testRoomLookupIsCaseInsensitive() {
        XCTAssertNotNil(clough.floor(level: 1)?.room("152"))
        XCTAssertNil(clough.floor(level: 1)?.room("589"), "589 is on floor 5, not 1")
    }

    func testUnpositionedRoomsStillNameTheirFloor() {
        // 125 loses its transform in the PDF but is definitely on floor 1.
        let room = clough.floor(level: 1)?.room("125")
        XCTAssertNotNil(room)
        XCTAssertFalse(room?.isPositioned ?? true)
    }

    // MARK: locate()

    func testLocatePrefersThePlanOverTheRoomNumberRule() {
        let located = pack.locate(room: "152", buildingID: clough.buildingId)
        XCTAssertTrue(located.isFromFloorPlan)
        XCTAssertEqual(located.floor, 1)
        XCTAssertEqual(located.floorLabel, "First Floor")
    }

    func testLocateFallsBackToTheRuleWhenNoPlanExists() {
        // Klaus has no published plan.
        let located = pack.locate(room: "1443", buildingID: "b156")
        XCTAssertFalse(located.isFromFloorPlan)
        XCTAssertEqual(located.floor, 1)
        XCTAssertEqual(located.hint, "Lecture hall off the atrium")
    }

    func testLocateFallsBackForARoomTheePlanDoesNotList() {
        // 250 is scheduled but not labeled on the plan; the rule still answers.
        let located = pack.locate(room: "250", buildingID: clough.buildingId)
        XCTAssertFalse(located.isFromFloorPlan)
        XCTAssertEqual(located.floor, 2)
    }

    func testMostScheduledCloughRoomsAreCoveredByThePlan() {
        let scheduled = pack.rooms.filter { $0.buildingId == clough.buildingId }
        XCTAssertFalse(scheduled.isEmpty)
        let covered = scheduled.filter { clough.floor(forRoom: $0.room) != nil }
        let ratio = Double(covered.count) / Double(scheduled.count)
        XCTAssertGreaterThan(ratio, 0.75, "plan should cover most scheduled rooms; got \(Int(ratio * 100))%")
    }
}
