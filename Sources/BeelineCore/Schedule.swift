import Foundation

public struct EnrolledSection: Codable, Hashable, Sendable, Identifiable {
    public var course: String
    public var section: String

    public var id: String { "\(course)/\(section)" }

    public init(course: String, section: String) {
        self.course = course
        self.section = section
    }
}

public struct ClassEvent: Hashable, Sendable, Identifiable {
    public var meeting: Meeting
    public var buildingID: String
    public var buildingName: String
    public var room: String
    public var start: Int
    public var end: Int
    public var weekday: Weekday

    public var id: String { "\(meeting.crn)/\(weekday.rawValue)/\(start)" }

    public var location: String { "\(buildingName) \(room)" }

    public var timeRange: String {
        "\(Weekday.clock(start))–\(Weekday.clock(end))"
    }
}

public enum Weekday: Int, CaseIterable, Codable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    public var letter: Character {
        switch self {
        case .monday: "M"
        case .tuesday: "T"
        case .wednesday: "W"
        case .thursday: "R"
        case .friday: "F"
        case .saturday: "S"
        case .sunday: "U"
        }
    }

    public var shortName: String {
        switch self {
        case .sunday: "Sun"
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        }
    }

    public static func from(date: Date, calendar: Calendar = .current) -> Weekday {
        Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .monday
    }

    public static func minutesSinceMidnight(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    public static func clock(_ minutes: Int) -> String {
        let h24 = (minutes / 60) % 24, m = minutes % 60
        let suffix = h24 < 12 ? "AM" : "PM"
        var h = h24 % 12
        if h == 0 { h = 12 }
        return String(format: "%d:%02d %@", h, m, suffix)
    }
}

public struct Schedule: Sendable {
    public private(set) var events: [ClassEvent]

    public init(sections: [EnrolledSection], pack: CampusPack) {
        let buildings = Dictionary(pack.buildings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let wanted = Set(sections.map(\.id))
        var events: [ClassEvent] = []
        for room in pack.rooms {
            guard let building = buildings[room.buildingId] else { continue }
            for meeting in room.meetings {
                guard wanted.contains("\(meeting.course)/\(meeting.section)") else { continue }
                for day in Weekday.allCases where meeting.days.contains(day.letter) {
                    events.append(
                        ClassEvent(
                            meeting: meeting,
                            buildingID: building.id,
                            buildingName: building.shortName,
                            room: room.room,
                            start: meeting.start,
                            end: meeting.end,
                            weekday: day
                        )
                    )
                }
            }
        }
        self.events = events.sorted { ($0.weekday.rawValue, $0.start) < ($1.weekday.rawValue, $1.start) }
    }

    public func events(on day: Weekday) -> [ClassEvent] {
        events.filter { $0.weekday == day }
    }

    public func next(from now: Date = Date(), calendar: Calendar = .current) -> (event: ClassEvent, minutesUntil: Int)? {
        let today = Weekday.from(date: now, calendar: calendar)
        let minutes = Weekday.minutesSinceMidnight(now, calendar: calendar)

        for offset in 0..<8 {
            let dayIndex = (today.rawValue - 1 + offset) % 7 + 1
            guard let day = Weekday(rawValue: dayIndex) else { continue }
            let candidates = events(on: day).filter { offset > 0 || $0.end > minutes }
            guard let event = candidates.first else { continue }
            let until = offset == 0 ? event.start - minutes : offset * 1440 + event.start - minutes
            return (event, until)
        }
        return nil
    }

    public static func leaveBy(event: ClassEvent, walkMinutes: Double, buffer: Int = 3) -> Int {
        max(0, event.start - Int(walkMinutes.rounded(.up)) - buffer)
    }
}
