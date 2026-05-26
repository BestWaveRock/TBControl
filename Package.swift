// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TBControl",
    platforms: [.macOS(.v11)],
    targets: [
        .executableTarget(
            name: "tbcontrold",
            dependencies: [],
            path: "Sources/tbcontrold"
        ),
        .executableTarget(
            name: "TBControl",
            dependencies: [],
            path: "Sources/TBControl",
            linkerSettings: [.linkedFramework("AppKit")]
        ),
    ]
)
