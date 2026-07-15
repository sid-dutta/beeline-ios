import SwiftUI
import BeelineCore

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationProvider.self) private var location

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
                Toggle("Step-free routes", isOn: $model.accessibleRouting)
            } header: {
                Text("Getting around")
            } footer: {
                Text("Avoids stairs and prefers accessible entrances where they're mapped.")
            }

            Section {
                LabeledContent("Location") {
                    Text(locationStatus)
                        .foregroundStyle(location.isAuthorized ? .secondary : Color.orange)
                }
                if !location.isAuthorized {
                    Button("Allow location access") { location.request() }
                }
            } footer: {
                Text("Without location, routes start from the middle of campus.")
            }

            Section {
                LabeledContent("Term", value: termLabel)
                LabeledContent("Buildings", value: "\(model.pack.buildings.count)")
                LabeledContent("Rooms with classes", value: "\(model.pack.rooms.count)")
                LabeledContent("Walking path nodes", value: "\(model.pack.graph.nodes.count)")
                LabeledContent("Bus routes", value: "\(model.pack.bus.routes.count)")
                LabeledContent("Data built", value: builtAt)
            } header: {
                Text("Campus data")
            } footer: {
                Text("Beeline works fully offline. Buildings and paths come from OpenStreetMap, entrances and places from Georgia Tech's campus map, and class rooms from the schedule of classes.")
            }

            Section("About") {
                LabeledContent("Version", value: "0.1")
                Link(destination: URL(string: "https://github.com/sid-dutta/beeline-ios")!) {
                    Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
        }
        .navigationTitle("Settings")
    }

    private var locationStatus: String {
        switch location.authorization {
        case .authorizedAlways, .authorizedWhenInUse: location.coordinate == nil ? "Waiting for a fix" : "On"
        case .denied, .restricted: "Off — enable in Settings"
        default: "Not enabled"
        }
    }

    private var termLabel: String {
        let term = model.pack.term
        guard term.count == 6, let year = Int(term.prefix(4)) else { return term }
        let season = switch term.suffix(2) {
        case "02": "Spring"
        case "05": "Summer"
        default: "Fall"
        }
        return "\(season) \(year)"
    }

    private var builtAt: String {
        let raw = model.pack.generatedAt
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: raw) else { return raw }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct SettingsScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { SettingsScreen() }
            .environment(AppModel.preview())
            .environment(LocationProvider())
    }
}
