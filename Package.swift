// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "IslandEffect",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "IslandEffect",
            path: "Sources/IslandEffect",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
