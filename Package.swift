// swift-tools-version: 6.0
import PackageDescription

// Same shape as Cadence: all logic in a UI-free core that builds and tests on
// a Mac, all views in a second package, and a ten-line app target on top.
// The campus data pack ships inside the core as a resource, so the app works
// with no network at all.
let package = Package(
    name: "BeelineKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BeelineCore", targets: ["BeelineCore"]),
        .library(name: "BeelineUI", targets: ["BeelineUI"]),
    ],
    targets: [
        .target(name: "BeelineCore", resources: [.copy("Resources/campus.json")]),
        .target(name: "BeelineUI", dependencies: ["BeelineCore"]),
        .testTarget(name: "BeelineCoreTests", dependencies: ["BeelineCore"]),
    ],
    swiftLanguageModes: [.v6]
)
