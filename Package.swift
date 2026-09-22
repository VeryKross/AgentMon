// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AgentMon",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "AgentMon"
        ),
        .testTarget(
            name: "AgentMonTests",
            dependencies: ["AgentMon"]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
