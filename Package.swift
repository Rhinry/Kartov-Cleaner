// swift-tools-version:5.9
// Kartov Cleaner — open this file in Xcode (File > Open… > Package.swift) and press Run.
import PackageDescription

let package = Package(
    name: "KartovCleaner",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "KartovCleaner", targets: ["KartovCleaner"]),
        .library(name: "KartovCore", targets: ["KartovCore"])
    ],
    targets: [
        // Platform-independent engine: rules, safety checks, scanning, cleaning, undo, history.
        .target(
            name: "KartovCore",
            resources: [.process("Resources/rules.json"), .process("Resources/strings.json")]
        ),
        // SwiftUI macOS app.
        .executableTarget(
            name: "KartovCleaner",
            dependencies: ["KartovCore"]
        ),
        .testTarget(
            name: "KartovCoreTests",
            dependencies: ["KartovCore"]
        )
    ]
)
