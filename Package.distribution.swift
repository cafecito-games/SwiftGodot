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
            name: "SwiftGodot",
            type: .dynamic,
            targets: ["SwiftGodot"]
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
            name: "GDExtensionC",
            path: "Sources/GDExtension",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // The full SwiftGodot API in one module. The release build stages
        // CodeGeneratorPlugin output into Sources/SwiftGodot/_generated/
        // inside this temporary package.
        .target(
            name: "SwiftGodot",
            dependencies: ["GDExtensionC"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
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
            ]
        ),
    ]
)
