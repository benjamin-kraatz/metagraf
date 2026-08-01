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
        .library(name: "MetagrafWhisper", targets: ["MetagrafWhisper"]),
    ],
    dependencies: [
        // WhisperKit now ships from Argmax's combined repository; the product
        // name is unchanged.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", from: "0.9.0"),
    ],
    targets: [
        // Deliberately free of WhisperKit. The iOS keyboard extension links
        // only this target: extensions run under a hard memory limit, and
        // WhisperKit drags in transformers, tokenizers, and crypto that a
        // keyboard would pay for without ever using. Apple's SpeechAnalyzer
        // runs out of process, so the keyboard gets dictation for almost no
        // resident cost.
        .target(name: "MetagrafCore"),

        // Whisper models and everything needed to download and run them.
        // Linked by the full apps only.
        .target(
            name: "MetagrafWhisper",
            dependencies: [
                "MetagrafCore",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ]
        ),

        .testTarget(
            name: "MetagrafCoreTests",
            dependencies: ["MetagrafCore", "MetagrafWhisper"]
        ),
    ]
)
