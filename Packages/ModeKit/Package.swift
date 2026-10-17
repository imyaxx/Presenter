// swift-tools-version: 6.0
// 6.0 is the lowest tools version with the Swift 6 language mode; see ADR-024 in docs/09-decisions.md.

import PackageDescription

let package = Package(
    name: "ModeKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ModeKit", targets: ["ModeKit"])
    ],
    targets: [
        .target(
            name: "ModeKit",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
        ),
        .testTarget(
            name: "ModeKitTests",
            dependencies: ["ModeKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
        ),
    ],
)
