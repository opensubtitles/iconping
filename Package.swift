// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "IconPing",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "IconPing", targets: ["IconPingApp"]),
        .library(name: "IconPingCore", targets: ["IconPingCore"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "IconPingApp",
            dependencies: ["IconPingCore"],
            path: "Sources/IconPingApp",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "IconPingCore",
            path: "Sources/IconPingCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "IconPingCoreTests",
            dependencies: ["IconPingCore"],
            path: "Tests/IconPingCoreTests"
        )
    ]
)
