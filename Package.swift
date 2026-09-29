// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexIsland",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CodexIsland", targets: ["CodexIsland"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "IslandCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "CodexIsland", dependencies: ["IslandCore"]),
        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"]),
        .testTarget(name: "IslandLayoutTests", dependencies: ["CodexIsland"])
    ]
)
