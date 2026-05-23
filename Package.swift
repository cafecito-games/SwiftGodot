// swift-tools-version: 6.3

import CompilerPluginSupport
import PackageDescription

let withMultiProcessTrait = "with_multi_process"

// Products define the executables and libraries a package produces, and make them visible to other packages.
var products: [Product] = [
    .library(
        name: "SwiftGodot",
        type: .dynamic,
        targets: ["SwiftGodot"]
    ),

    .library(
        name: "SwiftGodotStatic",
        targets: ["SwiftGodot"]
    ),

    .library(
        name: "ExtensionApi",
        targets: [
            "ExtensionApi",
            "ExtensionApiJson",
        ]
    ),

    .plugin(
        name: "CodeGeneratorPlugin",
        targets: ["CodeGeneratorPlugin"]
    ),

    .plugin(
        name: "EntryPointGeneratorPlugin",
        targets: ["EntryPointGeneratorPlugin"]
    ),

    .library(
        name: "SimpleExtension",
        type: .dynamic,
        targets: ["SimpleExtension"]
    ),

    .library(
        name: "ManualExtension",
        type: .dynamic,
        targets: ["ManualExtension"]
    ),

    .library(
        name: "SwiftGodotEmbed",
        type: .dynamic,
        targets: ["SwiftGodotEmbed"]
    ),

    .executable(
        name: "SwiftGodotTestRunner",
        targets: ["SwiftGodotTestRunner"]
    ),

    .library(
        name: "SwiftGodotTestExtension",
        type: .dynamic,
        targets: ["SwiftGodotTestExtension"]
    ),
]

/// Targets are the basic building blocks of a package. A target can define a module, plugin, test suite, etc.
var targets: [Target] = [
    .executableTarget(
        name: "EntryPointGenerator",
        dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ],
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),

    // This contains GDExtension's JSON API data models
    .target(
        name: "ExtensionApi",
        exclude: ["ExtensionApiJson.swift", "extension_api.json"],
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),

    // This contains a resource bundle with extension_api.json
    .target(
        name: "ExtensionApiJson",
        path: "Sources/ExtensionApi",
        exclude: ["ApiJsonModel.swift", "ApiJsonModel+Extra.swift"],
        sources: ["ExtensionApiJson.swift"],
        resources: [.process("extension_api.json")],
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),

    // The generator takes Godot's JSON-based API description as input and
    // produces Swift API bindings that can be used to call into Godot.
    .executableTarget(
        name: "Generator",
        dependencies: [
            "ExtensionApi",
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        ],
        path: "Generator",
        exclude: ["README.md"],
        swiftSettings: [
            .swiftLanguageMode(.v6)
            // Uncomment for using legacy array-based marshalling
            //.define("LEGACY_MARSHALING")
        ]
    ),

    // This is a build-time plugin that invokes the generator and produces
    // the bindings that are compiled into SwiftGodot.
    .plugin(
        name: "CodeGeneratorPlugin",
        capability: .buildTool(),
        dependencies: ["Generator"]
    ),

    // This is a build-time plugin that generates the EntryPoint.swift file,
    // which is used to bootstrap the SwiftGodot API and register your
    // extension and classes with Godot.
    .plugin(
        name: "EntryPointGeneratorPlugin",
        capability: .buildTool(),
        dependencies: ["EntryPointGenerator"]
    ),

    // This allows the Swift code to call into the Godot bridge API (GDExtension)
    .target(
        name: "GDExtensionC",
        path: "Sources/GDExtension",
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),

    // These are macros that can be used by third parties to simplify their
    // SwiftGodot development experience, these are used at compile time by
    // third party projects
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

    // Test macro implementations for @SwiftGodotTest and @SwiftGodotTestSuite
    .macro(
        name: "SwiftGodotTestMacrosLibrary",
        dependencies: [
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        ],
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),

    // Test macro definitions and SwiftGodotTestSuiteProtocol
    .target(
        name: "SwiftGodotTestMacros",
        dependencies: ["SwiftGodot"],
        swiftSettings: [.swiftLanguageMode(.v6)],
        plugins: ["SwiftGodotTestMacrosLibrary"]
    ),
    // This contains sample code showing how to use the SwiftGodot API
    .target(
        name: "SimpleExtension",
        dependencies: ["SwiftGodot"],
        exclude: ["SimpleExtension.gdextension", "README.md"],
        swiftSettings: [.swiftLanguageMode(.v6)],
        plugins: [.plugin(name: "EntryPointGeneratorPlugin")]
    ),

    // This contains sample code showing how to use the SwiftGodot API
    // with manual registration of methods and properties
    .target(
        name: "ManualExtension",
        dependencies: ["SwiftGodot"],
        exclude: ["ManualExtension.gdextension", "README.md"],
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),

    // No-op GDExtension shipped inside the SwiftGodot Godot addon. Its sole
    // purpose is to give Godot's iOS/macOS exporters a registered extension
    // that declares SwiftGodot under `[dependencies]`, so SwiftGodot.framework
    // is embedded into the exported app exactly once. Registers no Godot
    // classes; see SwiftGodotEmbed.swift for the manual entry point.
    .target(
        name: "SwiftGodotEmbed",
        dependencies: ["SwiftGodot"],
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),

    // The full SwiftGodot API: hand-written core + the generated Godot API,
    // all in one module. The release build stages CodeGeneratorPlugin output
    // into Sources/SwiftGodot/_generated/ inside a temporary package.
    .target(
        name: "SwiftGodot",
        dependencies: ["GDExtensionC"],
        exclude: ["_generated"],
        swiftSettings: [
            .swiftLanguageMode(.v6),
            .define("CUSTOM_BUILTIN_IMPLEMENTATIONS"),
            .define("SWIFTGODOT_WITH_MULTI_PROCESS", .when(traits: [withMultiProcessTrait])),
            .unsafeFlags(
                [
                    "-Xfrontend", "-conditional-runtime-records",
                    "-Xfrontend", "-internalize-at-link",
                    "-Xfrontend", "-lto=llvm-full",
                ]
            ),
        ],
        plugins: ["CodeGeneratorPlugin", "SwiftGodotMacroLibrary"]
    ),

    // General purpose cross-platform tests
    .testTarget(
        name: "SwiftGodotUniversalTests",
        dependencies: [
            "SwiftGodot",
            "ExtensionApi",
            "ExtensionApiJson",
        ],
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),

    // Test runner CLI executable
    .executableTarget(
        name: "SwiftGodotTestRunner",
        dependencies: [],
        path: "Sources/SwiftGodotTestRunner",
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),

    // Test extension (loaded by Godot) - includes all test infrastructure and test suites
    .target(
        name: "SwiftGodotTestExtension",
        dependencies: ["SwiftGodot", "SwiftGodotTestMacros"],
        path: "Tests/SwiftGodotTestExtension",
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),
]

// Idea: -mark_dead_strippable_dylib
targets.append(
    .testTarget(
        name: "SwiftGodotMacrosTests",
        dependencies: [
            "SwiftGodotMacroLibrary",
            "SwiftGodot",
            .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
        ],
        exclude: ["Resources"],
        resources: [
            .copy("Resources")
        ],
        swiftSettings: [.swiftLanguageMode(.v6)]
    ))

let package = Package(
    name: "SwiftGodot",
    platforms: [
        .macOS(.v14),
        .iOS (.v17)
    ],
    products: products,
    traits: [
        .trait(
            name: withMultiProcessTrait,
            description: "Use multi-process-safe code generation with reinitialization support."
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.3.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.1"),
    ],
    targets: targets
)
