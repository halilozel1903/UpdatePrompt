// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UpdatePrompt",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "UpdatePrompt", targets: ["UpdatePrompt"]),
    ],
    targets: [
        .target(name: "UpdatePrompt"),
        .testTarget(
            name: "UpdatePromptTests",
            dependencies: ["UpdatePrompt"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
