// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "T3IsleCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "T3IsleCore", targets: ["T3IsleCore"]),
    ],
    targets: [
        .target(name: "T3IsleCore", resources: [.copy("Scenarios")]),
        .testTarget(
            name: "T3IsleCoreTests",
            dependencies: ["T3IsleCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
