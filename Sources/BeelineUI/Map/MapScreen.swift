import MapKit
import SwiftUI
import BeelineCore

/// Map with a draggable panel over it — search when idle, the route when one
/// is active. The panel is an overlay rather than a system sheet so it never
/// covers the tab bar; a sheet at any detent would make the other tabs
/// unreachable.
struct MapScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationProvider.self) private var location

    @State private var camera: MapCameraPosition = .region(Self.campus)
    @State private var selection: String?
    @State private var panel: PanelHeight = .peek
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

    /// Campus fits in about 1.6 km.
    static let campus = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 33.7756, longitude: -84.3963),
        latitudinalMeters: 1700,
        longitudinalMeters: 1700
    )

    var body: some View {
        GeometryReader { geo in
            let height = min(
                max(panel.points(in: geo.size.height) - dragOffset, 120),
                geo.size.height - 60
            )
            ZStack(alignment: .bottom) {
                map
                    .ignoresSafeArea(edges: .top)
                panelContent
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: -2)
            }
        }
        .onChange(of: model.activeRoute?.title) {
            if let active = model.activeRoute {
                withAnimation { camera = .region(region(fitting: active.route.coordinates)) }
                panel = .expanded
            }
        }
    }

    // MARK: Map

    private var map: some View {
        Map(position: $camera, selection: $selection) {
            UserAnnotation()

            if let active = model.activeRoute {
                MapPolyline(coordinates: active.route.coordinates.map(\.clCoordinate))
                    .stroke(Color.beelineRoute, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))

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
                    Annotation(active.title, coordinate: end.clCoordinate) {
                        DestinationPin()
                    }
                }
                if let building = active.destination.buildingID.flatMap(model.building) {
                    MapPolygon(coordinates: building.polygon.map(\.clCoordinate))
                        .foregroundStyle(Color.beelineRoute.opacity(0.14))
                        .stroke(Color.beelineRoute.opacity(0.55), lineWidth: 1.5)
                }
            } else if let id = selection, let building = model.building(id) {
                MapPolygon(coordinates: building.polygon.map(\.clCoordinate))
                    .foregroundStyle(Color.beelineGold.opacity(0.2))
                    .stroke(Color.beelineGold, lineWidth: 1.5)
                Annotation(building.shortName, coordinate: building.center) {
                    DestinationPin()
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
    }

    // MARK: Panel

    private var panelContent: some View {
        VStack(spacing: 0) {
            grabber
            if let active = model.activeRoute {
                RouteSheet(active: active, expand: { panel = .expanded })
            } else {
                SearchSheet(expand: { panel = .expanded }, camera: $camera, selection: $selection)
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
                withAnimation(.snappy(duration: 0.28)) {
                    panel = panel == .peek ? .expanded : .peek
                }
            }
            .accessibilityLabel(panel == .peek ? "Expand panel" : "Collapse panel")
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
