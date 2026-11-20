// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pith",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Pith", targets: ["PithApp"]),
        .library(name: "PithCore", targets: ["PithCore"]),
    ],
    targets: [
        .target(name: "PithCore"),
        .executableTarget(name: "PithApp", dependencies: ["PithCore"]),
        .testTarget(name: "PithCoreTests", dependencies: ["PithCore"]),
        .testTarget(name: "PithAppTests", dependencies: ["PithApp"]),
    ]
)
