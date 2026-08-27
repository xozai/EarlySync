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
    dependencies: [
        // Auto-update mechanism for distribution outside the App Store.
        // Explicit exception to the "no external SPM deps" rule — approved
        // by Jose (issue #8 author) and HermesX; there's no maintained
        // non-SPM alternative for this.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "EarlySync",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/EarlySync",
            linkerSettings: [
                .linkedFramework("IOKit"),
                // Sparkle.framework ships embedded in Contents/Frameworks in
                // the packaged .app (see scripts/package-dmg.sh); the binary
                // needs this rpath to find it there. @loader_path alone
                // (SwiftPM's default) only covers Contents/MacOS.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "EarlySyncTests",
            dependencies: ["EarlySync"],
            path: "Tests/EarlySyncTests"
        ),
    ]
)
