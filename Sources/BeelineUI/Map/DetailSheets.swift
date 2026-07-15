import SwiftUI
import BeelineCore

/// What's in a building: its rooms with classes, its doors, and the places
/// inside it. Shown before routing, because "is this the right building?" is
/// the question people actually have.
struct BuildingSheet: View {
    @Environment(AppModel.self) private var model
    let building: Building
    let onRoute: () -> Void
    let onDismiss: () -> Void
    let onSelectRoom: (String) -> Void

    @State private var showingPlan = false

    private var rooms: [Room] { model.rooms(in: building.id) }
    private var inside: [Place] { model.places(inBuilding: building.id) }
    private var plan: FloorPlan? { model.floorPlan(for: building.id) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let plan {
                        Button {
                            showingPlan = true
                        } label: {
                            Label("Floor plans (\(plan.floors.count) floors)", systemImage: "map")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .padding(.horizontal)
                    }

                    if !inside.isEmpty {
                        Section3(title: "Inside") {
                            ForEach(inside) { place in
                                HStack(spacing: 10) {
                                    Image(systemName: PlaceLayer.from(kind: place.kind)?.symbol ?? "mappin")
                                        .font(.caption)
                                        .foregroundStyle(Color.beelineNavy)
                                        .frame(width: 22)
                                    Text(place.displayName)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    if let status = model.status(for: place) {
                                        StatusPill(status: status)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }

                    if !rooms.isEmpty {
                        Section3(title: "\(rooms.count) rooms with classes") {
                            ForEach(rooms) { room in
                                Button {
                                    onSelectRoom(room.room)
                                } label: {
                                    HStack(spacing: 10) {
                                        Text(room.room)
                                            .font(.subheadline.weight(.medium))
                                            .monospacedDigit()
                                            .frame(minWidth: 46, alignment: .leading)
                                        Text(model.locate(room: room.room, in: building.id).summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer(minLength: 0)
                                        Text("\(room.meetings.count)")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                        Image(systemName: "chevron.right")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 3)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Section3(title: "Entrances") {
                        ForEach(building.entrances) { entrance in
                            HStack(spacing: 10) {
                                Image(systemName: entrance.accessible ? "figure.roll" : "door.left.hand.open")
                                    .font(.caption)
                                    .foregroundStyle(entrance.accessible ? Color.beelineWalk : .secondary)
                                    .frame(width: 22)
                                Text(entrance.doorDescription.capitalizedFirst)
                                    .font(.subheadline)
                                Spacer(minLength: 0)
                                if entrance.source == "synthetic" {
                                    Text("approx.")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                .padding(.vertical, 16)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showingPlan) {
            if let plan {
                FloorPlanView(plan: plan, buildingName: building.shortName)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(building.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CloseButton(action: onDismiss)
            }
            Button(action: onRoute) {
                Label("Directions", systemImage: "figure.walk")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let num = building.bldgNum { parts.append("Building \(num)") }
        if let kind = building.kind { parts.append(kind) }
        if let levels = building.levels { parts.append("\(levels) floors") }
        if let walk = model.walkMinutes(toBuilding: building.id) { parts.append("\(Int(walk)) min walk") }
        return parts.joined(separator: " · ")
    }
}

/// A single point of interest — a restroom, a café, a bus stop, a study room.
struct PlaceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let place: Place
    let onRoute: () -> Void
    let onDismiss: () -> Void

    private var building: Building? { place.buildingId.flatMap(model.building) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.displayName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CloseButton(action: onDismiss)
            }
            .padding(.horizontal)
            .padding(.top, 2)

            if let status = model.status(for: place) {
                HStack(spacing: 8) {
                    StatusPill(status: status)
                    Text(statusDetail(status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 10)
            }

            HStack(spacing: 10) {
                Button(action: onRoute) {
                    Label("Directions", systemImage: "figure.walk")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                if let url = place.url.flatMap(URL.init(string:)) {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Book", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.top, 12)

            if place.kind == "restroom" {
                Note("Georgia Tech publishes locations for gender-inclusive single-occupancy restrooms only, so this list isn't every restroom on campus.")
            } else if place.kind == "vending" {
                Note("Georgia Tech's map doesn't say what each machine stocks.")
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 20)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let layer = PlaceLayer.from(kind: place.kind) { parts.append(layer.title) }
        if let capacity = place.capacity { parts.append("Seats \(capacity)") }
        if let building { parts.append(building.shortName) }
        if let id = place.buildingId, let walk = model.walkMinutes(toBuilding: id) {
            parts.append("\(Int(walk)) min walk")
        }
        return parts.joined(separator: " · ")
    }

    private func statusDetail(_ status: Availability.Status) -> String {
        switch status {
        case .free(_, let until): "Free until \(StudyRoomRow.clock.string(from: until))"
        case .freeIndefinitely: "Open now"
        case .busy(let until): "Next free at \(StudyRoomRow.clock.string(from: until))"
        case .busyAllDay: "Booked for the rest of today"
        case .unknown: "Availability unknown"
        }
    }
}

// MARK: - Small shared pieces

struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary, Color.groupedBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}

struct Section3<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
        .padding(.horizontal)
    }
}

struct Note: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)
            .padding(.top, 14)
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
