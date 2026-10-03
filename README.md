# SwiftGodot (Cafecito Games Fork)

This is a hard fork of [migueldeicaza/SwiftGodot](https://github.com/migueldeicaza/SwiftGodot), maintained by [Cafecito Games](https://github.com/cafecito-games).

**Scope of this fork:**
- Runtime and packaged-release support for **Android, iOS, and macOS**
- Source-build support for **Linux** (x86_64 is exercised in CI)
- Targets Cafecito's **Godot 4.7.2** build
- Requires a **Swift 6.3** toolchain; CI and Android releases use Swift 6.3.3

Linux support currently covers building from source, unit tests, and loading a Swift GDExtension in the Godot editor. Prebuilt Linux artifacts, Swift runtime bundling, and exported-game packaging are not provided yet. If you need Windows, older Godot versions, or community-driven development, use the upstream project.

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

The `SwiftGodot` product carries the prebuilt runtime *and* the prebuilt macro compiler plugin, so `@Godot`, `@Callable`, `@Export`, `#initSwiftExtension`, etc. work without depending on `swift-syntax` or building macros from source. The plugin is shipped as a universal macOS (arm64 + x86_64) artifact bundle; Linux consumers must use the source build above.

## Using SwiftGodot as a Godot addon

Godot projects that use Swift-based addons can install the shared SwiftGodot binary addon with gpm:

```toml
[project]
platforms = ["ios", "macos.arm64", "android.arm64", "android.x86_64"]

[addons.SwiftGodot]
source  = "github-release"
repo    = "cafecito-games/SwiftGodot"
version = "v<X.Y.Z>"
```

The release publishes the addon twice over: as the single `SwiftGodot-v<X.Y.Z>.zip`, and as
gpm slices — one archive per platform plus a mandatory `core`, listed by a `gpm-index.toml`
asset. gpm discovers the slices from that asset and downloads only `core`, the platforms
declared above, and the host's own, which matters here because the whole addon unpacks to
well over a gigabyte of Apple frameworks: a Linux or Windows machine, or an Android CI job,
needs `core` plus a few kilobytes of it.

This requires **gpm 0.5.1 or newer**, and the manifest must declare neither `asset` nor
`source_path`:

- `asset` selects one archive of a set that is only complete together, so a sliced addon
  ignores it and reports that it did.
- `source_path` is resolved against the merged slice tree, which is already the addon
  subtree, so `addons/SwiftGodot` resolves to nothing and the install fails.

Projects pinned to a release from before slicing keep using the older form, with `asset` and
`source_path` naming the zip.

Starting with 0.2.0, the addon registers a single no-op GDExtension named **SwiftGodotEmbed** whose only job is to own embedding `SwiftGodot.framework` / `SwiftGodot.xcframework` into iOS and macOS exports. Its `[dependencies]` block points at the bundled SwiftGodot binary, so Godot's exporter copies SwiftGodot into `App.app/Frameworks/` exactly once regardless of how many downstream Swift GDExtensions are installed alongside it.

The same release addon is a Godot Android v2 plugin. Its prebuilt `SwiftGodot-release.aar` contains `arm64-v8a` and `x86_64` libraries plus their Swift runtime closure, and its editor export plugin adds the AAR automatically when **Gradle Build** is enabled. See <doc:Android> for the complete Android toolchain, source-consumer, export, and troubleshooting contract.

Because of this:

- Downstream GDExtensions (e.g. cafecito-games/AuthenticationKit, cafecito-games/PurchaseKit) that link against SwiftGodot **must not** list SwiftGodot under their own `.gdextension`'s `[dependencies]`. Embedding is owned exclusively by SwiftGodotEmbed.
- They still depend on this addon at runtime: SwiftGodotEmbed is what causes the shared SwiftGodot binary to be present in the exported app, and dynamic loading via `@rpath/SwiftGodot.framework/SwiftGodot` resolves through that.
- SwiftGodotEmbed registers zero Godot classes; it is loaded purely for its side effect on the exporter's copy-frameworks phase.

**Compatibility note for downstream addon authors:** if your `.gdextension` declares SwiftGodot under `[dependencies]`, remove it when targeting the SwiftGodot addon ≥ 0.2.0. Two extensions that both list the same SwiftGodot path cause Godot's iOS exporter to emit two `Embed Frameworks` entries for the same path, which Xcode rejects with `Multiple commands produce '.../Frameworks/SwiftGodot.framework'` during archive.

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
linux.debug = "res://bin/libMyFirstGame.so"
linux.release = "res://bin/libMyFirstGame.so"
```

Copy the `.gdextension` file and its referenced binaries into your Godot project. Godot will load the extension automatically on startup.

### Linux source builds

Install Swift 6.3 or newer, then build your dynamic extension product normally:

```bash
swift build -c release --product MyFirstGame
cp .build/release/libMyFirstGame.so /path/to/project/bin/
```

The development machine must have a compatible Swift runtime installed. Linux release artifacts and exported-game runtime bundling are intentionally deferred to a later milestone.

## Working with this Repository

Clone and open in Xcode via `Package.swift`. If you only need to work on the binding generator, open the `Generator` project and edit the `okList` variable to reduce build times.

## License

MIT — see [LICENSE](LICENSE).

Upstream project: [migueldeicaza/SwiftGodot](https://github.com/migueldeicaza/SwiftGodot)
