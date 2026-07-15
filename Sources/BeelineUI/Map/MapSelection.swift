import Foundation
import BeelineCore

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

enum PlaceLayer: String, CaseIterable, Identifiable, Equatable {
    case study, dining, restroom, vending, stop, library, gym, makerspace, quiet, parking, lactation

    var id: String { rawValue }

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

    static let featured: [PlaceLayer] = [.study, .dining, .restroom, .vending, .stop, .library]

    static func from(kind: String) -> PlaceLayer? {
        PlaceLayer(rawValue: kind)
    }
}
