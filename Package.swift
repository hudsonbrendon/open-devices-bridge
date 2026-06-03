// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HABatteryBridge",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/emqx/CocoaMQTT", from: "2.1.0"),
    ],
    targets: [
        .target(
            name: "HABatteryCore",
            dependencies: [
                .product(name: "CocoaMQTT", package: "CocoaMQTT"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "HABatteryBridge",
            dependencies: ["HABatteryCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Assertion-based test runner (XCTest/swift-testing are unavailable
        // without full Xcode; this runs via `swift run CoreTests`).
        .executableTarget(
            name: "CoreTests",
            dependencies: ["HABatteryCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
