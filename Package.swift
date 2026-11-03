// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "darkfield",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "DarkfieldCore"),
        .executableTarget(name: "Darkfield", dependencies: ["DarkfieldCore", .product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "DarkfieldCoreTests", dependencies: ["DarkfieldCore"]),
    ],
    swiftLanguageModes: [.v5]
)
