// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CrateBotCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CrateBotCore",
            targets: ["CrateBotCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/chicio/ID3TagEditor.git", from: "4.6.0")
    ],
    targets: [
        .target(
            name: "CrateBotCore",
            dependencies: ["ID3TagEditor"],
            path: "Sources/CrateBotCore",
            resources: [
                .copy("Resources/Discogs_EffNet.mlpackage"),
                .copy("Resources/Jamendo_MoodTheme.mlpackage"),
                .copy("Resources/Jamendo_Instrument.mlpackage"),
                .copy("Resources/CLAPAudioEncoder.mlpackage"),
                .copy("Resources/genre_discogs400-discogs-effnet-1.json"),
                .copy("Resources/mtg_jamendo_moodtheme-discogs-effnet-1.json"),
                .copy("Resources/mtg_jamendo_instrument-discogs-effnet-1.json")
            ]
        ),
        .testTarget(
            name: "CrateBotCoreTests",
            dependencies: ["CrateBotCore"],
            path: "Tests/CrateBotCoreTests",
            resources: [
                .copy("Resources/example.mp3")
            ]
        ),
    ]
)
