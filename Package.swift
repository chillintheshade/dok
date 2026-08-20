// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "dok",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "dok",
            path: "Sources/dok",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
