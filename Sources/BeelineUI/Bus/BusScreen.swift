import MapKit
import SwiftUI
import BeelineCore

/// What TransLoc doesn't do: routes and live buses on one screen, with the
/// arrival for each stop right there instead of two taps away.
struct BusScreen: View {
    @Environment(AppModel.self) private var model
    @State private var selectedRoute: Int?
    @State private var camera: MapCameraPosition = .region(MapScreen.campus)

    private var routes: [BusRoute] { model.pack.bus.routes }

    var body: some View {
        VStack(spacing: 0) {
            map
                .frame(height: 260)
            routePicker
            Divider()
            stopList
        }
        .navigationTitle("Stinger")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if model.isRefreshingBus {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await model.refreshBus() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .task {
            if selectedRoute == nil { selectedRoute = routes.first(where: { $0.name == "Red" })?.id ?? routes.first?.id }
            model.startBusUpdates()
        }
        .onDisappear { model.stopBusUpdates() }
    }

    // MARK: Map

    private var map: some View {
        Map(position: $camera) {
            ForEach(visibleRoutes) { route in
                MapPolyline(coordinates: route.polyline.map(\.clCoordinate))
                    .stroke(Color(hex: route.color), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            ForEach(visibleRoutes) { route in
                ForEach(route.stops) { stop in
                    Annotation(stop.name, coordinate: CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lng)) {
                        Circle()
                            .fill(Color.markerBody)
                            .stroke(Color(hex: route.color), lineWidth: 3)
                            .frame(width: 9, height: 9)
                    }
                    .annotationTitles(.hidden)
                }
            }
            ForEach(visibleVehicles) { vehicle in
                Annotation(vehicle.name, coordinate: CLLocationCoordinate2D(latitude: vehicle.lat, longitude: vehicle.lng)) {
                    BusMarker(color: Color(hex: model.route(vehicle.routeID)?.color ?? "#888888"), heading: vehicle.heading)
                }
                .annotationTitles(.hidden)
            }
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }

    private var visibleRoutes: [BusRoute] {
        guard let id = selectedRoute, let route = model.route(id) else { return [] }
        return [route]
    }

    private var visibleVehicles: [Vehicle] {
        guard let id = selectedRoute else { return model.vehicles }
        return model.vehicles(onRoute: id)
    }

    // MARK: Route picker

    private var routePicker: some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(routes) { route in
                    Button {
                        selectedRoute = route.id
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: route.color))
                                .frame(width: 9, height: 9)
                            Text(route.name)
                                .font(.subheadline.weight(selectedRoute == route.id ? .semibold : .regular))
                            if !model.vehicles(onRoute: route.id).isEmpty {
                                Text("\(model.vehicles(onRoute: route.id).count)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color(hex: route.color), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            selectedRoute == route.id ? Color.groupedBackground : Color.clear,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                selectedRoute == route.id ? Color(hex: route.color).opacity(0.6) : Color.secondary.opacity(0.2)
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .id(route.id)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        // Keep the selected route visible; it is rarely first alphabetically.
        .onChange(of: selectedRoute) { _, id in
            guard let id else { return }
            withAnimation { proxy.scrollTo(id, anchor: .center) }
        }
        .task {
            if let id = selectedRoute { proxy.scrollTo(id, anchor: .center) }
        }
        }
    }

    // MARK: Stops

    @ViewBuilder
    private var stopList: some View {
        if let id = selectedRoute, let route = model.route(id) {
            List {
                Section {
                    ForEach(route.stops) { stop in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: route.color))
                                .frame(width: 8, height: 8)
                            Text(stop.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if let arrival = model.nextArrival(routeID: route.id, stopID: stop.id) {
                                Text(arrival.label)
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Color(hex: route.color))
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("\(route.stops.count) stops")
                        Spacer()
                        Text(statusText)
                            .textCase(nil)
                    }
                } footer: {
                    if !route.hours.isEmpty {
                        Text(route.hours.joined(separator: "\n"))
                    }
                }
            }
            .groupedList()
        }
    }

    private var statusText: String {
        if let error = model.busError { return error }
        if model.isServiceActive {
            let count = visibleVehicles.count
            return count == 1 ? "1 bus running" : "\(count) buses running"
        }
        if model.busUpdatedAt != nil { return "No buses running" }
        return "Loading…"
    }
}

struct BusMarker: View {
    let color: Color
    let heading: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 22, height: 22)
                .shadow(radius: 2, y: 1)
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 8))
                .foregroundStyle(.white)
                .offset(y: -1)
                .rotationEffect(.degrees(heading))
        }
        .overlay(Circle().strokeBorder(Color.markerBody, lineWidth: 2).frame(width: 22, height: 22))
    }
}

struct BusScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { BusScreen() }
            .environment(AppModel.preview())
    }
}
