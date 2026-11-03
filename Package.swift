// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "darkfield",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DarkfieldCore"),
        .executableTarget(name: "Darkfield", dependencies: ["DarkfieldCore"]),
        .testTarget(name: "DarkfieldCoreTests", dependencies: ["DarkfieldCore"]),
    ],
    swiftLanguageModes: [.v5]
)
