// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MetagrafCore",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "MetagrafCore", targets: ["MetagrafCore"]),
    ],
    dependencies: [
        // WhisperKit now ships from Argmax's combined repository; the product
        // name is unchanged.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "MetagrafCore",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ]
        ),
        .testTarget(name: "MetagrafCoreTests", dependencies: ["MetagrafCore"]),
    ]
)
