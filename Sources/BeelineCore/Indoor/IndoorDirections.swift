import Foundation

public struct IndoorStep: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case enter
        case straight
        case left
        case right
        case stairs(to: Int)
        case elevator(to: Int)
        case arrive
    }

    public var id: Int
    public var kind: Kind
    public var text: String
    public var level: Int
    public var node: IndoorNode

    public var symbolName: String {
        switch kind {
        case .enter: "door.left.hand.open"
        case .straight: "arrow.up"
        case .left: "arrow.turn.up.left"
        case .right: "arrow.turn.up.right"
        case .stairs: "figure.stairs"
        case .elevator: "arrow.up.arrow.down.square"
        case .arrive: "mappin.and.ellipse"
        }
    }
}

public enum IndoorDirections {

    static let turnThreshold = 40.0

    static func bearing(from a: IndoorNode, to b: IndoorNode) -> Double {
        let degrees = atan2(b.x - a.x, -(b.y - a.y)) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    static func turn(from a: Double, to b: Double) -> Double {
        var d = b - a
        while d > 180 { d -= 360 }
        while d <= -180 { d += 360 }
        return d
    }

    public static func steps(for path: IndoorRouter.Path, in graph: IndoorGraph, room: String? = nil) -> [IndoorStep] {
        let resolved: [(ref: NodeRef, node: IndoorNode)] = path.nodes.compactMap { ref in
            guard let node = graph.floor(level: ref.level)?.node(ref.id) else { return nil }
            return (ref, node)
        }
        guard let first = resolved.first else { return [] }

        var steps: [IndoorStep] = []
        var index = 0

        steps.append(
            IndoorStep(
                id: index,
                kind: .enter,
                text: first.node.name.map { "Enter at \($0)" } ?? "Enter the building",
                level: first.ref.level,
                node: first.node
            )
        )
        index += 1

        var heading: Double?
        var arrivalAngle: Double?
        let lastIndex = resolved.count - 1
        let endsAtDoor = resolved.last.map { $0.node.kind == .room || $0.node.kind == .door } ?? false

        var i = 1
        while i < resolved.count {
            let previous = resolved[i - 1]
            let current = resolved[i]

            if current.ref.level != previous.ref.level {
                let going = current.ref.level > previous.ref.level ? "up" : "down"
                let floorName = ordinal(current.ref.level)
                let isLift = previous.node.kind == .elevator || current.node.kind == .elevator
                steps.append(
                    IndoorStep(
                        id: index,
                        kind: isLift ? .elevator(to: current.ref.level) : .stairs(to: current.ref.level),
                        text: isLift
                            ? "Take the lift \(going) to the \(floorName)"
                            : "Take the stairs \(going) to the \(floorName)",
                        level: current.ref.level,
                        node: current.node
                    )
                )
                index += 1
                heading = nil
                i += 1
                continue
            }

            let next = bearing(from: previous.node, to: current.node)
            let isFinalApproach = i == lastIndex && endsAtDoor
            if let previousHeading = heading {
                let angle = turn(from: previousHeading, to: next)
                if isFinalApproach {
                    arrivalAngle = angle
                } else if abs(angle) >= turnThreshold {
                    steps.append(
                        IndoorStep(
                            id: index,
                            kind: angle < 0 ? .left : .right,
                            text: angle < 0 ? "Turn left" : "Turn right",
                            level: current.ref.level,
                            node: current.node
                        )
                    )
                    index += 1
                }
            } else if steps.count == 1 {
                steps.append(
                    IndoorStep(
                        id: index,
                        kind: .straight,
                        text: "Follow the corridor",
                        level: current.ref.level,
                        node: current.node
                    )
                )
                index += 1
            }
            heading = next
            i += 1
        }

        if let last = resolved.last {
            var text = room.map { "Room \($0)" } ?? (last.node.room.map { "Room \($0)" } ?? "You've arrived")
            if last.node.room != nil || room != nil {
                if let angle = arrivalAngle, abs(angle) >= turnThreshold {
                    text += angle < 0 ? " is on your left" : " is on your right"
                } else {
                    text += " is ahead"
                }
            }
            steps.append(
                IndoorStep(id: index, kind: .arrive, text: text, level: last.ref.level, node: last.node)
            )
        }

        return steps
    }

    static func ordinal(_ level: Int) -> String {
        switch level {
        case 0: "basement"
        case 1: "1st floor"
        case 2: "2nd floor"
        case 3: "3rd floor"
        default: "\(level)th floor"
        }
    }
}
