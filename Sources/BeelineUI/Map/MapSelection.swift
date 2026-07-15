import Foundation
import BeelineCore

/// What the map panel is showing. The map has one job at a time: browse and
/// search, look at a thing, or follow a route.
enum PanelState: Equatable {
    case search
    case building(String)
    case place(String)
    case route

    var isDetail: Bool {
        switch self {
        case .building, .place: true
        default: false
        }
    }
}

/// A category of places the user can switch on over the map.
enum PlaceLayer: String, CaseIterable, Identifiable, Equatable {
    case study, dining, restroom, vending, stop, library, gym, makerspace, quiet, parking, lactation

    var id: String { rawValue }

    /// The `kind` used in the data pack.
    var kind: String { rawValue }

    var title: String {
        switch self {
        case .study: "Study rooms"
        case .dining: "Food"
        case .restroom: "Restrooms"
        case .vending: "Vending"
        case .stop: "Bus stops"
        case .library: "Libraries"
        case .gym: "Gyms"
        case .makerspace: "Maker spaces"
        case .quiet: "Quiet rooms"
        case .parking: "Parking"
        case .lactation: "Lactation rooms"
        }
    }

    var symbol: String {
        switch self {
        case .study: "book.closed.fill"
        case .dining: "fork.knife"
        case .restroom: "figure.dress.line.vertical.figure"
        case .vending: "takeoutbag.and.cup.and.straw.fill"
        case .stop: "bus.fill"
        case .library: "books.vertical.fill"
        case .gym: "figure.run"
        case .makerspace: "wrench.and.screwdriver.fill"
        case .quiet: "moon.zzz.fill"
        case .parking: "parkingsign"
        case .lactation: "figure.and.child.holdinghands"
        }
    }

    /// Layers worth putting in the quick row, in the order students need them.
    static let featured: [PlaceLayer] = [.study, .dining, .restroom, .vending, .stop, .library]

    static func from(kind: String) -> PlaceLayer? {
        PlaceLayer(rawValue: kind)
    }
}
