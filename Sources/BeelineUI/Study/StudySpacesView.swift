import SwiftUI
import BeelineCore

/// Bookable library study rooms, free ones first. The question is never
/// "does a study room exist" — it's "can I walk into one right now".
struct StudySpacesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// Set when the user picks a room to walk to.
    let onRoute: (Place) -> Void

    @State private var freeOnly = false

    private var spaces: [Place] {
        freeOnly ? model.studySpaces.filter { model.status(for: $0)?.isFree == true } : model.studySpaces
    }

    private var grouped: [(building: String, rooms: [Place])] {
        var order: [String] = []
        var byBuilding: [String: [Place]] = [:]
        for space in spaces {
            let name = model.buildingName(for: space)
            if byBuilding[name] == nil { order.append(name) }
            byBuilding[name, default: []].append(space)
        }
        return order.map { ($0, byBuilding[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.studyAvailability.isEmpty && model.isRefreshingStudy {
                    ProgressView("Checking availability…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
            .navigationTitle("Study Rooms")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if model.isRefreshingStudy {
                        ProgressView().controlSize(.small)
                    } else {
                        Button {
                            Task { await model.refreshStudyAvailability() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
            .task {
                if model.studyAvailability.isEmpty { await model.refreshStudyAvailability() }
            }
        }
    }

    private var list: some View {
        List {
            Section {
                Toggle("Free right now", isOn: $freeOnly.animation())
            } footer: {
                Text(summary)
            }

            ForEach(grouped, id: \.building) { group in
                Section(group.building) {
                    ForEach(group.rooms) { room in
                        StudyRoomRow(room: room, status: model.status(for: room))
                            .contentShape(Rectangle())
                            .onTapGesture { onRoute(room) }
                            .swipeActions(edge: .trailing) {
                                if let url = room.url.flatMap(URL.init(string:)) {
                                    Button {
                                        openURL(url)
                                    } label: {
                                        Label("Book", systemImage: "calendar.badge.plus")
                                    }
                                    .tint(Color.beelineNavy)
                                }
                            }
                    }
                }
            }
        }
        .groupedList()
        .overlay {
            if spaces.isEmpty {
                ContentUnavailableView(
                    freeOnly ? "Nothing free right now" : "No study rooms",
                    systemImage: "book.closed",
                    description: Text(freeOnly ? "Turn off the filter to see every bookable room." : "The library's booking data couldn't be loaded.")
                )
            }
        }
    }

    private var summary: String {
        if let error = model.studyError { return error }
        let free = model.freeStudyCount
        let total = model.studySpaces.count
        guard model.studyUpdatedAt != nil else { return "\(total) bookable rooms in the library." }
        return "\(free) of \(total) rooms free right now. Tap a room for directions, swipe to book."
    }
}

struct StudyRoomRow: View {
    let room: Place
    let status: Availability.Status?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(room.displayName)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    if let capacity = room.capacity {
                        Label("\(capacity)", systemImage: "person.2.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            StatusPill(status: status)
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        switch status {
        case .free(_, let until): "until \(Self.clock.string(from: until))"
        case .freeIndefinitely: "open"
        case .busy(let until): "free at \(Self.clock.string(from: until))"
        case .busyAllDay: "booked for the rest of today"
        case .unknown, .none: "availability unknown"
        }
    }

    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}

struct StatusPill: View {
    let status: Availability.Status?

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color, in: Capsule())
    }

    private var label: String {
        switch status {
        case .free(let minutes, _): minutes >= 60 ? "Free \(minutes / 60)h" : "Free \(minutes)m"
        case .freeIndefinitely: "Free"
        case .busy: "Busy"
        case .busyAllDay: "Booked"
        case .unknown, .none: "—"
        }
    }

    private var color: Color {
        switch status {
        case .free, .freeIndefinitely: .beelineWalk
        case .busy, .busyAllDay: .secondary
        case .unknown, .none: Color.secondary.opacity(0.5)
        }
    }
}

struct StudySpacesView_Previews: PreviewProvider {
    static var previews: some View {
        StudySpacesView(onRoute: { _ in })
            .environment(AppModel.preview())
    }
}
