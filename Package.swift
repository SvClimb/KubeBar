// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KubeBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "KubeBar",
            path: "Sources/KubeBar"
        )
    ]
)
