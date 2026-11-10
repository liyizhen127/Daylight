// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DaylightGoals",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DaylightGoals", targets: ["DaylightGoals"])],
    targets: [
        .target(name: "DaylightCore"),
        .executableTarget(name: "DaylightGoals", dependencies: ["DaylightCore"]),
        .testTarget(name: "DaylightCoreTests", dependencies: ["DaylightCore"]),
        .testTarget(name: "DaylightGoalsTests", dependencies: ["DaylightGoals", "DaylightCore"])
    ],
    swiftLanguageModes: [.v5]
)
