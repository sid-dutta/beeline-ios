import Foundation

/// Live availability for the library's bookable study rooms.
///
/// LibCal's booking grid is a public POST that returns the *free* 15-minute
/// slots for a date range. Turning that into "free now, until 3:45" is the
/// whole point — a static pin telling you a study room exists is far less
/// useful than knowing you can walk into it.

public struct Availability: Hashable, Sendable {
    /// LibCal space id.
    public var spaceID: Int
    /// Free intervals, merged and sorted.
    public var free: [DateInterval]

    public init(spaceID: Int, free: [DateInterval]) {
        self.spaceID = spaceID
        self.free = free
    }

    public func isFree(at moment: Date) -> Bool {
        free.contains { $0.contains(moment) }
    }

    /// When the current free stretch ends, if it's free right now.
    public func freeUntil(from moment: Date) -> Date? {
        free.first { $0.contains(moment) }?.end
    }

    /// The next moment this room opens up, if it isn't free now.
    public func nextFree(after moment: Date) -> Date? {
        free.first { $0.start > moment }?.start
    }

    /// How the UI describes this room right now.
    public func status(now: Date = Date()) -> Status {
        if free.isEmpty { return .unknown }
        if isFree(at: now) {
            guard let until = freeUntil(from: now) else { return .freeIndefinitely }
            let minutes = Int(until.timeIntervalSince(now) / 60)
            return minutes >= 24 * 60 ? .freeIndefinitely : .free(untilMinutes: minutes, until: until)
        }
        if let next = nextFree(after: now) { return .busy(until: next) }
        return .busyAllDay
    }

    public enum Status: Hashable, Sendable {
        case free(untilMinutes: Int, until: Date)
        case freeIndefinitely
        case busy(until: Date)
        case busyAllDay
        case unknown

        public var isFree: Bool {
            switch self {
            case .free, .freeIndefinitely: true
            default: false
            }
        }
    }
}

// MARK: - Parsing

public enum LibCal {
    /// Slot timestamps arrive as `"2026-09-04 09:00:00"` in the library's
    /// own time zone.
    public static func makeFormatter(timeZone: TimeZone = TimeZone(identifier: "America/New_York") ?? .current) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    /// Group the flat slot list into merged free intervals per space.
    public static func availability(fromJSON data: Data, formatter: DateFormatter = makeFormatter()) throws -> [Int: Availability] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let slots = root["slots"] as? [[String: Any]] else {
            return [:]
        }

        var bySpace: [Int: [DateInterval]] = [:]
        for slot in slots {
            guard let itemID = (slot["itemId"] as? Int) ?? Int("\(slot["itemId"] ?? "")"),
                  let startText = slot["start"] as? String,
                  let endText = slot["end"] as? String,
                  let start = formatter.date(from: startText),
                  let end = formatter.date(from: endText),
                  end > start else { continue }
            bySpace[itemID, default: []].append(DateInterval(start: start, end: end))
        }

        return bySpace.mapValues { intervals in
            Availability(spaceID: 0, free: merge(intervals))
        }
        .reduce(into: [Int: Availability]()) { result, pair in
            result[pair.key] = Availability(spaceID: pair.key, free: pair.value.free)
        }
    }

    /// Adjacent or overlapping 15-minute slots become one interval.
    public static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in sorted {
            if let last = merged.last, interval.start <= last.end {
                if interval.end > last.end {
                    merged[merged.count - 1] = DateInterval(start: last.start, end: interval.end)
                }
            } else {
                merged.append(interval)
            }
        }
        return merged
    }
}

// MARK: - Client

public protocol StudyAvailabilityService: Sendable {
    /// Availability keyed by LibCal space id, for the day containing `date`.
    func availability(locationIDs: [Int], on date: Date) async throws -> [Int: Availability]
}

public actor LibCalClient: StudyAvailabilityService {
    public static let defaultBaseURL = URL(string: "https://libcal.library.gatech.edu")!

    private let baseURL: URL
    private let session: URLSession
    private let formatter = LibCal.makeFormatter()

    public init(baseURL: URL = LibCalClient.defaultBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func availability(locationIDs: [Int], on date: Date = Date()) async throws -> [Int: Availability] {
        var combined: [Int: Availability] = [:]
        for lid in locationIDs {
            let page = try await grid(lid: lid, on: date)
            combined.merge(page) { existing, new in
                Availability(spaceID: existing.spaceID, free: LibCal.merge(existing.free + new.free))
            }
        }
        return combined
    }

    private func grid(lid: Int, on date: Date) async throws -> [Int: Availability] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = formatter.timeZone
        let day = calendar.startOfDay(for: date)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) else { return [:] }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = formatter.timeZone
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")

        var request = URLRequest(url: baseURL.appendingPathComponent("spaces/availability/grid"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(baseURL.appendingPathComponent("spaces").absoluteString, forHTTPHeaderField: "Referer")
        let body = [
            "lid=\(lid)", "gid=0", "eid=-1", "seat=0", "seatId=0", "zone=0",
            "start=\(dayFormatter.string(from: day))",
            "end=\(dayFormatter.string(from: tomorrow))",
            "pageIndex=0", "pageSize=100",
        ].joined(separator: "&")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw StudyError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try LibCal.availability(fromJSON: data, formatter: formatter)
    }

    public enum StudyError: Error, LocalizedError {
        case badResponse(Int)

        public var errorDescription: String? {
            switch self {
            case .badResponse(let code): "The library's booking system returned an error (\(code))."
            }
        }
    }
}

/// Deterministic availability for previews and tests.
public struct PreviewStudyService: StudyAvailabilityService {
    public init() {}

    public func availability(locationIDs: [Int], on date: Date) async throws -> [Int: Availability] {
        let now = Date()
        return [
            158668: Availability(spaceID: 158668, free: [DateInterval(start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(5400))]),
            158669: Availability(spaceID: 158669, free: [DateInterval(start: now.addingTimeInterval(7200), end: now.addingTimeInterval(14400))]),
        ]
    }
}
