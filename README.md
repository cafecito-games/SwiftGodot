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

**Binary (xcframework)** — faster iteration, no source compilation. Published at [cafecito-games/SwiftGodotBinary](https://github.com/cafecito-games/SwiftGodotBinary):

```swift
dependencies: [
    .package(url: "https://github.com/cafecito-games/SwiftGodotBinary", from: "0.0.0")
],
targets: [
    .target(
        name: "MyFirstGame",
        dependencies: [
            .product(name: "SwiftGodot", package: "SwiftGodotBinary"),
            .product(name: "SwiftGodotMacros", package: "SwiftGodotBinary"),
        ]
    )
]
```

## Targets

| Target | Description |
|--------|-------------|
| `SwiftGodot` | Full Godot API bindings |
| `SwiftGodotRuntime` | Minimal runtime — core variant types, `Object`, `ClassDB`, `RefCounted` only |

Use `SwiftGodotRuntime` when you want a smaller binary and don't need the full API surface.

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
