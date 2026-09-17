// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "IslandEffect",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "IslandEffect", targets: ["IslandEffect"]),
        // Producto propio para que Xcode le cree un esquema: las previews se
        // compilan con él.
        .library(name: "IslandEffectKit", targets: ["IslandEffectKit"])
    ],
    targets: [
        // Todo el código de la app. Va en una librería porque Xcode no renderiza
        // #Preview dentro de un target ejecutable de SwiftPM.
        .target(
            name: "IslandEffectKit",
            path: "Sources/IslandEffectKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "IslandEffect",
            dependencies: ["IslandEffectKit"],
            path: "Sources/IslandEffect",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
