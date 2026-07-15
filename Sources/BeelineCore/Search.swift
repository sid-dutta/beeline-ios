import Foundation

/// One search box for buildings, rooms, courses, and places.
public enum SearchResult: Identifiable, Hashable, Sendable {
    case building(Building)
    case room(Room, Building)
    case course(String, title: String, rooms: [(Room, Building)])
    case place(Place)

    public var id: String {
        switch self {
        case .building(let b): "b:\(b.id)"
        case .room(let r, _): "r:\(r.id)"
        case .course(let c, _, _): "c:\(c)"
        case .place(let p): "p:\(p.id)"
        }
    }

    public static func == (lhs: SearchResult, rhs: SearchResult) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public var title: String {
        switch self {
        case .building(let b): b.name
        case .room(let r, let b): "\(b.shortName) \(r.room)"
        case .course(let c, let title, _): "\(c) — \(title)"
        case .place(let p): p.name
        }
    }

    public var subtitle: String {
        switch self {
        case .building(let b): b.kind ?? "Building"
        case .room(let r, let b): RoomDecoder.decode(room: r.room, buildingID: b.id).summary
        case .course(_, _, let rooms): rooms.map { "\($0.1.shortName) \($0.0.room)" }.joined(separator: ", ")
        case .place(let p): p.kind.capitalized
        }
    }
}

public struct SearchIndex: Sendable {
    private let buildings: [Building]
    private let buildingsByID: [String: Building]
    private let rooms: [Room]
    private let places: [Place]
    /// course id → (title, rooms)
    private let courses: [String: (String, [(Room, Building)])]

    public init(pack: CampusPack) {
        buildings = pack.buildings
        // Tolerate a malformed pack rather than trapping in front of the user.
        buildingsByID = Dictionary(pack.buildings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        rooms = pack.rooms
        places = pack.places
        var courses: [String: (String, [(Room, Building)])] = [:]
        for room in pack.rooms {
            guard let b = buildingsByID[room.buildingId] else { continue }
            for m in room.meetings {
                var entry = courses[m.course] ?? (m.title, [])
                if !entry.1.contains(where: { $0.0.id == room.id }) { entry.1.append((room, b)) }
                courses[m.course] = entry
            }
        }
        self.courses = courses
    }

    public func building(id: String) -> Building? { buildingsByID[id] }

    public func rooms(in buildingID: String) -> [Room] {
        rooms.filter { $0.buildingId == buildingID }.sorted { $0.room.localizedStandardCompare($1.room) == .orderedAscending }
    }

    public func search(_ query: String, limit: Int = 25) -> [SearchResult] {
        let q = normalize(query)
        guard !q.isEmpty else { return [] }
        let qTokens = q.split(separator: " ").map(String.init)
        var scored: [(Double, SearchResult)] = []

        // "klaus 1443", "van leer e465", "1443"
        if let (bq, roomQ) = splitRoomQuery(qTokens) {
            for room in rooms where normalize(room.room).hasPrefix(roomQ) {
                guard let b = buildingsByID[room.buildingId] else { continue }
                let bScore = bq.isEmpty ? 0.6 : nameScore(bq, b)
                if bScore > 0 {
                    scored.append((2.0 + bScore + (normalize(room.room) == roomQ ? 0.5 : 0), .room(room, b)))
                }
            }
        }

        // Courses: "cs 1332", "cs1332", "data struct"
        let compact = q.replacingOccurrences(of: " ", with: "")
        for (course, (title, rooms)) in courses {
            let cid = normalize(course), cidCompact = cid.replacingOccurrences(of: " ", with: "")
            if cidCompact.hasPrefix(compact) || cid == q {
                scored.append((1.8 + (cidCompact == compact ? 0.5 : 0), .course(course, title: title, rooms: rooms)))
            } else if qTokens.count >= 2, tokenScore(qTokens, normalize(title)) >= 0.99 {
                scored.append((1.2, .course(course, title: title, rooms: rooms)))
            }
        }

        for b in buildings {
            let s = nameScore(q, b)
            if s > 0 { scored.append((1.0 + s, .building(b))) }
        }

        for p in places {
            let s = tokenScore(qTokens, normalize(p.name))
            if s > 0 { scored.append((0.5 + s, .place(p))) }
            else if normalize(p.kind).hasPrefix(q) { scored.append((0.4, .place(p))) }
        }

        var seen = Set<String>()
        return scored
            .sorted { $0.0 > $1.0 }
            .compactMap { seen.insert($0.1.id).inserted ? $0.1 : nil }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Scoring

    private func nameScore(_ q: String, _ b: Building) -> Double {
        let qTokens = q.split(separator: " ").map(String.init)
        var best = 0.0
        for name in [b.name, b.shortName] + b.aliases {
            let n = normalize(name)
            if n == q { return 1.0 }
            if n.hasPrefix(q) { best = max(best, 0.9) }
            best = max(best, tokenScore(qTokens, n) * 0.85)
        }
        return best
    }

    /// Fraction of query tokens that prefix-match a token of the candidate.
    private func tokenScore(_ qTokens: [String], _ candidate: String) -> Double {
        let cTokens = candidate.split(separator: " ").map(String.init)
        guard !qTokens.isEmpty, !cTokens.isEmpty else { return 0 }
        let hits = qTokens.filter { qt in cTokens.contains { $0.hasPrefix(qt) } }.count
        return hits == qTokens.count ? 1.0 : (hits > 0 && qTokens.count > 1 ? Double(hits) / Double(qTokens.count) * 0.5 : 0)
    }

    /// Last token that looks like a room number splits the query.
    private func splitRoomQuery(_ tokens: [String]) -> (String, String)? {
        guard let last = tokens.last, last.contains(where: \.isNumber) else { return nil }
        let head = tokens.dropLast().joined(separator: " ")
        // "cs 1332" is a course, not a room in a building called "cs".
        if head.count <= 4, head.allSatisfy(\.isLetter), courses.keys.contains(where: { normalize($0) == "\(head) \(last)" }) {
            return nil
        }
        return (head, last)
    }

    private func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
