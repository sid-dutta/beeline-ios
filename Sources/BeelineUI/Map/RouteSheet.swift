import SwiftUI
import BeelineCore

/// The active-route state of the map sheet: headline ETA, the room's floor
/// and wing, then the step list.
struct RouteSheet: View {
    @Environment(AppModel.self) private var model
    let active: AppModel.ActiveRoute
    @Binding var detent: PresentationDetent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let indoor = indoorGuidance {
                        indoorCard(indoor)
                    }
                    ForEach(active.steps) { step in
                        StepRow(step: step, isLast: step.id == active.steps.last?.id)
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
                Label("\(Int(active.route.minutes)) min", systemImage: "figure.walk")
                    .font(.headline)
                    .foregroundStyle(Color.beelineWalk)
                Text(Directions.format(active.route.meters))
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
                Label("From the center of campus — turn on location for directions from where you are.", systemImage: "location.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var subtitle: String {
        if let s = active.subtitle, !s.isEmpty { return s }
        if let entrance = active.entrance { return "Via \(entrance.doorDescription)" }
        return "Walking directions"
    }

    // MARK: Indoor guidance

    private var indoorGuidance: RoomLocation? {
        guard case .room(let buildingID, let room) = active.destination else { return nil }
        let decoded = RoomDecoder.decode(room: room, buildingID: buildingID)
        return decoded.floor == nil && decoded.hint == nil ? nil : decoded
    }

    private func indoorCard(_ location: RoomLocation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Once inside", systemImage: "arrow.up.forward.square")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.beelineGold)
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
            Text("Floor plans for this building aren't mapped yet — this comes from the room number.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
