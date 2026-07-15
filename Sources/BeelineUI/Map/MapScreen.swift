import MapKit
import SwiftUI
import BeelineCore

/// Map with a persistent bottom sheet — search when idle, the route when one
/// is active. The map is the whole screen; the sheet never covers all of it.
struct MapScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationProvider.self) private var location

    @State private var camera: MapCameraPosition = .region(Self.campus)
    @State private var detent: PresentationDetent = .height(150)
    @State private var selection: String?
    @State private var showingSheet = true

    /// Campus fits in about 1.6 km.
    static let campus = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 33.7756, longitude: -84.3963),
        latitudinalMeters: 1700,
        longitudinalMeters: 1700
    )

    var body: some View {
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
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showingSheet) {
            sheetContent
                .presentationDetents([.height(150), .medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
        }
        .onChange(of: model.activeRoute?.title) {
            if let active = model.activeRoute {
                withAnimation { camera = .region(region(fitting: active.route.coordinates)) }
                detent = .height(150)
            }
        }
    }

    @ViewBuilder
    private var sheetContent: some View {
        if let active = model.activeRoute {
            RouteSheet(active: active, detent: $detent)
        } else {
            SearchSheet(detent: $detent, camera: $camera, selection: $selection)
        }
    }

    private func region(fitting coordinates: [Coordinate]) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else { return Self.campus }
        let lats = coordinates.map(\.lat), lngs = coordinates.map(\.lng)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLng = lngs.min()!, maxLng = lngs.max()!
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 2.2, 0.003),
                longitudeDelta: max((maxLng - minLng) * 2.2, 0.003)
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
