// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "mdv",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
    ],
    targets: [
        .executableTarget(
            name: "mdv",
            dependencies: [
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MarkdownViewerTests",
            dependencies: ["mdv"]
        )
    ]
)
