# SwiftGodot (Cafecito Games Fork)

This is a hard fork of [migueldeicaza/SwiftGodot](https://github.com/migueldeicaza/SwiftGodot), maintained by [Cafecito Games](https://github.com/cafecito-games).

**Scope of this fork:**
- Apple platforms only: **iOS and macOS**
- Targets the **latest stable Godot release**
- Requires **Swift 6** (swift-tools-version 6.3, strict concurrency)

If you need cross-platform support, older Godot versions, or community-driven development, use the upstream project.

---

SwiftGodot provides Swift language bindings for the Godot 4 game engine using the [GDExtension](https://docs.godotengine.org/en/stable/tutorials/scripting/gdextension/what_is_gdextension.html) system.

## Consuming this Package

**Source build** — reference the package directly from SwiftPM:

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "MyFirstGame",
    products: [
        .library(name: "MyFirstGame", type: .dynamic, targets: ["MyFirstGame"]),
    ],
    dependencies: [
        .package(url: "https://github.com/cafecito-games/SwiftGodot", branch: "main")
    ],
    targets: [
        .target(
            name: "MyFirstGame",
            dependencies: ["SwiftGodot"]
        )
    ]
)
```

**Binary (xcframework + prebuilt macro plugin)** — faster iteration, no source compilation, no `swift-syntax` dependency. Published at [cafecito-games/SwiftGodotBinary](https://github.com/cafecito-games/SwiftGodotBinary):

```swift
dependencies: [
    .package(url: "https://github.com/cafecito-games/SwiftGodotBinary", from: "0.0.0")
],
targets: [
    .target(
        name: "MyFirstGame",
        dependencies: [
            .product(name: "SwiftGodot", package: "SwiftGodotBinary"),
        ]
    )
]
```

The `SwiftGodot` product carries the prebuilt runtime *and* the prebuilt macro compiler plugin, so `@Godot`, `@Callable`, `@Export`, `#initSwiftExtension`, etc. work without depending on `swift-syntax` or building macros from source. The plugin is shipped as a universal macOS (arm64 + x86_64) artifact bundle; if you're on a Swift toolchain that's incompatible with the prebuilt plugin, use the source build above instead.

## Using SwiftGodot as a Godot addon

Godot projects that use Swift-based addons can install the shared SwiftGodot binary addon with gpm:

```toml
[addons.SwiftGodot]
source      = "github-release"
repo        = "cafecito-games/SwiftGodot"
version     = "v<X.Y.Z>"
asset       = "SwiftGodot-v<X.Y.Z>.zip"
source_path = "addons/SwiftGodot"
```

This addon ships ONLY the SwiftGodot binaries and a plugin.cfg. It does not register a GDExtension. Other GDExtensions that link against SwiftGodot (e.g. cafecito-games/AuthenticationKit, cafecito-games/PurchaseKit) reference these binaries via their own `.gdextension`'s `[dependencies]` block at the path `res://addons/SwiftGodot/bin/<platform>/SwiftGodot.{xcframework,framework}`. AuthenticationKit and PurchaseKit no longer bundle SwiftGodot themselves; this addon must be installed alongside them.

## Targets

| Target | Description |
|--------|-------------|
| `SwiftGodot` | Full Godot API bindings |

## Creating a GDExtension

### Entry point

The simplest approach uses the `#initSwiftExtension` macro:

```swift
import SwiftGodot

#initSwiftExtension(cdecl: "swift_entry_point", types: [SpinningCube.self])

@Godot(.tool)
class SpinningCube: Node3D {
    public override func _ready() {
        let meshRender = MeshInstance3D()
        meshRender.mesh = BoxMesh()
        addChild(node: meshRender)
    }

    public override func _process(delta: Double) {
        rotateY(angle: delta)
    }
}
```

Alternatively, `EntryPointGeneratorPlugin` scans your target's source files and generates the entry point automatically. Add it to your target in `Package.swift`:

```swift
.target(
    name: "MyFirstGame",
    dependencies: ["SwiftGodot"],
    plugins: [
        .plugin(name: "EntryPointGeneratorPlugin", package: "SwiftGodot")
    ]
)
```

### `.gdextension` file

```ini
[configuration]
entry_symbol = "swift_entry_point"
compatibility_minimum = 4.2

[libraries]
macos.debug = "res://bin/MyFirstGame"
macos.release = "res://bin/MyFirstGame"
ios.debug = "res://bin/MyFirstGame"
ios.release = "res://bin/MyFirstGame"
```

Copy the `.gdextension` file and its referenced binaries into your Godot project. Godot will load the extension automatically on startup.

## Working with this Repository

Clone and open in Xcode via `Package.swift`. If you only need to work on the binding generator, open the `Generator` project and edit the `okList` variable to reduce build times.

## License

MIT — see [LICENSE](LICENSE).

Upstream project: [migueldeicaza/SwiftGodot](https://github.com/migueldeicaza/SwiftGodot)
