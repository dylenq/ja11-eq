// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JA11",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "JA11Kit", targets: ["JA11Kit"]),
        .executable(name: "ja11-probe", targets: ["ja11-probe"]),
    ],
    targets: [
        .target(name: "JA11Kit"),
        .executableTarget(name: "ja11-probe", dependencies: ["JA11Kit"]),
        .testTarget(name: "JA11KitTests", dependencies: ["JA11Kit"]),
    ]
)
