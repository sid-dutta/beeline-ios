import SwiftUI
import BeelineUI

/// The app target is deliberately tiny: all views live in the `BeelineUI`
/// package and all logic in `BeelineCore`, so both build and test without a
/// simulator.
@main
struct BeelineApp: App {
    var body: some Scene {
        WindowGroup {
            BeelineRootView()
        }
    }
}
