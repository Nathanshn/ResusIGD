// swift-tools-version:6.0
// ClinicalCore — pure, deterministic clinical math + bundled offline seed data.
// No UIKit / SwiftUI / SwiftData imports, so it builds and tests on macOS, Linux and Windows.
import PackageDescription

let package = Package(
    name: "ClinicalCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ClinicalCore", targets: ["ClinicalCore"])
    ],
    targets: [
        .target(
            name: "ClinicalCore",
            resources: [.copy("Resources/SeedData")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ClinicalCoreTests",
            dependencies: ["ClinicalCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
