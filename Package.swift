// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "livewall",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "livewall", path: "Sources/livewall")
    ]
)
