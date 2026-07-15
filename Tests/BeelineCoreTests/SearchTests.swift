import XCTest
@testable import BeelineCore

final class SearchTests: XCTestCase {

    private static let index = SearchIndex(pack: try! CampusPack.bundled())
    private var index: SearchIndex { Self.index }

    private func firstTitle(_ query: String) -> String {
        index.search(query).first?.title ?? "<none>"
    }

    func testBuildingSearchByShortNameAndAlias() {
        XCTAssertTrue(firstTitle("klaus").contains("Klaus"))
        XCTAssertTrue(firstTitle("clough").contains("Clough"))
        XCTAssertTrue(firstTitle("crc").lowercased().contains("recreation") || firstTitle("crc").contains("CRC"))
    }

    func testRoomSearchResolvesBuildingAndRoom() {
        guard case .room(let room, let building)? = index.search("klaus 1443").first else {
            return XCTFail("klaus 1443 should be a room, got \(firstTitle("klaus 1443"))")
        }
        XCTAssertEqual(room.room, "1443")
        XCTAssertTrue(building.name.contains("Klaus"))
        XCTAssertFalse(room.meetings.isEmpty)
    }

    func testRoomSearchWithLetterPrefix() {
        guard case .room(let room, let building)? = index.search("van leer e465").first else {
            return XCTFail("van leer e465 should be a room, got \(firstTitle("van leer e465"))")
        }
        XCTAssertEqual(room.room, "E465")
        XCTAssertTrue(building.name.contains("Van Leer"))
    }

    func testCourseSearchBeatsRoomInterpretation() {
        guard case .course(let id, _, let rooms)? = index.search("cs 1332").first else {
            return XCTFail("cs 1332 should be a course, got \(firstTitle("cs 1332"))")
        }
        XCTAssertEqual(id, "CS 1332")
        XCTAssertFalse(rooms.isEmpty)
        // Without the space too.
        guard case .course(let id2, _, _)? = index.search("cs1332").first else {
            return XCTFail("cs1332 should be a course")
        }
        XCTAssertEqual(id2, "CS 1332")
    }

    func testPlaceSearchByKind() {
        let results = index.search("dining")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains { if case .place = $0 { return true } else { return false } })
    }

    func testEmptyAndNonsenseQueries() {
        XCTAssertTrue(index.search("").isEmpty)
        XCTAssertTrue(index.search("   ").isEmpty)
        XCTAssertTrue(index.search("zzzzqqq").isEmpty)
    }

    func testResultsAreDeduplicatedAndLimited() {
        let results = index.search("b", limit: 5)
        XCTAssertLessThanOrEqual(results.count, 5)
        XCTAssertEqual(Set(results.map(\.id)).count, results.count)
    }
}

final class RoomDecoderTests: XCTestCase {

    func testDefaultFloorFromLeadingDigit() {
        XCTAssertEqual(RoomDecoder.decode(room: "1443", buildingID: "bX").floor, 1)
        XCTAssertEqual(RoomDecoder.decode(room: "2446", buildingID: "bX").floor, 2)
        XCTAssertEqual(RoomDecoder.decode(room: "423", buildingID: "bX").floor, 4)
        XCTAssertEqual(RoomDecoder.decode(room: "202", buildingID: "bX").floorLabel, "2nd floor")
    }

    func testWingPrefixes() {
        let e465 = RoomDecoder.decode(room: "E465", buildingID: "bX")
        XCTAssertEqual(e465.floor, 4)
        XCTAssertEqual(e465.wing, "East wing")
        XCTAssertEqual(e465.summary, "4th floor · East wing")
        XCTAssertEqual(RoomDecoder.decode(room: "W200", buildingID: "bX").wing, "West wing")
    }

    func testBasementAndGroundPrefixes() {
        XCTAssertEqual(RoomDecoder.decode(room: "B12", buildingID: "bX").floorLabel, "Basement")
        XCTAssertEqual(RoomDecoder.decode(room: "G20", buildingID: "bX").floorLabel, "Ground floor")
    }

    func testLevelPrefixDistinguishesRoomFromLectureHall() {
        XCTAssertEqual(RoomDecoder.decode(room: "L1105", buildingID: "bX").floor, 1)
        let hall = RoomDecoder.decode(room: "L3", buildingID: "b81")
        XCTAssertEqual(hall.floorLabel, "Ground floor")
        XCTAssertEqual(hall.hint, "Lecture hall L3")
    }

    func testKlausLectureHallHint() {
        XCTAssertEqual(RoomDecoder.decode(room: "1443", buildingID: "b156").hint, "Lecture hall off the atrium")
        XCTAssertNil(RoomDecoder.decode(room: "2108", buildingID: "b156").hint)
    }

    func testCollegeOfComputingShortNumbersAreGroundFloor() {
        let r = RoomDecoder.decode(room: "16", buildingID: "b50")
        XCTAssertEqual(r.floorLabel, "Ground floor")
        XCTAssertNotNil(r.hint)
    }

    func testUnparseableRoom() {
        XCTAssertNil(RoomDecoder.decode(room: "TBA", buildingID: "bX").floor)
    }
}
