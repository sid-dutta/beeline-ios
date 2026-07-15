import SwiftUI
import BeelineCore

struct RouteSheet: View {
    @Environment(AppModel.self) private var model
    let active: AppModel.ActiveRoute
    let expand: () -> Void
    @State private var showingPlan = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if model.busOption != nil {
                        tripChooser
                    }
                    if let indoor = indoorGuidance {
                        indoorCard(indoor)
                    }
                    if let trip = model.selectedTrip, !trip.isWalkOnly {
                        ForEach(Array(trip.legs.enumerated()), id: \.offset) { index, leg in
                            TripLegRow(leg: leg, isLast: index == trip.legs.count - 1)
                        }
                    } else {
                        ForEach(active.steps) { step in
                            StepRow(step: step, isLast: step.id == active.steps.last?.id)
                        }
                    }
                }
                .padding(.bottom, 32)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(active.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.clearRoute()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary, Color.groupedBackground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("End route")
            }

            HStack(spacing: 14) {
                Label(
                    "\(model.selectedTrip?.minutes ?? Int(active.route.minutes)) min",
                    systemImage: (model.selectedTrip?.isWalkOnly ?? true) ? "figure.walk" : "bus.fill"
                )
                .font(.headline)
                .foregroundStyle(Color.beelineWalk)
                Text(Directions.format(model.selectedTrip?.walkingMeters ?? active.route.meters))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if active.route.hasSteps {
                    Label("Stairs", systemImage: "figure.stairs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !active.startedFromLocation {
                Label("From the center of campus. Turn on location for directions from where you are.", systemImage: "location.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    private var tripChooser: some View {
        HStack(spacing: 8) {
            ForEach(Array(model.tripOptions.enumerated()), id: \.offset) { index, trip in
                Button {
                    model.selectTrip(index)
                } label: {
                    VStack(spacing: 2) {
                        Label(
                            trip.isWalkOnly ? "Walk" : trip.routeName ?? "Bus",
                            systemImage: trip.isWalkOnly ? "figure.walk" : "bus.fill"
                        )
                        .font(.caption.weight(.medium))
                        Text("\(trip.minutes) min")
                            .font(.headline.monospacedDigit())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        model.selectedTripIndex == index ? Color.beelineNavy.opacity(0.12) : Color.groupedBackground,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(model.selectedTripIndex == index ? Color.beelineNavy : .clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private var subtitle: String {
        if let s = active.subtitle, !s.isEmpty { return s }
        if let entrance = active.entrance { return "Via \(entrance.doorDescription)" }
        return "Walking directions"
    }

    private var indoorGuidance: RoomLocation? {
        guard case .room(let buildingID, let room) = active.destination else { return nil }
        let located = model.locate(room: room, in: buildingID)
        return located.floor == nil && located.hint == nil ? nil : located
    }

    private var floorPlan: (plan: FloorPlan, room: String, name: String)? {
        guard case .room(let buildingID, let room) = active.destination,
              let plan = model.floorPlan(for: buildingID) else { return nil }
        return (plan, room, model.building(buildingID)?.shortName ?? active.title)
    }

    private func indoorCard(_ location: RoomLocation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("Once inside", systemImage: "arrow.up.forward.square")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.beelineGold)
                if location.isFromFloorPlan {
                    Text("FROM FLOOR PLAN")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                if let floor = location.floor {
                    FloorBadge(floor: floor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.summary)
                        .font(.subheadline.weight(.medium))
                    if let hint = location.hint {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            if let fp = floorPlan {
                Button {
                    showingPlan = true
                } label: {
                    Label("View floor plan", systemImage: "map")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .sheet(isPresented: $showingPlan) {
                    FloorPlanView(plan: fp.plan, buildingName: fp.name, highlight: fp.room)
                }
            } else {
                Text("Floor plans for this building aren't published, so this comes from the room number.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .card(padding: 14)
        .padding(.horizontal)
        .padding(.top, 12)
    }

    struct FloorBadge: View {
        let floor: Int

        var body: some View {
            VStack(spacing: -2) {
                Text(floor == 0 ? "B" : "\(floor)")
                    .font(.title3.weight(.bold))
                Text("FLOOR")
                    .font(.system(size: 7, weight: .semibold))
                    .tracking(0.5)
            }
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(Color.beelineGold, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}

struct StepRow: View {
    let step: Step
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Image(systemName: step.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(step.kind == .arrive ? Color.beelineNavy : .secondary)
                    .frame(width: 30, height: 30)
                    .background(Color.groupedBackground, in: Circle())
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(minHeight: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.text)
                    .font(.subheadline)
                    .fontWeight(step.kind == .arrive ? .semibold : .regular)
                if step.meters > 0 {
                    Text(Directions.format(step.meters))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 5)
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

struct TripLegRow: View {
    let leg: Trip.Leg
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(Color.groupedBackground, in: Circle())
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(minHeight: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 5)
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var symbol: String {
        switch leg {
        case .walk: "figure.walk"
        case .wait: "clock"
        case .ride: "bus.fill"
        }
    }

    private var tint: Color {
        switch leg {
        case .walk: .secondary
        case .wait: .orange
        case .ride: .beelineNavy
        }
    }

    private var title: String {
        switch leg {
        case .walk(_, _, _, let to): "Walk to \(to)"
        case .wait(let seconds, let route, let stop): "Wait for the \(route) at \(stop)"
        case .ride(_, let route, _, let alight, _, let stops, _):
            "Ride the \(route) \(stops) stop\(stops == 1 ? "" : "s") to \(alight)"
        }
    }

    private var detail: String? {
        switch leg {
        case .walk(let meters, let seconds, _, _):
            "\(Directions.format(meters)) · \(minutes(seconds))"
        case .wait(let seconds, _, _):
            seconds < 60 ? "less than a minute" : minutes(seconds)
        case .ride(_, _, let board, _, let seconds, _, _):
            "From \(board) · \(minutes(seconds))"
        }
    }

    private func minutes(_ seconds: TimeInterval) -> String {
        let m = max(1, Int((seconds / 60).rounded()))
        return "\(m) min"
    }
}
