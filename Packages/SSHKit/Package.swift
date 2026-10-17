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
        .package(url: "https://github.com/orlandos-nl/Citadel", .upToNextMinor(from: "0.12.1")),
        .package(path: "../MagpieKit"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/Wellz26/swift-nio-ssh.git", "0.3.4" ..< "0.4.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.12.3")
    ],
    targets: [
        .target(
            name: "SSHKit",
            dependencies: [
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "MagpieKit", package: "MagpieKit"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .testTarget(name: "SSHKitTests", dependencies: [
            "SSHKit",
            .product(name: "MagpieKit", package: "MagpieKit"),
            .product(name: "NIOEmbedded", package: "swift-nio"),
            .product(name: "NIOSSH", package: "swift-nio-ssh")
        ])
    ]
)
