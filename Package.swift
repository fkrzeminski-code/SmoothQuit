// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SmoothQuit", defaultLocalization: "en", platforms: [.macOS(.v14)], products: [
    .executable(name: "SmoothQuit", targets: ["SmoothQuit"])
], targets: [
    .target(name: "SmoothQuitCore"),
    .executableTarget(name: "SmoothQuit", dependencies: ["SmoothQuitCore"], resources: [.process("Resources")]),
    .testTarget(name: "SmoothQuitCoreTests", dependencies: ["SmoothQuitCore", "SmoothQuit"])
])
