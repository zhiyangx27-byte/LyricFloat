// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LyricFloat",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "LyricFloat", targets: ["LyricFloat"])
    ],
    targets: [
        .executableTarget(
            name: "LyricFloat",
            path: "Sources/LyricFloat",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("ScriptingBridge")
            ]
        ),
        .testTarget(
            name: "LyricFloatTests",
            dependencies: ["LyricFloat"],
            path: "Tests/LyricFloatTests"
        )
    ]
)
