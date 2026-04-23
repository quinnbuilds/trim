// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Trim",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Trim",
            path: "Trim",
            exclude: ["Resources/Trim.entitlements", "Resources/Info.plist"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-strict-concurrency=minimal"])
            ],
            linkerSettings: [
                .linkedFramework("Photos")
            ]
        )
    ]
)
