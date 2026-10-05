// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tether",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Tether", targets: ["Tether"]),
        .executable(name: "tetherctl", targets: ["TetherCLI"]),
    ],
    targets: [
        .target(
            name: "TetherIPC",
            path: "Sources/TetherIPC"
        ),
        .executableTarget(
            name: "Tether",
            dependencies: ["TetherIPC"],
            path: "Sources/Tether"
        ),
        .executableTarget(
            name: "TetherCLI",
            dependencies: ["TetherIPC"],
            path: "Sources/TetherCLI"
        ),
        .testTarget(
            name: "TetherTests",
            dependencies: ["Tether", "TetherIPC"],
            path: "Tests/TetherTests"
        ),
    ]
)
