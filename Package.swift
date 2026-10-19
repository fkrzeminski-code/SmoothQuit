// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SmoothQuit", platforms: [.macOS(.v14)], products: [
    .executable(name: "SmoothQuit", targets: ["SmoothQuit"])
], targets: [
    .target(name: "SmoothQuitCore"),
    .executableTarget(name: "SmoothQuit", dependencies: ["SmoothQuitCore"]),
    .testTarget(name: "SmoothQuitCoreTests", dependencies: ["SmoothQuitCore", "SmoothQuit"])
])
