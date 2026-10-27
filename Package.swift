// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClipRecorder",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "ClipRecorder",
            path: "Sources/ClipRecorder",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
