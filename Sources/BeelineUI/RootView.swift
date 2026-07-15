import SwiftUI
import BeelineCore

public enum Tab: Hashable {
    case map, classes, bus, settings
}

public struct BeelineRootView: View {
    @State private var model: AppModel
    @State private var location = LocationProvider()
    @State private var tab: Tab = .map

    public init(model: AppModel = .live()) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        TabView(selection: $tab) {
            MapScreen()
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(Tab.map)

            NavigationStack {
                ClassesScreen(tab: $tab)
            }
            .tabItem { Label("Classes", systemImage: "calendar") }
            .tag(Tab.classes)

            NavigationStack {
                BusScreen()
            }
            .tabItem { Label("Bus", systemImage: "bus.fill") }
            .tag(Tab.bus)

            NavigationStack {
                SettingsScreen()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(Tab.settings)
        }
        .tint(.beelineNavy)
        .environment(model)
        .environment(location)
        .task {
            location.request()
            await model.refreshBus()
        }
        .onChange(of: location.coordinate?.latitude) {
            model.origin = location.coordinate
        }
        .overlay(alignment: .top) {
            if let error = model.loadError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
    }
}

struct BeelineRootView_Previews: PreviewProvider {
    static var previews: some View {
        BeelineRootView(model: .preview())
    }
}
