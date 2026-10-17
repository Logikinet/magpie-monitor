// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MagpieKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "MagpieKit", targets: ["MagpieKit"])
    ],
    targets: [
        .target(name: "MagpieKit", resources: [.copy("MockData")]),
        .testTarget(name: "MagpieKitTests", dependencies: ["MagpieKit"], resources: [.copy("Fixtures")])
    ]
)
