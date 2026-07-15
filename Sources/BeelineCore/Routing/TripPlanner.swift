import Foundation

/// Walk, or walk-bus-walk?
///
/// The Stinger tracker can tell you where the buses are; it can't tell you
/// whether taking one actually gets you to class sooner. That needs the
/// walking graph and the bus timetable in the same place, which is the one
/// thing Beeline has.
///
/// A bus leg only wins when it beats walking by a real margin, and it is only
/// offered when we can name a bus the rider can actually catch.

public struct Trip: Identifiable, Sendable {
    public enum Leg: Sendable {
        case walk(meters: Double, seconds: TimeInterval, coordinates: [Coordinate], to: String)
        case wait(seconds: TimeInterval, routeName: String, stop: String)
        case ride(routeID: Int, routeName: String, board: String, alight: String, seconds: TimeInterval, stops: Int, coordinates: [Coordinate])
    }

    public var legs: [Leg]
    public var totalSeconds: TimeInterval
    /// Nil for a pure walk.
    public var routeName: String?

    public var id: String {
        (routeName ?? "walk") + "-" + String(Int(totalSeconds))
    }

    public var isWalkOnly: Bool { routeName == nil }

    public var minutes: Int { max(1, Int((totalSeconds / 60).rounded())) }

    public var walkingMeters: Double {
        legs.reduce(0) { total, leg in
            if case .walk(let m, _, _, _) = leg { return total + m }
            return total
        }
    }

    /// Every coordinate the trip covers, for drawing it on the map.
    public var coordinates: [Coordinate] {
        legs.flatMap { leg -> [Coordinate] in
            switch leg {
            case .walk(_, _, let c, _): c
            case .ride(_, _, _, _, _, _, let c): c
            case .wait: []
            }
        }
    }
}

public struct TripPlanner: Sendable {
    /// Only consider boarding at a stop this close to the start.
    public static let boardRadius = 550.0
    /// Only consider getting off this close to the destination.
    public static let alightRadius = 550.0
    /// A bus trip has to save at least this much to be worth suggesting.
    public static let minimumSavingSeconds = 180.0
    /// Walking pace used for every walk leg, metres per second.
    public static let walkingSpeed = 1.35

    private let router: Router
    private let routes: [BusRoute]

    public init(router: Router, routes: [BusRoute]) {
        self.router = router
        self.routes = routes
    }

    // MARK: Planning

    /// Best options from a point to a set of destination graph nodes,
    /// walking-only first, then the best bus trip if one genuinely helps.
    public func plan(
        fromLat lat: Double,
        lng: Double,
        toNodes goals: [Int],
        destinationName: String,
        arrivals: [StopArrival] = [],
        now: Date = Date(),
        accessible: Bool = false
    ) -> [Trip] {
        guard let startNode = router.nearestNode(lat: lat, lng: lng, maxMeters: 300),
              let walk = router.route(fromAny: [startNode], toAny: goals, accessible: accessible) else {
            return []
        }

        let walkTrip = Trip(
            legs: [.walk(meters: walk.route.meters, seconds: seconds(walk.route.meters), coordinates: walk.route.coordinates, to: destinationName)],
            totalSeconds: seconds(walk.route.meters),
            routeName: nil
        )

        guard let best = bestBusTrip(
            from: startNode,
            fromLat: lat, fromLng: lng,
            toNodes: goals,
            destinationName: destinationName,
            arrivals: arrivals,
            now: now,
            accessible: accessible
        ), best.totalSeconds + Self.minimumSavingSeconds < walkTrip.totalSeconds else {
            return [walkTrip]
        }
        return [best, walkTrip]
    }

    // MARK: Bus search

    private func bestBusTrip(
        from startNode: Int,
        fromLat: Double, fromLng: Double,
        toNodes goals: [Int],
        destinationName: String,
        arrivals: [StopArrival],
        now: Date,
        accessible: Bool
    ) -> Trip? {
        var best: Trip?

        for route in routes {
            let boardable = route.stops.filter {
                Geo.distanceMeters(fromLat, fromLng, $0.lat, $0.lng) <= Self.boardRadius
            }
            guard !boardable.isEmpty else { continue }

            // Candidate alighting stops: near any destination node.
            let alightable = route.stops.filter { stop in
                guard let node = router.nearestNode(lat: stop.lat, lng: stop.lng, maxMeters: 120) else { return false }
                return router.route(fromAny: [node], toAny: goals, accessible: accessible)
                    .map { $0.route.meters <= Self.alightRadius } ?? false
            }
            guard !alightable.isEmpty else { continue }

            for board in boardable {
                guard let boardNode = router.nearestNode(lat: board.lat, lng: board.lng, maxMeters: 120),
                      let toStop = router.route(fromAny: [startNode], toAny: [boardNode], accessible: accessible) else { continue }
                let walkToStop = seconds(toStop.route.meters)

                // The first bus on this route we can actually reach.
                guard let wait = waitSeconds(routeID: route.id, stopID: board.id, afterWalking: walkToStop, arrivals: arrivals) else { continue }

                for alight in alightable where alight.id != board.id {
                    guard let ride = rideSeconds(route: route, from: board, to: alight) else { continue }
                    guard let alightNode = router.nearestNode(lat: alight.lat, lng: alight.lng, maxMeters: 120),
                          let fromStop = router.route(fromAny: [alightNode], toAny: goals, accessible: accessible) else { continue }
                    let walkFromStop = seconds(fromStop.route.meters)

                    let total = walkToStop + wait + ride + walkFromStop
                    if let current = best, current.totalSeconds <= total { continue }

                    best = Trip(
                        legs: [
                            .walk(meters: toStop.route.meters, seconds: walkToStop, coordinates: toStop.route.coordinates, to: board.name),
                            .wait(seconds: wait, routeName: route.name, stop: board.name),
                            .ride(
                                routeID: route.id,
                                routeName: route.name,
                                board: board.name,
                                alight: alight.name,
                                seconds: ride,
                                stops: stopCount(route: route, from: board, to: alight),
                                coordinates: ridePath(route: route, from: board, to: alight)
                            ),
                            .walk(meters: fromStop.route.meters, seconds: walkFromStop, coordinates: fromStop.route.coordinates, to: destinationName),
                        ],
                        totalSeconds: total,
                        routeName: route.name
                    )
                }
            }
        }
        return best
    }

    // MARK: Pieces

    func seconds(_ meters: Double) -> TimeInterval { meters / Self.walkingSpeed }

    /// The wait for the first bus we can still catch, or nil when no live
    /// arrival is reachable — we don't guess at a headway.
    func waitSeconds(routeID: Int, stopID: Int, afterWalking walk: TimeInterval, arrivals: [StopArrival]) -> TimeInterval? {
        let candidates = arrivals
            .filter { $0.routeID == routeID && $0.routeStopID == stopID }
            .map { TimeInterval($0.secondsToStop) }
            .sorted()
        // A bus arriving before we can get there is one we miss.
        guard let catchable = candidates.first(where: { $0 >= walk }) else { return nil }
        return catchable - walk
    }

    /// Stinger routes are loops, so riding "past the end" wraps around.
    func rideSeconds(route: BusRoute, from board: BusStop, to alight: BusStop) -> TimeInterval? {
        let ordered = route.stops.sorted { $0.order < $1.order }
        guard let start = ordered.firstIndex(where: { $0.id == board.id }),
              let end = ordered.firstIndex(where: { $0.id == alight.id }), start != end else { return nil }

        var total: TimeInterval = 0
        var i = start
        var hops = 0
        while i != end {
            guard let seconds = ordered[i].secondsToNext, seconds > 0 else { return nil }
            total += TimeInterval(seconds)
            i = (i + 1) % ordered.count
            hops += 1
            if hops > ordered.count { return nil }
        }
        return total
    }

    func stopCount(route: BusRoute, from board: BusStop, to alight: BusStop) -> Int {
        let ordered = route.stops.sorted { $0.order < $1.order }
        guard let start = ordered.firstIndex(where: { $0.id == board.id }),
              let end = ordered.firstIndex(where: { $0.id == alight.id }) else { return 0 }
        return start <= end ? end - start : ordered.count - start + end
    }

    /// The stop-to-stop path, used to draw the ride on the map.
    func ridePath(route: BusRoute, from board: BusStop, to alight: BusStop) -> [Coordinate] {
        let ordered = route.stops.sorted { $0.order < $1.order }
        guard let start = ordered.firstIndex(where: { $0.id == board.id }),
              let end = ordered.firstIndex(where: { $0.id == alight.id }) else { return [] }
        var path: [Coordinate] = []
        var i = start
        var hops = 0
        while true {
            path.append(Coordinate(lat: ordered[i].lat, lng: ordered[i].lng))
            if i == end || hops > ordered.count { break }
            i = (i + 1) % ordered.count
            hops += 1
        }
        return path
    }
}
