// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Torpet",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Torpet", path: "Sources/Torpet"),
    ],
    swiftLanguageModes: [.v5]
)
