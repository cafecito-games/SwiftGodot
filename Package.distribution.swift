// swift-tools-version: 6.3

import PackageDescription

let withMultiProcessTrait = "with_multi_process"

let package = Package(
    name: "SwiftGodot",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "SwiftGodotRuntime",
            type: .dynamic,
            targets: ["SwiftGodotRuntime"]
        ),
        .library(
            name: "SwiftGodot",
            type: .dynamic,
            targets: ["SwiftGodot"]
        ),
        .library(
            name: "SwiftGodotRuntimeStatic",
            targets: ["SwiftGodotRuntime"]
        ),
        .library(
            name: "SwiftGodotStatic",
            targets: ["SwiftGodot"]
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
            name: "GDExtension",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // Sources/SwiftGodotRuntime/_generated/ must be populated by running a
        // normal build first (CodeGeneratorPlugin output) before using this manifest.
        .target(
            name: "SwiftGodotRuntime",
            dependencies: ["GDExtension"],
            swiftSettings: [
                .define("CUSTOM_BUILTIN_IMPLEMENTATIONS"),
                .define("SWIFTGODOT_WITH_MULTI_PROCESS", .when(traits: [withMultiProcessTrait])),
                .unsafeFlags(
                    [
                        "-enable-library-evolution",
                        "-suppress-warnings",
                        "-Xfrontend", "-conditional-runtime-records",
                        "-Xfrontend", "-internalize-at-link",
                        "-Xfrontend", "-lto=llvm-full",
                    ]
                ),
                .swiftLanguageMode(.v5),
            ]
        ),

        // Sources/SwiftGodot/_generated/ must be populated by running a
        // normal build first (CodeGeneratorPlugin output) before using this manifest.
        .target(
            name: "SwiftGodot",
            dependencies: ["GDExtension", "SwiftGodotRuntime"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .define("CUSTOM_BUILTIN_IMPLEMENTATIONS"),
                .define("SWIFTGODOT_WITH_MULTI_PROCESS", .when(traits: [withMultiProcessTrait])),
                .unsafeFlags(["-enable-library-evolution", "-suppress-warnings"]),
            ]
        ),
    ]
)
