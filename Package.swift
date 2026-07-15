// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BeelineKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BeelineCore", targets: ["BeelineCore"]),
        .library(name: "BeelineUI", targets: ["BeelineUI"]),
    ],
    targets: [
        .target(
            name: "BeelineCore",
            resources: [.copy("Resources/campus.json"), .copy("Resources/floorplans")]
        ),
        .target(name: "BeelineUI", dependencies: ["BeelineCore"]),
        .testTarget(name: "BeelineCoreTests", dependencies: ["BeelineCore"]),
    ],
    swiftLanguageModes: [.v6]
)
