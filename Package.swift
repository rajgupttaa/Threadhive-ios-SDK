// swift-tools-version: 5.9
import PackageDescription

// ThreadHive iOS SDK — native in-app messaging for the ThreadHive support bot
// + human agents, at parity with the web widget.
//
// macOS is declared as a supported platform purely so the networking/model
// layer can be exercised with `swift test` on a Mac (CI + local). The chat UI
// (SwiftUI/UIKit) is gated with `#if canImport(UIKit)` and only ships on iOS.
let package = Package(
    name: "ThreadHive",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "ThreadHive", targets: ["ThreadHive"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ThreadHive",
            dependencies: [],
            path: "Sources/ThreadHive"
        ),
        .testTarget(
            name: "ThreadHiveTests",
            dependencies: ["ThreadHive"],
            path: "Tests/ThreadHiveTests"
        ),
        // No-Xcode smoke runner: `swift run ThreadHiveSmoke`. Exercises the
        // model/networking/storage layer without XCTest, so the SDK can be
        // verified on a box that only has the Swift command-line toolchain
        // (CI without a full Xcode). The canonical suite is ThreadHiveTests.
        .executableTarget(
            name: "ThreadHiveSmoke",
            dependencies: ["ThreadHive"],
            path: "Smoke"
        ),
    ]
)
