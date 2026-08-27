// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EarlySync",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "EarlySync", targets: ["EarlySync"]),
    ],
    targets: [
        .executableTarget(
            name: "EarlySync",
            path: "Sources/EarlySync",
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
        .testTarget(
            name: "EarlySyncTests",
            dependencies: ["EarlySync"],
            path: "Tests/EarlySyncTests"
        ),
    ]
)
