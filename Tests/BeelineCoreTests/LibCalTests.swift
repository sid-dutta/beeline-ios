import XCTest
@testable import BeelineCore

final class LibCalTests: XCTestCase {

    private let formatter: DateFormatter = {
        let f = LibCal.makeFormatter(timeZone: TimeZone(identifier: "America/New_York")!)
        return f
    }()

    private func date(_ text: String) -> Date {
        guard let d = formatter.date(from: text) else { fatalError("bad fixture date \(text)") }
        return d
    }

    private func json(_ slots: [(Int, String, String)]) -> Data {
        let items = slots.map { ["itemId": $0.0, "start": $0.1, "end": $0.2] as [String: Any] }
        return try! JSONSerialization.data(withJSONObject: ["slots": items, "bookings": []])
    }

    // MARK: Parsing

    func testAdjacentSlotsMergeIntoOneInterval() throws {
        let data = json([
            (100, "2026-09-04 09:00:00", "2026-09-04 09:15:00"),
            (100, "2026-09-04 09:15:00", "2026-09-04 09:30:00"),
            (100, "2026-09-04 09:30:00", "2026-09-04 09:45:00"),
        ])
        let result = try LibCal.availability(fromJSON: data, formatter: formatter)
        XCTAssertEqual(result[100]?.free.count, 1)
        XCTAssertEqual(result[100]?.free.first?.start, date("2026-09-04 09:00:00"))
        XCTAssertEqual(result[100]?.free.first?.end, date("2026-09-04 09:45:00"))
    }

    func testGapsProduceSeparateIntervals() throws {
        let data = json([
            (100, "2026-09-04 09:00:00", "2026-09-04 09:15:00"),
            (100, "2026-09-04 11:00:00", "2026-09-04 11:15:00"),
        ])
        let result = try LibCal.availability(fromJSON: data, formatter: formatter)
        XCTAssertEqual(result[100]?.free.count, 2)
    }

    func testSlotsAreGroupedPerSpace() throws {
        let data = json([
            (100, "2026-09-04 09:00:00", "2026-09-04 09:15:00"),
            (200, "2026-09-04 09:00:00", "2026-09-04 09:15:00"),
        ])
        let result = try LibCal.availability(fromJSON: data, formatter: formatter)
        XCTAssertEqual(Set(result.keys), [100, 200])
        XCTAssertEqual(result[200]?.spaceID, 200)
    }

    func testEmptyAndMalformedPayloads() throws {
        XCTAssertTrue(try LibCal.availability(fromJSON: Data(#"{"slots":[],"bookings":[]}"#.utf8), formatter: formatter).isEmpty)
        XCTAssertTrue(try LibCal.availability(fromJSON: Data(#"{}"#.utf8), formatter: formatter).isEmpty)
        // A slot missing its end time is skipped, not fatal.
        let partial = Data(#"{"slots":[{"itemId":1,"start":"2026-09-04 09:00:00"}]}"#.utf8)
        XCTAssertTrue(try LibCal.availability(fromJSON: partial, formatter: formatter).isEmpty)
    }

    // MARK: Status

    func testStatusFreeNowReportsWhenItEnds() {
        let now = date("2026-09-04 10:00:00")
        let a = Availability(spaceID: 1, free: [DateInterval(start: date("2026-09-04 09:00:00"), end: date("2026-09-04 11:30:00"))])
        guard case .free(let minutes, let until) = a.status(now: now) else {
            return XCTFail("expected free, got \(a.status(now: now))")
        }
        XCTAssertEqual(minutes, 90)
        XCTAssertEqual(until, date("2026-09-04 11:30:00"))
    }

    func testStatusBusyReportsTheNextOpening() {
        let now = date("2026-09-04 10:00:00")
        let a = Availability(spaceID: 1, free: [DateInterval(start: date("2026-09-04 13:00:00"), end: date("2026-09-04 14:00:00"))])
        guard case .busy(let until) = a.status(now: now) else {
            return XCTFail("expected busy")
        }
        XCTAssertEqual(until, date("2026-09-04 13:00:00"))
        XCTAssertFalse(a.status(now: now).isFree)
    }

    func testStatusBusyAllDayWhenNothingRemains() {
        let now = date("2026-09-04 18:00:00")
        let a = Availability(spaceID: 1, free: [DateInterval(start: date("2026-09-04 09:00:00"), end: date("2026-09-04 10:00:00"))])
        XCTAssertEqual(a.status(now: now), .busyAllDay)
    }

    func testStatusUnknownWithNoData() {
        XCTAssertEqual(Availability(spaceID: 1, free: []).status(now: Date()), .unknown)
    }

    func testFreeUntilAndNextFree() {
        let now = date("2026-09-04 10:00:00")
        let a = Availability(spaceID: 1, free: [
            DateInterval(start: date("2026-09-04 09:00:00"), end: date("2026-09-04 10:30:00")),
            DateInterval(start: date("2026-09-04 12:00:00"), end: date("2026-09-04 13:00:00")),
        ])
        XCTAssertTrue(a.isFree(at: now))
        XCTAssertEqual(a.freeUntil(from: now), date("2026-09-04 10:30:00"))
        XCTAssertEqual(a.nextFree(after: now), date("2026-09-04 12:00:00"))
    }

    // MARK: Study places in the pack

    func testPackShipsBookableStudyRooms() throws {
        let pack = try CampusPack.bundled()
        let study = pack.places.filter { $0.kind == "study" }
        XCTAssertGreaterThan(study.count, 30)

        let bookable = study.filter(\.isBookable)
        XCTAssertGreaterThan(bookable.count, 30)
        for place in bookable {
            XCTAssertNotNil(place.locationId, place.name)
            XCTAssertNotNil(place.url, place.name)
        }

        // Clough study rooms resolve to a coordinate through their building.
        guard let clough = bookable.first(where: { $0.name.hasPrefix("Clough 2") }) else {
            return XCTFail("expected a Clough study room")
        }
        XCTAssertNotNil(pack.coordinate(of: clough))
        XCTAssertEqual(clough.displayName, "Clough 242")
        XCTAssertNotNil(clough.capacity)
    }

    func testSomeCloughStudyRoomsLandOnTheFloorPlan() throws {
        let pack = try CampusPack.bundled()
        guard let plan = pack.floorplans.first else { return XCTFail("no plan shipped") }
        let rooms = pack.places.filter {
            $0.kind == "study" && $0.buildingId == plan.buildingId && $0.room != nil
        }
        XCTAssertGreaterThan(rooms.count, 10)

        // The plan labels 242–252 as one range, so not every bookable room is
        // individually drawn. Those still resolve to a floor by number.
        let pinned = rooms.filter { plan.floor(forRoom: $0.room!) != nil }
        XCTAssertGreaterThanOrEqual(pinned.count, 5, "several study rooms should pin to the plan")
        for room in rooms where plan.floor(forRoom: room.room!) == nil {
            let located = pack.locate(room: room.room!, buildingID: plan.buildingId)
            XCTAssertNotNil(located.floor, "\(room.room!) should still resolve a floor")
            XCTAssertFalse(located.isFromFloorPlan)
        }
    }

    func testVendingMachinesAreNamedByBuilding() throws {
        let pack = try CampusPack.bundled()
        let vending = pack.places.filter { $0.kind == "vending" }
        XCTAssertGreaterThan(vending.count, 40, "the dedupe must not collapse distinct machines")
        XCTAssertTrue(vending.contains { $0.name.contains("—") }, "generic names should carry a building")
    }

    func testRestroomNamesDoNotOverclaimCoverage() throws {
        let pack = try CampusPack.bundled()
        let restrooms = pack.places.filter { $0.kind == "restroom" }
        XCTAssertGreaterThan(restrooms.count, 50)
        XCTAssertTrue(restrooms.allSatisfy { $0.name.lowercased().contains("gender-inclusive") })
    }

    func testBusStopsComeFromTheBusFeed() throws {
        let pack = try CampusPack.bundled()
        let stops = pack.places.filter { $0.kind == "stop" }
        XCTAssertGreaterThan(stops.count, 40, "stops should come from the routes, not the sparse map category")
    }
}
