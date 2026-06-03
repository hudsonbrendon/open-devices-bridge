// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "camera-mac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "camera-mac",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
