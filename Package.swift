// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Mindshare",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MemoryCore"),
        .executableTarget(name: "CoreCheck", dependencies: ["MemoryCore"]),
        .executableTarget(name: "Mindshare", dependencies: ["MemoryCore"]),
    ]
)
