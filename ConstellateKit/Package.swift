// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ConstellateKit",
    platforms: [
        .visionOS(.v2),
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "ConstellateKit", targets: ["ConstellateKit"])
    ],
    targets: [
        .target(
            name: "ConstellateKit",
            swiftSettings: [
                .enableUpcomingFeature("MemberImportVisibility")
            ]
        ),
        .testTarget(
            name: "ConstellateKitTests",
            dependencies: ["ConstellateKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
