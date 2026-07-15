import SwiftUI
import BeelineCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct FloorPlanView: View {
    let plan: FloorPlan
    let buildingName: String
    var highlight: String?

    @Environment(\.dismiss) private var dismiss
    @State private var level: Int

    init(plan: FloorPlan, buildingName: String, highlight: String? = nil) {
        self.plan = plan
        self.buildingName = buildingName
        self.highlight = highlight
        let start = highlight.flatMap { plan.floor(forRoom: $0)?.level }
            ?? plan.floors.map(\.level).min()
            ?? 1
        _level = State(initialValue: start)
    }

    private var floor: Floor? { plan.floor(level: level) }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                floorPicker
                Divider()
                planImage
            }
            .background(Color.groupedBackground)
            .navigationTitle(buildingName)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { caption }
        }
    }

    private var floorPicker: some View {
        VStack(spacing: 6) {
            ForEach(plan.floors.sorted { $0.level > $1.level }) { f in
                Button {
                    level = f.level
                } label: {
                    Text(f.level == 0 ? "B" : "\(f.level)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 34, height: 34)
                        .background(
                            level == f.level ? Color.beelineNavy : Color.cardBackground,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .foregroundStyle(level == f.level ? .white : .primary)
                        .overlay(alignment: .topTrailing) {
                            if let highlight, f.room(highlight) != nil {
                                Circle()
                                    .fill(Color.beelineGold)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 3, y: -3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(f.name)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .frame(width: 52)
    }

    @ViewBuilder
    private var planImage: some View {
        if let floor, let image = PlatformImage.load(floor.imageURL) {
            GeometryReader { geo in
                let size = fitted(floor.aspectRatio, in: geo.size)
                ZStack(alignment: .topLeading) {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: size.width, height: size.height)
                    if let highlight, let room = floor.room(highlight), let x = room.x, let y = room.y {
                        RoomMarker()
                            .position(x: x * size.width, y: y * size.height)
                            .frame(width: size.width, height: size.height)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        } else {
            ContentUnavailableView("Plan unavailable", systemImage: "doc.questionmark")
        }
    }

    private func fitted(_ aspect: Double, in bounds: CGSize) -> CGSize {
        let byWidth = CGSize(width: bounds.width, height: bounds.width / aspect)
        return byWidth.height <= bounds.height
            ? byWidth
            : CGSize(width: bounds.height * aspect, height: bounds.height)
    }

    @ViewBuilder
    private var caption: some View {
        let text: String = {
            guard let highlight else { return "Floor plans from the \(plan.source)." }
            guard let floor = plan.floor(forRoom: highlight) else {
                return "Room \(highlight) isn't labeled on these plans."
            }
            if floor.room(highlight)?.isPositioned == true {
                return "Room \(highlight) is on the \(floor.name.lowercased())."
            }
            return "Room \(highlight) is on the \(floor.name.lowercased()), but isn't pinpointed on the plan."
        }()

        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal)
            .background(.regularMaterial)
    }
}

struct RoomMarker: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.beelineGold, lineWidth: 3)
                .frame(width: pulse ? 78 : 48, height: pulse ? 78 : 48)
                .opacity(pulse ? 0 : 0.85)
            Circle()
                .stroke(Color.beelineGold, lineWidth: 3.5)
                .frame(width: 46, height: 46)
        }
        .shadow(color: .black.opacity(0.25), radius: 2)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
        .accessibilityHidden(true)
    }
}

enum PlatformImage {
    static func load(_ url: URL?) -> Image? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        return nil
        #endif
    }
}

struct FloorPlanView_Previews: PreviewProvider {
    static var previews: some View {
        let pack = (try? CampusPack.bundled()) ?? .empty
        if let plan = pack.floorplans.first {
            FloorPlanView(plan: plan, buildingName: "Clough", highlight: "144")
        }
    }
}
