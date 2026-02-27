// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FanControl",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FanControlCLI", targets: ["FanControlCLI"]),
        .executable(name: "FanControlApp", targets: ["FanControlApp"]),
        .executable(name: "FanControlHelper", targets: ["FanControlHelper"]),
    ],
    targets: [
        .target(
            name: "CSMCTypes",
            path: "Sources/CSMCTypes",
            publicHeadersPath: "include"
        ),
        .target(
            name: "SMCKit",
            dependencies: ["CSMCTypes"],
            path: "Sources/SMCKit"
        ),
        .executableTarget(
            name: "FanControlCLI",
            dependencies: ["SMCKit"],
            path: "Sources/FanControlCLI"
        ),
        .executableTarget(
            name: "FanControlApp",
            dependencies: ["SMCKit"],
            path: "Sources/FanControlApp"
        ),
        .executableTarget(
            name: "FanControlHelper",
            dependencies: ["SMCKit"],
            path: "Sources/FanControlHelper"
        ),
    ]
)
