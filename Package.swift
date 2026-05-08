// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RightClickKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "RightClickKitCore", targets: ["RightClickKitCore"]),
        .executable(name: "rck", targets: ["rck"]),
        .executable(name: "RightClickKitApp", targets: ["RightClickKitApp"])
    ],
    targets: [
        .target(name: "RightClickKitCore"),
        .executableTarget(name: "rck", dependencies: ["RightClickKitCore"]),
        .executableTarget(
            name: "RightClickKitApp",
            dependencies: ["RightClickKitCore"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/RightClickKitApp/Info.plist"
                ])
            ]
        )
    ]
)
