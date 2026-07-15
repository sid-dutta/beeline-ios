import Foundation

/// What a room number tells you before you have a floor plan. Every GT
/// building numbers rooms a little differently; the default rule covers most,
/// and the table below overrides the ones that don't.
public struct RoomLocation: Hashable, Sendable {
    public var floor: Int?
    /// "2nd floor", "Ground floor", "Lower level"
    public var floorLabel: String
    /// "East wing", "North wing"
    public var wing: String?
    /// Building-specific hint, e.g. which stairwell.
    public var hint: String?

    public var summary: String {
        [floorLabel, wing].compactMap { $0 }.joined(separator: " · ")
    }
}

public enum RoomDecoder {

    public static func decode(room: String, buildingID: String) -> RoomLocation {
        let trimmed = room.trimmingCharacters(in: .whitespaces).uppercased()
        if let special = specialCases[buildingID]?(trimmed) {
            return special
        }
        return defaultRule(trimmed, buildingID: buildingID)
    }

    // MARK: Default rule

    /// `E465` → East wing, floor 4. `1443` → floor 1. `L1105` → level 1.
    /// `16` → ground floor. `B12` → basement.
    static func defaultRule(_ room: String, buildingID: String) -> RoomLocation {
        let scanner = parse(room)
        guard let digits = scanner.digits, let firstDigit = digits.first.flatMap({ Int(String($0)) }) else {
            return RoomLocation(floor: nil, floorLabel: "Floor unknown", wing: nil, hint: nil)
        }

        var wing: String? = nil
        var floor: Int?
        switch scanner.prefix {
        case "N": wing = "North wing"
        case "S": wing = "South wing"
        case "E": wing = "East wing"
        case "W": wing = "West wing"
        case "B":
            return RoomLocation(floor: 0, floorLabel: "Basement", wing: nil, hint: nil)
        case "G":
            return RoomLocation(floor: 1, floorLabel: "Ground floor", wing: nil, hint: nil)
        case "L":
            // "L1105" = level 1; a bare "L2" is a lecture hall on the ground floor.
            if digits.count >= 3 {
                floor = firstDigit
                return RoomLocation(floor: floor, floorLabel: floorLabel(firstDigit), wing: nil, hint: nil)
            }
            return RoomLocation(floor: 1, floorLabel: "Ground floor", wing: nil, hint: "Lecture hall \(digits)")
        default: break
        }

        if digits.count >= 3 {
            floor = firstDigit
        } else {
            floor = 1
        }
        return RoomLocation(floor: floor, floorLabel: floorLabel(floor ?? 1), wing: wing, hint: nil)
    }

    static func floorLabel(_ floor: Int) -> String {
        switch floor {
        case 0: "Basement"
        case 1: "1st floor"
        case 2: "2nd floor"
        case 3: "3rd floor"
        default: "\(floor)th floor"
        }
    }

    struct Parsed {
        var prefix: String
        var digits: String?
        var suffix: String
    }

    static func parse(_ room: String) -> Parsed {
        var prefix = "", digits = "", suffix = ""
        var phase = 0
        for ch in room {
            if phase == 0 {
                if ch.isLetter { prefix.append(ch) } else if ch.isNumber { phase = 1; digits.append(ch) }
            } else if phase == 1 {
                if ch.isNumber { digits.append(ch) } else if ch.isLetter { phase = 2; suffix.append(ch) }
            } else if ch.isLetter {
                suffix.append(ch)
            }
        }
        return Parsed(prefix: prefix, digits: digits.isEmpty ? nil : digits, suffix: suffix)
    }

    // MARK: Building overrides (keyed by pack building id = "b<GT number>")

    /// Rules that are known to differ from the default. Grow this as we
    /// learn buildings; each entry is a small closure so it stays readable.
    static let specialCases: [String: @Sendable (String) -> RoomLocation?] = [
        // Klaus (bldg 156): 1xxx/2xxx floors; 1440s/2440s are the big lecture halls off the atrium.
        "b156": { room in
            let p = parse(room)
            guard let d = p.digits, d.count == 4, let f = Int(String(d.first!)) else { return nil }
            let hall = d.hasPrefix("\(f)44") || d.hasPrefix("\(f)45") ? "Lecture hall off the atrium" : nil
            return RoomLocation(floor: f, floorLabel: floorLabel(f), wing: nil, hint: hall)
        },
        // Howey (bldg 81): L1–L5 lecture halls on the ground floor; N/S wings.
        "b81": { room in
            let p = parse(room)
            if p.prefix == "L", let d = p.digits, d.count <= 2 {
                return RoomLocation(floor: 1, floorLabel: "Ground floor", wing: nil, hint: "Lecture hall L\(d)")
            }
            return nil
        },
        // College of Computing (bldg 50): 2-digit rooms (16, 17, 52, 53) are the ground-floor lecture halls.
        "b50": { room in
            let p = parse(room)
            guard let d = p.digits, d.count <= 2 else { return nil }
            return RoomLocation(floor: 1, floorLabel: "Ground floor", wing: nil, hint: "Lecture hall — enter from the atrium")
        },
    ]
}
