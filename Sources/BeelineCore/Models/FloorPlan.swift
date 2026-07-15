import Foundation

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

    public func floor(forRoom room: String) -> Floor? {
        floors.first { $0.room(room) != nil }
    }
}

public extension CampusPack {
    func coordinate(of place: Place) -> Coordinate? {
        if let lat = place.lat, let lng = place.lng {
            return Coordinate(lat: lat, lng: lng)
        }
        guard let id = place.buildingId,
              let building = buildings.first(where: { $0.id == id }) else { return nil }
        return Coordinate(lat: building.lat, lng: building.lng)
    }

    func floorPlan(for buildingID: String) -> FloorPlan? {
        floorplans.first { $0.buildingId == buildingID }
    }

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
