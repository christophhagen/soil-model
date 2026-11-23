// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "soil-model",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
    ],
    products: [
        .library(
            name: "SoilModel",
            targets: ["SoilModel"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/DLR-RB/soil-core-swift.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "SoilModel",
            dependencies: [
                .product(name: "Soil", package: "soil-core-swift"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ],
        ),
        .testTarget(
            name: "SoilModelTests",
            dependencies: [
                "SoilModel",
                .product(name: "Soil", package: "soil-core-swift"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ],
        ),
    ]
)
