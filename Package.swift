// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StripTile",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "StripCore"),
        .executableTarget(name: "StripTile", dependencies: ["StripCore"]),
        .executableTarget(name: "StripCheck", dependencies: ["StripCore"]),
    ]
)
