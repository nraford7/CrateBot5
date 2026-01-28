// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CrateBotModelLab",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "CrateBotModelLab",
            targets: ["CrateBotModelLab"]
        )
    ],
    dependencies: [
        .package(path: "../CrateBotCore")
    ],
    targets: [
        .executableTarget(
            name: "CrateBotModelLab",
            dependencies: ["CrateBotCore"],
            path: ".",
            exclude: [
                "Package.swift",
                "App/ModelLab.entitlements",
                "Resources",
                "ViewModels",
                "Experimentation"
            ],
            sources: ["App", "Views"]
        )
    ]
)
