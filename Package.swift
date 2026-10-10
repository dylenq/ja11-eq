// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JA11",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "JA11Kit", targets: ["JA11Kit"]),
        .executable(name: "ja11-probe", targets: ["ja11-probe"]),
        .executable(name: "ja11-eq", targets: ["ja11-eq"]),
        .executable(name: "JA11EQ", targets: ["JA11EQ"]),
    ],
    targets: [
        .target(name: "JA11Kit"),
        .executableTarget(name: "ja11-probe", dependencies: ["JA11Kit"]),
        .executableTarget(name: "ja11-eq", dependencies: ["JA11Kit"]),
        .target(name: "JA11EQCore", dependencies: ["JA11Kit"]),
        .executableTarget(name: "JA11EQ", dependencies: ["JA11EQCore", "JA11Kit"]),
        .testTarget(name: "JA11KitTests", dependencies: ["JA11Kit", "JA11EQCore"]),
    ]
)
