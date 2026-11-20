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
    ],
    targets: [
        .target(name: "MMCore"),
        .target(name: "MMDiagnostics", dependencies: ["MMCore"]),
        .target(name: "MMSecurity"),
        .testTarget(name: "MMCoreTests", dependencies: ["MMCore"]),
        .testTarget(name: "MMDiagnosticsTests", dependencies: ["MMDiagnostics"]),
        .testTarget(name: "MMSecurityTests", dependencies: ["MMSecurity"]),
    ]
)
