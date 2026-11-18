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
        .target(name: "DarkfieldImaging"),
        .executableTarget(name: "Darkfield", dependencies: ["DarkfieldCore", "DarkfieldImaging", .product(name: "Sparkle", package: "Sparkle")]),
        // The camera system extension; `just bundle` wraps it into darkfield.app.
        .executableTarget(name: "DarkfieldCameraExtension", dependencies: ["DarkfieldCore"]),
        .testTarget(name: "DarkfieldCoreTests", dependencies: ["DarkfieldCore"]),
        .testTarget(name: "DarkfieldImagingTests", dependencies: ["DarkfieldImaging"]),
    ],
    swiftLanguageModes: [.v5]
)
