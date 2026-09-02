// swift-tools-version: 6.3

import PackageDescription

let withMultiProcessTrait = "with_multi_process"

let package = Package(
    name: "SwiftGodotAndroid",
    products: [
        .library(
            name: "SwiftGodot",
            type: .dynamic,
            targets: ["SwiftGodot"]
        ),
        .library(
            name: "SwiftGodotEmbed",
            type: .dynamic,
            targets: ["SwiftGodotEmbed"]
        ),
    ],
    traits: [
        .trait(
            name: withMultiProcessTrait,
            description: "Use multi-process-safe code generation with reinitialization support."
        ),
    ],
    targets: [
        .target(
            name: "GDExtensionC",
            path: "Sources/GDExtension"
        ),
        .target(
            name: "SwiftGodot",
            dependencies: ["GDExtensionC"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .define("CUSTOM_BUILTIN_IMPLEMENTATIONS"),
                .define("SWIFTGODOT_WITH_MULTI_PROCESS", .when(traits: [withMultiProcessTrait])),
                .unsafeFlags([
                    "-enable-library-evolution",
                    "-suppress-warnings",
                    "-Xfrontend", "-conditional-runtime-records",
                ]),
            ]
        ),
        .target(
            name: "SwiftGodotEmbed",
            publicHeadersPath: "include"
        ),
    ]
)
