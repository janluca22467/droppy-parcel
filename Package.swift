// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PaketTracking",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PaketTracking", type: .dynamic, targets: ["PaketTracking"])
    ],
    dependencies: [
        .package(url: "https://gitlab.com/droppyformac1/droppykit.git", from: "1.6.0")
    ],
    targets: [
        .target(
            name: "PaketTracking",
            dependencies: [.product(name: "DroppyKit", package: "droppykit")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "PaketTrackingHarness",
            dependencies: [
                "PaketTracking",
                .product(name: "DroppyKitHarness", package: "droppykit")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
