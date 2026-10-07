// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Keymin",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "KeyminApp",
            path: "Sources/KeyminApp",
            resources: [.process("Resources")],
            swiftSettings: [.define("KEYMIN_SWIFTPM")]
        )
    ],
    // The app is written for the Swift 5 language mode, as in the Xcode project and build script.
    swiftLanguageModes: [.v5]
)
