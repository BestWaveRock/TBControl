// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TBControl",
    platforms: [.macOS(.v11)],
    targets: [
        .target(
            name: "Csmc",
            path: "Sources/Csmc",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "tbcontrold",
            dependencies: ["Csmc"],
            path: "Sources/tbcontrold",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "TBControl",
            dependencies: [],
            path: "Sources/TBControl",
            linkerSettings: [.linkedFramework("AppKit")]
        ),
    ]
)
