import MapKit
import SwiftUI
import BeelineCore

/// The idle state of the map sheet: a search field, the next class, and
/// quick categories. Everything here answers "where am I going?".
struct SearchSheet: View {
    @Environment(AppModel.self) private var model
    let expand: () -> Void
    @Binding var camera: MapCameraPosition
    @Binding var selection: String?

    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Room, class, or place", text: $model.query)
                    .searchKeyboard()
                    .focused($searchFocused)
                    .submitLabel(.search)
                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.groupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal)
            .padding(.top, 2)
            .onChange(of: searchFocused) { _, focused in
                if focused { expand() }
            }

            if model.query.isEmpty {
                idleContent
            } else {
                resultsList
            }
        }
    }

    // MARK: Idle

    private var idleContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let next = model.nextClass() {
                    NextClassCard(next: next) {
                        model.route(to: .room(buildingID: next.event.buildingID, room: next.event.room))
                    }
                    .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Nearby")
                        .font(.headline)
                        .padding(.horizontal)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Category.allCases) { category in
                                Button {
                                    model.query = category.query
                                    expand()
                                } label: {
                                    Label(category.title, systemImage: category.symbol)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.groupedBackground, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Busiest buildings")
                        .font(.headline)
                    ForEach(popularBuildings, id: \.id) { building in
                        Button {
                            show(building)
                        } label: {
                            HStack {
                                Image(systemName: "building.2.fill")
                                    .foregroundStyle(Color.beelineNavy)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(building.shortName).foregroundStyle(.primary)
                                    Text("\(model.rooms(in: building.id).count) rooms with classes")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 26)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
    }

    private var popularBuildings: [Building] {
        let counts = Dictionary(grouping: model.pack.rooms, by: \.buildingId)
            .mapValues { $0.reduce(0) { $0 + $1.meetings.count } }
        return counts.sorted { $0.value > $1.value }
            .prefix(6)
            .compactMap { model.building($0.key) }
    }

    // MARK: Results

    private var resultsList: some View {
        List(model.results) { result in
            Button {
                select(result)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: symbol(for: result))
                        .font(.body)
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(tint(for: result), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(result.title)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if !result.subtitle.isEmpty {
                            Text(result.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
        .listStyle(.plain)
        .overlay {
            if model.results.isEmpty {
                ContentUnavailableView.search(text: model.query)
            }
        }
    }

    private func symbol(for result: SearchResult) -> String {
        switch result {
        case .building: "building.2.fill"
        case .room: "door.left.hand.open"
        case .course: "graduationcap.fill"
        case .place(let p): Category.symbol(forKind: p.kind)
        }
    }

    private func tint(for result: SearchResult) -> Color {
        switch result {
        case .building: .beelineNavy
        case .room: .beelineGold
        case .course: .beelineWalk
        case .place: .gray
        }
    }

    // MARK: Actions

    private func select(_ result: SearchResult) {
        searchFocused = false
        switch result {
        case .building(let b):
            show(b)
        case .room(let room, let building):
            model.route(to: .room(buildingID: building.id, room: room.room))
        case .course(_, _, let rooms):
            if let (room, building) = rooms.first {
                model.route(to: .room(buildingID: building.id, room: room.room))
            }
        case .place(let p):
            model.route(to: .place(p.id))
        }
        model.query = ""
    }

    private func show(_ building: Building) {
        searchFocused = false
        selection = building.id
        model.query = ""
        withAnimation {
            camera = .region(MKCoordinateRegion(center: building.center, latitudinalMeters: 320, longitudinalMeters: 320))
        }
        model.route(to: .building(building.id))
    }
}

enum Category: String, CaseIterable, Identifiable {
    case dining, restroom, library, gym, study, stop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dining: "Food"
        case .restroom: "Restrooms"
        case .library: "Library"
        case .gym: "Gym"
        case .study: "Study"
        case .stop: "Bus stops"
        }
    }

    var query: String { rawValue }

    var symbol: String { Self.symbol(forKind: rawValue) }

    static func symbol(forKind kind: String) -> String {
        switch kind {
        case "dining": "fork.knife"
        case "restroom": "figure.dress.line.vertical.figure"
        case "library": "books.vertical.fill"
        case "gym": "figure.run"
        case "study": "lamp.desk.fill"
        case "stop": "bus.fill"
        case "parking": "parkingsign"
        case "lactation": "figure.and.child.holdinghands"
        default: "mappin"
        }
    }
}

struct NextClassCard: View {
    let next: (event: ClassEvent, minutesUntil: Int, walkMinutes: Double?)
    let go: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Next class", systemImage: "graduationcap.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.beelineNavy)
                Spacer()
                Text(countdown)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(next.event.meeting.course)
                    .font(.title3.weight(.semibold))
                Text("\(next.event.location) · \(next.event.timeRange)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if let walk = next.walkMinutes {
                    Label("\(Int(walk)) min walk", systemImage: "figure.walk")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Directions", action: go)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .card()
    }

    private var countdown: String {
        let m = next.minutesUntil
        if m < 0 { return "In progress" }
        if m == 0 { return "Starting now" }
        if m < 60 { return "in \(m) min" }
        if m < 1440 { return "in \(m / 60) hr" }
        return next.event.weekday.shortName
    }
}
