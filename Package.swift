// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cosmosaic",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: config parsing, layout math, action model. No AppKit/AX.
        .target(
            name: "CosmosaicCore",
            path: "Sources/CosmosaicCore"
        ),
        // The menu-bar app: AX services, hotkeys, window/workspace managers.
        .executableTarget(
            name: "Cosmosaic",
            dependencies: ["CosmosaicCore"],
            path: "Sources/Cosmosaic"
        ),
        .testTarget(
            name: "CosmosaicCoreTests",
            dependencies: ["CosmosaicCore"],
            path: "Tests/CosmosaicCoreTests"
        ),
    ]
)
