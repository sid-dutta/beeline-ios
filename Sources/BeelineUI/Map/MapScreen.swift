import MapKit
import SwiftUI
import BeelineCore

/// Map with a draggable panel over it. The panel is an overlay rather than a
/// system sheet so it never covers the tab bar — a sheet at any detent would
/// make the other tabs unreachable.
struct MapScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationProvider.self) private var location

    @State private var camera: MapCameraPosition = .region(Self.campus)
    @State private var panel: PanelHeight = .peek
    @State private var state: PanelState = .search
    @State private var layer: PlaceLayer?
    @State private var dragOffset: CGFloat = 0

    enum PanelHeight {
        case peek, expanded

        func points(in total: CGFloat) -> CGFloat {
            switch self {
            case .peek: 168
            case .expanded: max(320, total * 0.72)
            }
        }
    }

    static let campus = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 33.7756, longitude: -84.3963),
        latitudinalMeters: 1700,
        longitudinalMeters: 1700
    )

    var body: some View {
        GeometryReader { geo in
            let height = min(max(panel.points(in: geo.size.height) - dragOffset, 120), geo.size.height - 60)
            ZStack(alignment: .bottom) {
                map
                    .ignoresSafeArea(edges: .top)
                    .overlay(alignment: .topLeading) { layerBar }
                panelContent
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: -2)
            }
        }
        .onChange(of: model.activeRoute?.title) {
            guard let active = model.activeRoute else { return }
            state = .route
            let shown = model.selectedTrip?.coordinates ?? active.route.coordinates
            withAnimation { camera = .region(region(fitting: shown)) }
            panel = .expanded
        }
    }

    // MARK: Map

    private var visiblePlaces: [Place] {
        guard let layer else { return [] }
        let centre = model.origin ?? Self.campus.center
        return model.nearestPlaces(ofKind: layer.kind, to: centre, limit: 60)
    }

    private var map: some View {
        Map(position: $camera) {
            UserAnnotation()

            ForEach(visiblePlaces) { place in
                if let c = model.pack.coordinate(of: place) {
                    Annotation(place.displayName, coordinate: c.clCoordinate, anchor: .bottom) {
                        PlacePin(
                            layer: PlaceLayer.from(kind: place.kind) ?? .dining,
                            isSelected: state == .place(place.id),
                            isFree: model.status(for: place)?.isFree
                        )
                        .onTapGesture { select(place) }
                    }
                    .annotationTitles(.hidden)
                }
            }

            if let active = model.activeRoute {
                // A bus trip draws its own walk-ride-walk path; a walking
                // route draws the footpath.
                if let trip = model.selectedTrip, !trip.isWalkOnly {
                    ForEach(Array(trip.legs.enumerated()), id: \.offset) { _, leg in
                        switch leg {
                        case .walk(_, _, let coords, _):
                            MapPolyline(coordinates: coords.map(\.clCoordinate))
                                .stroke(Color.beelineRoute, style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [2, 8]))
                        case .ride(let routeID, _, _, _, _, _, let coords):
                            MapPolyline(coordinates: coords.map(\.clCoordinate))
                                .stroke(
                                    Color(hex: model.route(routeID)?.color ?? "#888888"),
                                    style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                                )
                        case .wait:
                            EmptyMapContent()
                        }
                    }
                } else {
                    MapPolyline(coordinates: active.route.coordinates.map(\.clCoordinate))
                        .stroke(Color.beelineRoute, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                }
                if let start = active.route.coordinates.first {
                    Annotation("Start", coordinate: start.clCoordinate, anchor: .center) {
                        Circle()
                            .fill(.white)
                            .stroke(Color.beelineRoute, lineWidth: 4)
                            .frame(width: 14, height: 14)
                    }
                    .annotationTitles(.hidden)
                }
                if let end = active.route.coordinates.last {
                    Annotation(active.title, coordinate: end.clCoordinate) { DestinationPin() }
                }
            }

            if let building = highlightedBuilding {
                MapPolygon(coordinates: building.polygon.map(\.clCoordinate))
                    .foregroundStyle(Color.beelineGold.opacity(0.2))
                    .stroke(Color.beelineGold, lineWidth: 1.5)
                if model.activeRoute == nil {
                    Annotation(building.shortName, coordinate: building.center) { DestinationPin() }
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
    }

    private var highlightedBuilding: Building? {
        switch state {
        case .building(let id): model.building(id)
        case .route: model.activeRoute?.destination.buildingID.flatMap(model.building)
        case .place(let id): model.place(id)?.buildingId.flatMap(model.building)
        case .search: nil
        }
    }

    // MARK: Layer bar

    private var layerBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(PlaceLayer.featured) { candidate in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            layer = layer == candidate ? nil : candidate
                        }
                    } label: {
                        Label(candidate.title, systemImage: candidate.symbol)
                            .font(.caption.weight(.medium))
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                layer == candidate ? Color.beelineNavy : Color(white: 1, opacity: 0.92),
                                in: Capsule()
                            )
                            .foregroundStyle(layer == candidate ? .white : .primary)
                            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .scrollClipDisabled()
    }

    // MARK: Panel

    private var panelContent: some View {
        VStack(spacing: 0) {
            grabber
            switch state {
            case .route:
                if let active = model.activeRoute {
                    RouteSheet(active: active, expand: { panel = .expanded })
                }
            case .building(let id):
                if let building = model.building(id) {
                    BuildingSheet(
                        building: building,
                        onRoute: { model.route(to: .building(id)) },
                        onDismiss: dismissDetail,
                        onSelectRoom: { model.route(to: .room(buildingID: id, room: $0)) }
                    )
                }
            case .place(let id):
                if let place = model.place(id) {
                    PlaceSheet(
                        place: place,
                        onRoute: { model.route(to: .place(id)) },
                        onDismiss: dismissDetail
                    )
                }
            case .search:
                SearchSheet(
                    expand: { panel = .expanded },
                    onSelectBuilding: show(building:),
                    onSelectPlace: select
                )
            }
        }
    }

    private var grabber: some View {
        Capsule()
            .fill(.secondary.opacity(0.5))
            .frame(width: 36, height: 5)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { dragOffset = $0.translation.height }
                    .onEnded { value in
                        withAnimation(.snappy(duration: 0.28)) {
                            panel = value.translation.height < -40 ? .expanded
                                : value.translation.height > 40 ? .peek
                                : panel
                            dragOffset = 0
                        }
                    }
            )
            .onTapGesture {
                withAnimation(.snappy(duration: 0.28)) { panel = panel == .peek ? .expanded : .peek }
            }
            .accessibilityLabel(panel == .peek ? "Expand panel" : "Collapse panel")
    }

    // MARK: Actions

    private func show(building: Building) {
        model.clearRoute()
        state = .building(building.id)
        panel = .expanded
        withAnimation {
            camera = .region(MKCoordinateRegion(center: building.center, latitudinalMeters: 300, longitudinalMeters: 300))
        }
    }

    private func select(_ place: Place) {
        model.clearRoute()
        state = .place(place.id)
        panel = .peek
        if let c = model.pack.coordinate(of: place) {
            withAnimation {
                camera = .region(MKCoordinateRegion(center: c.clCoordinate, latitudinalMeters: 260, longitudinalMeters: 260))
            }
        }
    }

    private func dismissDetail() {
        model.clearRoute()
        withAnimation { state = .search }
        panel = .peek
    }

    private func region(fitting coordinates: [Coordinate]) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else { return Self.campus }
        let lats = coordinates.map(\.lat), lngs = coordinates.map(\.lng)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLng = lngs.min()!, maxLng = lngs.max()!
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 2.4, 0.003),
                longitudeDelta: max((maxLng - minLng) * 2.4, 0.003)
            )
        )
    }
}

/// A category pin. Study rooms carry a free/busy dot, because that is the
/// only thing you want to know at a glance.
struct PlacePin: View {
    let layer: PlaceLayer
    var isSelected: Bool = false
    var isFree: Bool?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.beelineNavy : .white)
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                Image(systemName: layer.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : Color.beelineNavy)
            }
            .frame(width: 28, height: 28)
            .overlay(alignment: .topTrailing) {
                if let isFree {
                    Circle()
                        .fill(isFree ? Color.beelineWalk : Color.secondary)
                        .stroke(.white, lineWidth: 1.5)
                        .frame(width: 10, height: 10)
                        .offset(x: 2, y: -2)
                }
            }
            Triangle()
                .fill(isSelected ? Color.beelineNavy : .white)
                .frame(width: 9, height: 6)
                .offset(y: -1)
        }
        .accessibilityLabel(layer.title)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct DestinationPin: View {
    var body: some View {
        Image(systemName: "mappin.circle.fill")
            .font(.title)
            .foregroundStyle(.white, Color.beelineNavy)
            .shadow(radius: 2, y: 1)
    }
}

extension Coordinate {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

extension Building {
    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

struct MapScreen_Previews: PreviewProvider {
    static var previews: some View {
        MapScreen()
            .environment(AppModel.preview())
            .environment(LocationProvider())
    }
}
