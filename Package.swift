// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "hyprmac",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: config parsing, layout math, action model. No AppKit/AX.
        .target(
            name: "HyprmacCore",
            path: "Sources/HyprmacCore"
        ),
        // The menu-bar app: AX services, hotkeys, window/workspace managers.
        .executableTarget(
            name: "hyprmac",
            dependencies: ["HyprmacCore"],
            path: "Sources/hyprmac"
        ),
        .testTarget(
            name: "HyprmacCoreTests",
            dependencies: ["HyprmacCore"],
            path: "Tests/HyprmacCoreTests"
        ),
    ]
)
