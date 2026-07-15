import Foundation

/// Turns a route's coordinate chain into human steps: "Head north 120 m",
/// "Turn left", "Take the steps", "Enter Klaus at the west door".
public struct Step: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case depart, straight, slightLeft, left, sharpLeft, slightRight, right, sharpRight, arrive
    }

    public var id: Int
    public var kind: Kind
    public var text: String
    public var meters: Double
    public var coordinate: Coordinate

    public var symbolName: String {
        switch kind {
        case .depart: "figure.walk"
        case .straight: "arrow.up"
        case .slightLeft: "arrow.up.left"
        case .left: "arrow.turn.up.left"
        case .sharpLeft: "arrow.uturn.left"
        case .slightRight: "arrow.up.right"
        case .right: "arrow.turn.up.right"
        case .sharpRight: "arrow.uturn.right"
        case .arrive: "mappin.and.ellipse"
        }
    }
}

public enum Directions {

    /// Minimum leg length that gets its own step; shorter wiggles are merged.
    static let minimumLegMeters = 12.0
    /// Below this angle a bend is "continue", not a turn.
    static let turnThreshold = 35.0

    public static func steps(for coordinates: [Coordinate], destinationName: String, entranceName: String? = nil) -> [Step] {
        guard coordinates.count >= 2 else {
            return [Step(id: 0, kind: .arrive, text: "You're at \(destinationName)", meters: 0, coordinate: coordinates.first ?? Coordinate(lat: 0, lng: 0))]
        }

        // Simplify: drop points that barely change direction so each step is a real leg.
        var legs: [(start: Coordinate, end: Coordinate, meters: Double, bearing: Double)] = []
        var legStart = coordinates[0]
        var legMeters = 0.0
        var legBearing: Double? = nil
        for i in 1..<coordinates.count {
            let a = coordinates[i - 1], b = coordinates[i]
            let m = Geo.distanceMeters(a.lat, a.lng, b.lat, b.lng)
            let br = Geo.bearing(a.lat, a.lng, b.lat, b.lng)
            if let lb = legBearing, abs(Geo.turnAngle(from: lb, to: br)) >= turnThreshold, legMeters >= minimumLegMeters {
                legs.append((legStart, a, legMeters, lb))
                legStart = a
                legMeters = 0
                legBearing = br
            } else if legBearing == nil {
                legBearing = br
            }
            legMeters += m
            // Keep the leg's bearing anchored to its first segment; small drift is fine.
        }
        legs.append((legStart, coordinates[coordinates.count - 1], legMeters, legBearing ?? 0))

        var steps: [Step] = []
        for (i, leg) in legs.enumerated() {
            let kind: Step.Kind
            let text: String
            if i == 0 {
                kind = .depart
                text = "Head \(Geo.compassName(leg.bearing)) for \(format(leg.meters))"
            } else {
                let angle = Geo.turnAngle(from: legs[i - 1].bearing, to: leg.bearing)
                kind = turnKind(angle)
                text = "\(turnText(kind)) and continue \(format(leg.meters))"
            }
            steps.append(Step(id: i, kind: kind, text: text, meters: leg.meters, coordinate: leg.start))
        }
        let arrival = entranceName.map { "Enter \(destinationName) at \($0)" } ?? "Arrive at \(destinationName)"
        steps.append(Step(id: legs.count, kind: .arrive, text: arrival, meters: 0, coordinate: coordinates[coordinates.count - 1]))
        return steps
    }

    static func turnKind(_ angle: Double) -> Step.Kind {
        switch angle {
        case ..<(-150): .sharpLeft
        case ..<(-70): .left
        case ..<(-turnThreshold): .slightLeft
        case ...turnThreshold: .straight
        case ...70: .slightRight
        case ...150: .right
        default: .sharpRight
        }
    }

    static func turnText(_ kind: Step.Kind) -> String {
        switch kind {
        case .sharpLeft: "Turn sharp left"
        case .left: "Turn left"
        case .slightLeft: "Bear left"
        case .straight: "Continue straight"
        case .slightRight: "Bear right"
        case .right: "Turn right"
        case .sharpRight: "Turn sharp right"
        case .depart, .arrive: ""
        }
    }

    public static func format(_ meters: Double) -> String {
        let feet = meters * 3.28084
        if feet < 100 { return "\(Int((feet / 10).rounded() * 10)) ft" }
        if feet < 1000 { return "\(Int((feet / 50).rounded() * 50)) ft" }
        return String(format: "%.1f mi", feet / 5280)
    }
}
