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
        .library(name: "MMAudio", targets: ["MMAudio"]),
        .library(name: "MMConversation", targets: ["MMConversation"]),
        .executable(name: "mm-probe", targets: ["MMProbeCLI"]),
    ],
    targets: [
        .target(name: "MMCore"),
        .target(name: "MMDiagnostics", dependencies: ["MMCore"]),
        .target(name: "MMSecurity"),
        .target(name: "MMPerception", dependencies: ["MMCore"]),
        .target(name: "MMEmotion", dependencies: ["MMCore", "MMPerception"], resources: [.process("Resources")]),
        .target(name: "MMAvatar", dependencies: ["MMCore", "MMEmotion"]),
        .target(name: "MMAudio", dependencies: ["MMCore"]),
        .target(
            name: "MMConversation",
            dependencies: ["MMCore", "MMAudio", "MMSecurity"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "MMProbeCLI",
            dependencies: ["MMConversation", "MMAudio", "MMSecurity"]
        ),
        .testTarget(name: "MMCoreTests", dependencies: ["MMCore"]),
        .testTarget(name: "MMDiagnosticsTests", dependencies: ["MMDiagnostics"]),
        .testTarget(name: "MMSecurityTests", dependencies: ["MMSecurity"]),
        .testTarget(name: "MMPerceptionTests", dependencies: ["MMPerception", "MMCore"]),
        .testTarget(name: "MMEmotionTests", dependencies: ["MMEmotion", "MMAvatar", "MMCore", "MMPerception"]),
        .testTarget(name: "MMAudioTests", dependencies: ["MMAudio", "MMCore"]),
        .testTarget(
            name: "MMConversationTests",
            dependencies: ["MMConversation", "MMAudio", "MMCore", "MMSecurity"]
        ),
    ]
)
