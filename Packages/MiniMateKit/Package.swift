// swift-tools-version: 6.2
import PackageDescription

// Swift 6 language mode (tools-version 6.x) enables strict concurrency checking by default.
let package = Package(
    name: "MiniMateKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "MMCore", targets: ["MMCore"]),
        .library(name: "MMDiagnostics", targets: ["MMDiagnostics"]),
        .library(name: "MMSecurity", targets: ["MMSecurity"]),
        .library(name: "MMPerception", targets: ["MMPerception"]),
        .library(name: "MMEmotion", targets: ["MMEmotion"]),
        .library(name: "MMAvatar", targets: ["MMAvatar"]),
    ],
    targets: [
        .target(name: "MMCore"),
        .target(name: "MMDiagnostics", dependencies: ["MMCore"]),
        .target(name: "MMSecurity"),
        .target(name: "MMPerception", dependencies: ["MMCore"]),
        .target(name: "MMEmotion", dependencies: ["MMCore", "MMPerception"], resources: [.process("Resources")]),
        .target(name: "MMAvatar", dependencies: ["MMCore", "MMEmotion"]),
        .testTarget(name: "MMCoreTests", dependencies: ["MMCore"]),
        .testTarget(name: "MMDiagnosticsTests", dependencies: ["MMDiagnostics"]),
        .testTarget(name: "MMSecurityTests", dependencies: ["MMSecurity"]),
        .testTarget(name: "MMPerceptionTests", dependencies: ["MMPerception", "MMCore"]),
        .testTarget(name: "MMEmotionTests", dependencies: ["MMEmotion", "MMAvatar", "MMCore", "MMPerception"]),
    ]
)
