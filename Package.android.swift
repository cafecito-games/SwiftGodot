// swift-tools-version: 6.3

import CompilerPluginSupport
import PackageDescription

let withMultiProcessTrait = "with_multi_process"

let package = Package(
    name: "SwiftGodotAndroid",
    platforms: [
        .macOS(.v14),
    ],
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
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.1"),
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
                    "-no-verify-emitted-module-interface",
                    "-suppress-warnings",
                    "-Xfrontend", "-conditional-runtime-records",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-soname", "-Xlinker", "libSwiftGodot.so"]),
            ],
            plugins: ["SwiftGodotMacroLibrary"]
        ),
        .target(
            name: "SwiftGodotEmbed",
            publicHeadersPath: "include",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-soname", "-Xlinker", "libSwiftGodotEmbed.so"]),
            ]
        ),
        .macro(
            name: "SwiftGodotMacroLibrary",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftBasicFormat", package: "swift-syntax"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
