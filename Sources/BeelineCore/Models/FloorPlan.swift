import Foundation

/// A published floor plan: a page image plus the room labels on it, with
/// positions normalized 0–1 from the left and from the top of the image.
/// A room with no position is known to be on this floor but couldn't be
/// pinpointed — the app shows the plan without a marker rather than guess.

public struct PlanRoom: Codable, Hashable, Sendable, Identifiable {
    public var room: String
    public var x: Double?
    public var y: Double?

    public var id: String { room }
    public var isPositioned: Bool { x != nil && y != nil }
}

public struct Floor: Codable, Hashable, Sendable, Identifiable {
    public var level: Int
    public var name: String
    public var image: String
    public var width: Int
    public var height: Int
    public var rooms: [PlanRoom]

    public var id: Int { level }

    public var aspectRatio: Double {
        height > 0 ? Double(width) / Double(height) : 0.5625
    }

    public func room(_ number: String) -> PlanRoom? {
        rooms.first { $0.room.caseInsensitiveCompare(number) == .orderedSame }
    }

    /// The image, loaded from the package bundle.
    public var imageURL: URL? {
        let name = (image as NSString).deletingPathExtension
        let ext = (image as NSString).pathExtension
        return Bundle.module.url(forResource: name, withExtension: ext.isEmpty ? "png" : ext, subdirectory: "floorplans")
            ?? Bundle.module.url(forResource: name, withExtension: ext.isEmpty ? "png" : ext)
    }
}

public struct FloorPlan: Codable, Hashable, Sendable, Identifiable {
    public var buildingId: String
    public var source: String
    public var floors: [Floor]

    public var id: String { buildingId }

    public func floor(level: Int) -> Floor? {
        floors.first { $0.level == level }
    }

    /// The floor a room is on according to the plan itself — authoritative,
    /// unlike the room-number rule.
    public func floor(forRoom room: String) -> Floor? {
        floors.first { $0.room(room) != nil }
    }
}

public extension CampusPack {
    func floorPlan(for buildingID: String) -> FloorPlan? {
        floorplans.first { $0.buildingId == buildingID }
    }

    /// Where a plan exists it wins; otherwise fall back to the room-number rule.
    func locate(room: String, buildingID: String) -> RoomLocation {
        if let plan = floorPlan(for: buildingID), let floor = plan.floor(forRoom: room) {
            let decoded = RoomDecoder.decode(room: room, buildingID: buildingID)
            return RoomLocation(
                floor: floor.level,
                floorLabel: floor.name,
                wing: decoded.wing,
                hint: decoded.hint,
                isFromFloorPlan: true
            )
        }
        return RoomDecoder.decode(room: room, buildingID: buildingID)
    }
}
