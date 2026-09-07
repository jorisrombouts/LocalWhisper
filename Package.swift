// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalWhisper",
    platforms: [.macOS("26.0")],
    targets: [
        .binaryTarget(name: "whisper", path: "Frameworks/whisper.xcframework"),
        .executableTarget(
            name: "LocalWhisper",
            dependencies: ["whisper"],
            path: "Sources/LocalWhisper"
        ),
    ]
)
