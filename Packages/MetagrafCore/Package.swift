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
    targets: [
        .target(name: "MetagrafCore"),
        .testTarget(name: "MetagrafCoreTests", dependencies: ["MetagrafCore"]),
    ]
)
