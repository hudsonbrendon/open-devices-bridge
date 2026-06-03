// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ble-battery",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ble-battery",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
