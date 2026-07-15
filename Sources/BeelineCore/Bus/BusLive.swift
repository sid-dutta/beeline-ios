import Foundation

public struct Vehicle: Identifiable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var routeID: Int
    public var lat: Double
    public var lng: Double
    public var heading: Double
    public var speedMPH: Double
    public var onRoute: Bool
    public var isDelayed: Bool
    public var reportedAt: Date?

    public func isStale(now: Date = Date(), tolerance: TimeInterval = 180) -> Bool {
        guard let reportedAt else { return false }
        return now.timeIntervalSince(reportedAt) > tolerance
    }
}

public struct StopArrival: Identifiable, Hashable, Sendable {
    public var routeID: Int
    public var routeStopID: Int
    public var vehicleID: Int
    public var secondsToStop: Int
    public var onRoute: Bool

    public var id: String { "\(routeID)-\(routeStopID)-\(vehicleID)" }

    public var minutes: Int { max(0, Int((Double(secondsToStop) / 60).rounded())) }

    public var label: String {
        switch secondsToStop {
        case ..<45: "Arriving"
        case ..<90: "1 min"
        default: "\(minutes) min"
        }
    }
}

enum RideSystems {

    static func date(from raw: String?) -> Date? {
        guard let raw, let open = raw.firstIndex(of: "("), let close = raw.firstIndex(of: ")") else { return nil }
        let inner = raw[raw.index(after: open)..<close]
        let millisPart = inner.prefix { $0.isNumber || $0 == "-" && inner.first == $0 }
        guard let millis = Double(millisPart) else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: d
        case let i as Int: Double(i)
        case let s as String: Double(s)
        case let n as NSNumber: n.doubleValue
        default: nil
        }
    }

    static func bool(_ value: Any?) -> Bool {
        switch value {
        case let b as Bool: b
        case let s as String: s.lowercased() == "true"
        case let n as NSNumber: n.boolValue
        default: false
        }
    }

    static func vehicles(from json: Any) -> [Vehicle] {
        guard let array = json as? [[String: Any]] else { return [] }
        return array.compactMap { item in
            guard let id = number(item["VehicleID"]).map(Int.init),
                  let route = number(item["RouteID"]).map(Int.init),
                  let lat = number(item["Latitude"]), let lng = number(item["Longitude"]),
                  lat != 0 || lng != 0 else { return nil }
            return Vehicle(
                id: id,
                name: (item["Name"] as? String) ?? "Bus \(id)",
                routeID: route,
                lat: lat,
                lng: lng,
                heading: number(item["Heading"]) ?? 0,
                speedMPH: number(item["GroundSpeed"]) ?? 0,
                onRoute: bool(item["IsOnRoute"]),
                isDelayed: bool(item["IsDelayed"]),
                reportedAt: date(from: item["TimeStamp"] as? String)
            )
        }
    }

    static func arrivals(from json: Any) -> [StopArrival] {
        guard let array = json as? [[String: Any]] else { return [] }
        var out: [StopArrival] = []
        for stop in array {
            guard let routeID = number(stop["RouteID"]).map(Int.init),
                  let stopID = number(stop["RouteStopID"]).map(Int.init) else { continue }
            for estimate in (stop["VehicleEstimates"] as? [[String: Any]]) ?? [] {
                guard let seconds = number(estimate["SecondsToStop"]).map(Int.init),
                      let vehicle = number(estimate["VehicleID"]).map(Int.init) else { continue }
                out.append(
                    StopArrival(
                        routeID: routeID,
                        routeStopID: stopID,
                        vehicleID: vehicle,
                        secondsToStop: seconds,
                        onRoute: bool(estimate["OnRoute"])
                    )
                )
            }
        }
        return out.sorted { $0.secondsToStop < $1.secondsToStop }
    }
}

public protocol BusService: Sendable {
    func vehicles() async throws -> [Vehicle]
    func arrivals() async throws -> [StopArrival]
}

public actor RideSystemsClient: BusService {
    public static let defaultBaseURL = URL(string: "https://bus.gatech.edu/Services/JSONPRelay.svc/")!

    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = RideSystemsClient.defaultBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func vehicles() async throws -> [Vehicle] {
        RideSystems.vehicles(from: try await get("GetMapVehiclePoints"))
    }

    public func arrivals() async throws -> [StopArrival] {
        RideSystems.arrivals(from: try await get("GetRouteStopArrivals?TimesPerStopString=2"))
    }

    private func get(_ path: String) async throws -> Any {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw BusError.badURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BusError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    public enum BusError: Error, LocalizedError {
        case badURL
        case badResponse(Int)

        public var errorDescription: String? {
            switch self {
            case .badURL: "Couldn't build the bus request."
            case .badResponse(let code): "The bus tracker returned an error (\(code))."
            }
        }
    }
}

public struct PreviewBusService: BusService {
    public init() {}

    public func vehicles() async throws -> [Vehicle] {
        [
            Vehicle(id: 1, name: "Bus 12", routeID: 20, lat: 33.7762, lng: -84.3985, heading: 95, speedMPH: 14, onRoute: true, isDelayed: false, reportedAt: Date()),
            Vehicle(id: 2, name: "Bus 07", routeID: 21, lat: 33.7745, lng: -84.3966, heading: 210, speedMPH: 8, onRoute: true, isDelayed: false, reportedAt: Date()),
        ]
    }

    public func arrivals() async throws -> [StopArrival] {
        [
            StopArrival(routeID: 20, routeStopID: 250, vehicleID: 1, secondsToStop: 95, onRoute: true),
            StopArrival(routeID: 20, routeStopID: 251, vehicleID: 1, secondsToStop: 420, onRoute: true),
        ]
    }
}
