// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SSHKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "SSHKit", targets: ["SSHKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/orlandos-nl/Citadel", from: "0.9.0"),
        .package(path: "../MagpieKit")
    ],
    targets: [
        .target(
            name: "SSHKit",
            dependencies: [
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "MagpieKit", package: "MagpieKit")
            ]
        )
    ]
)
