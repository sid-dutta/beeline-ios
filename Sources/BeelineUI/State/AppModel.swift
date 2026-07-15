import Foundation
import MapKit
import Observation
import BeelineCore

/// Everything the UI reads. The pack, router and search index are built once
/// at launch; routes and bus data are recomputed on demand.
@MainActor
@Observable
public final class AppModel {

    public enum Destination: Hashable, Sendable {
        case building(String)
        case room(buildingID: String, room: String)
        case place(String)

        var buildingID: String? {
            switch self {
            case .building(let id): id
            case .room(let id, _): id
            case .place: nil
            }
        }
    }

    public struct ActiveRoute: Sendable {
        public var destination: Destination
        public var title: String
        public var subtitle: String?
        public var route: Router.Route
        public var steps: [Step]
        public var entrance: Entrance?
        public var startedFromLocation: Bool
    }

    // MARK: Data

    public let pack: CampusPack
    public let router: Router
    public let index: SearchIndex

    public private(set) var loadError: String?

    // MARK: Search

    public var query: String = "" {
        didSet { results = query.isEmpty ? [] : index.search(query) }
    }
    public private(set) var results: [SearchResult] = []

    // MARK: Routing

    public private(set) var activeRoute: ActiveRoute?
    public var accessibleRouting: Bool {
        didSet {
            defaults.set(accessibleRouting, forKey: Keys.accessible)
            if let d = activeRoute?.destination { route(to: d) }
        }
    }
    public private(set) var routingError: String?

    // MARK: Classes

    public private(set) var enrolled: [EnrolledSection] {
        didSet {
            schedule = Schedule(sections: enrolled, pack: pack)
            if let data = try? JSONEncoder().encode(enrolled) {
                defaults.set(data, forKey: Keys.enrolled)
            }
        }
    }
    public private(set) var schedule: Schedule

    // MARK: Bus

    public private(set) var vehicles: [Vehicle] = []
    public private(set) var arrivals: [StopArrival] = []
    public private(set) var busUpdatedAt: Date?
    public private(set) var busError: String?
    public private(set) var isRefreshingBus = false

    // MARK: Study spaces

    public private(set) var studyAvailability: [Int: Availability] = [:]
    public private(set) var studyUpdatedAt: Date?
    public private(set) var studyError: String?
    public private(set) var isRefreshingStudy = false

    private let bus: BusService
    private let study: StudyAvailabilityService
    private let defaults: UserDefaults
    private var busTimer: Task<Void, Never>?

    private enum Keys {
        static let enrolled = "beeline.enrolled"
        static let accessible = "beeline.accessibleRouting"
    }

    // MARK: Init

    public init(
        pack: CampusPack,
        bus: BusService,
        study: StudyAvailabilityService = LibCalClient(),
        defaults: UserDefaults = .standard
    ) {
        self.pack = pack
        self.router = Router(graph: pack.graph)
        self.index = SearchIndex(pack: pack)
        self.bus = bus
        self.study = study
        self.defaults = defaults
        self.accessibleRouting = defaults.bool(forKey: Keys.accessible)
        let saved = (defaults.data(forKey: Keys.enrolled))
            .flatMap { try? JSONDecoder().decode([EnrolledSection].self, from: $0) } ?? []
        self.enrolled = saved
        self.schedule = Schedule(sections: saved, pack: pack)
    }

    /// Production: the pack from the bundle, live buses.
    public static func live() -> AppModel {
        do {
            return AppModel(pack: try CampusPack.bundled(), bus: RideSystemsClient(), study: LibCalClient())
        } catch {
            // A pack that won't load is a build error, not a runtime state the
            // user can fix — but crashing on launch is worse than an empty map.
            let model = AppModel(pack: .empty, bus: PreviewBusService(), study: PreviewStudyService())
            model.loadError = error.localizedDescription
            return model
        }
    }

    public static func preview() -> AppModel {
        AppModel(
            pack: (try? CampusPack.bundled()) ?? .empty,
            bus: PreviewBusService(),
            study: PreviewStudyService(),
            defaults: UserDefaults(suiteName: "beeline.preview") ?? .standard
        )
    }

    // MARK: Lookup

    public func building(_ id: String) -> Building? { index.building(id: id) }

    public func rooms(in buildingID: String) -> [Room] { index.rooms(in: buildingID) }

    public func place(_ id: String) -> Place? { pack.places.first { $0.id == id } }

    public func floorPlan(for buildingID: String) -> FloorPlan? { pack.floorPlan(for: buildingID) }

    /// Where a room is, preferring a published floor plan over the
    /// room-number rule.
    public func locate(room: String, in buildingID: String) -> RoomLocation {
        pack.locate(room: room, buildingID: buildingID)
    }

    public func coordinate(of destination: Destination) -> CLLocationCoordinate2D? {
        switch destination {
        case .building(let id), .room(let id, _):
            building(id).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        case .place(let id):
            place(id).flatMap(pack.coordinate(of:)).map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
            }
        }
    }

    public func title(for destination: Destination) -> String {
        switch destination {
        case .building(let id): building(id)?.name ?? "Building"
        case .room(let id, let room): "\(building(id)?.shortName ?? "") \(room)".trimmingCharacters(in: .whitespaces)
        case .place(let id): place(id)?.name ?? "Place"
        }
    }

    // MARK: Routing

    /// Current location if we have one, otherwise the middle of campus so the
    /// app is still useful indoors or in the simulator.
    public var origin: CLLocationCoordinate2D?

    public func route(to destination: Destination) {
        routingError = nil

        let goalNodes: [Int]
        var entranceCandidates: [Entrance] = []
        switch destination {
        case .building(let id), .room(let id, _):
            guard let b = building(id) else {
                routingError = "That building isn't in the map data."
                return
            }
            entranceCandidates = b.routableEntrances
            if accessibleRouting, entranceCandidates.contains(where: \.accessible) {
                entranceCandidates = entranceCandidates.filter(\.accessible)
            }
            goalNodes = entranceCandidates.compactMap(\.node)
        case .place(let id):
            // A bookable study room has no point of its own — route to the
            // building that holds it, and pick its door like any other.
            guard let p = place(id) else {
                routingError = "That place isn't in the map data."
                return
            }
            if let buildingID = p.buildingId, let b = building(buildingID) {
                entranceCandidates = b.routableEntrances
                if accessibleRouting, entranceCandidates.contains(where: \.accessible) {
                    entranceCandidates = entranceCandidates.filter(\.accessible)
                }
                goalNodes = entranceCandidates.compactMap(\.node)
            } else if let c = pack.coordinate(of: p),
                      let node = router.nearestNode(lat: c.lat, lng: c.lng) {
                goalNodes = [node]
            } else {
                routingError = "No walking path reaches that spot."
                return
            }
        }

        guard !goalNodes.isEmpty else {
            routingError = accessibleRouting
                ? "No step-free entrance is mapped for this building yet."
                : "No mapped entrance for this building yet."
            return
        }

        let fromLocation = origin != nil
        let start = origin.flatMap { router.nearestNode(lat: $0.latitude, lng: $0.longitude, maxMeters: 250) }
            ?? router.nearestNode(lat: 33.7743, lng: -84.3963, maxMeters: 400)

        guard let startNode = start else {
            routingError = "You're too far from campus to route from here."
            return
        }

        guard let result = router.route(fromAny: [startNode], toAny: goalNodes, accessible: accessibleRouting) else {
            routingError = "Couldn't find a walking route there."
            return
        }

        let entrance = entranceCandidates.first { $0.node == result.goal }
        let name = title(for: destination)
        var subtitle: String?
        if case .room(let id, let room) = destination {
            let decoded = pack.locate(room: room, buildingID: id)
            subtitle = [decoded.summary, decoded.hint].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        }

        activeRoute = ActiveRoute(
            destination: destination,
            title: name,
            subtitle: subtitle,
            route: result.route,
            steps: Directions.steps(for: result.route.coordinates, destinationName: name, entranceName: entrance?.doorDescription),
            entrance: entrance,
            startedFromLocation: fromLocation
        )
    }

    public func clearRoute() {
        activeRoute = nil
        routingError = nil
    }

    // MARK: Classes

    public func enroll(course: String, section: String) {
        let s = EnrolledSection(course: course, section: section)
        guard !enrolled.contains(s) else { return }
        enrolled.append(s)
    }

    public func unenroll(_ section: EnrolledSection) {
        enrolled.removeAll { $0 == section }
    }

    public var isEnrolledEmpty: Bool { enrolled.isEmpty }

    /// Sections available for a course, for the "add class" picker.
    public func sections(forCourse course: String) -> [(section: String, meeting: Meeting, buildingID: String, room: String)] {
        var out: [(String, Meeting, String, String)] = []
        for room in pack.rooms {
            for m in room.meetings where m.course == course {
                if !out.contains(where: { $0.0 == m.section }) {
                    out.append((m.section, m, room.buildingId, room.room))
                }
            }
        }
        return out.sorted { $0.0 < $1.0 }.map { (section: $0.0, meeting: $0.1, buildingID: $0.2, room: $0.3) }
    }

    /// Next class plus how long the walk there takes right now.
    public func nextClass() -> (event: ClassEvent, minutesUntil: Int, walkMinutes: Double?)? {
        guard let next = schedule.next() else { return nil }
        let walk = walkMinutes(toBuilding: next.event.buildingID)
        return (next.event, next.minutesUntil, walk)
    }

    public func walkMinutes(toBuilding id: String) -> Double? {
        guard let b = building(id) else { return nil }
        let goals = b.routableEntrances.compactMap(\.node)
        guard !goals.isEmpty else { return nil }
        let from = origin ?? CLLocationCoordinate2D(latitude: 33.7743, longitude: -84.3963)
        guard let start = router.nearestNode(lat: from.latitude, lng: from.longitude, maxMeters: 400),
              let result = router.route(fromAny: [start], toAny: goals, accessible: accessibleRouting) else { return nil }
        return result.route.minutes
    }

    // MARK: Bus

    public func startBusUpdates() {
        guard busTimer == nil else { return }
        busTimer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshBus()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    public func stopBusUpdates() {
        busTimer?.cancel()
        busTimer = nil
    }

    public func refreshBus() async {
        guard !isRefreshingBus else { return }
        isRefreshingBus = true
        defer { isRefreshingBus = false }
        do {
            async let v = bus.vehicles()
            async let a = bus.arrivals()
            let (vehicles, arrivals) = try await (v, a)
            self.vehicles = vehicles.filter { !$0.isStale() }
            self.arrivals = arrivals
            busUpdatedAt = Date()
            busError = nil
        } catch {
            busError = error.localizedDescription
        }
    }

    public func route(_ id: Int) -> BusRoute? { pack.bus.routes.first { $0.id == id } }

    // MARK: Study spaces

    /// Bookable rooms, free ones first, then by building and name.
    public var studySpaces: [Place] {
        pack.places
            .filter { $0.kind == "study" && $0.isBookable }
            .sorted { a, b in
                let fa = status(for: a)?.isFree ?? false
                let fb = status(for: b)?.isFree ?? false
                if fa != fb { return fa }
                let na = buildingName(for: a), nb = buildingName(for: b)
                return na == nb ? a.displayName < b.displayName : na < nb
            }
    }

    public func buildingName(for place: Place) -> String {
        place.buildingId.flatMap(building)?.shortName ?? "Elsewhere"
    }

    public func status(for place: Place) -> Availability.Status? {
        place.bookingId.flatMap { studyAvailability[$0] }?.status()
    }

    public var freeStudyCount: Int {
        studySpaces.filter { status(for: $0)?.isFree == true }.count
    }

    public func refreshStudyAvailability() async {
        guard !isRefreshingStudy else { return }
        let locationIDs = Set(pack.places.compactMap(\.locationId))
        guard !locationIDs.isEmpty else { return }
        isRefreshingStudy = true
        defer { isRefreshingStudy = false }
        do {
            studyAvailability = try await study.availability(locationIDs: Array(locationIDs).sorted(), on: Date())
            studyUpdatedAt = Date()
            studyError = nil
        } catch {
            studyError = error.localizedDescription
        }
    }

    public func vehicles(onRoute id: Int) -> [Vehicle] { vehicles.filter { $0.routeID == id } }

    public func nextArrival(routeID: Int, stopID: Int) -> StopArrival? {
        arrivals.first { $0.routeID == routeID && $0.routeStopID == stopID }
    }

    /// Are any buses running at all right now?
    public var isServiceActive: Bool { !vehicles.isEmpty }
}

extension Entrance {
    /// "the main entrance", "the west door", "the accessible entrance"
    var doorDescription: String {
        if let name, !name.isEmpty, name != "Nearest path" { return name }
        if main { return "the main entrance" }
        if accessible { return "the accessible entrance" }
        return "the entrance"
    }
}
