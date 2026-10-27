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

**Binary runtime (xcframeworks + source macro target)** — avoids compiling SwiftGodot's generated bindings and generators. Published at [cafecito-games/SwiftGodotBinary](https://github.com/cafecito-games/SwiftGodotBinary):

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

The `SwiftGodot` product downloads prebuilt `SwiftGodot` and `GDExtensionC` XCFrameworks and builds only `SwiftGodotMacroLibrary` from source, so `@Godot`, `@Callable`, `@Export`, `#initSwiftExtension`, and the other macros work through SwiftPM's supported macro-target model. This package therefore depends on `swift-syntax`; a cold build may fetch or compile it when the selected toolchain has no compatible prebuilt SwiftSyntax modules. Subsequent builds reuse SwiftPM's cache. Consumers that must build fully offline need both the binary artifacts and Swift package dependencies cached in advance. The XCFramework package supports Apple platforms; Linux consumers must use the source build above.

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

## Release validation and diagnosis

Releases publish the source release and the `SwiftGodotBinary` metadata in two
stages so a transport hang in the final consumer check cannot poison already-built
platform artifacts:

1. The `release` job builds and uploads every platform artifact, then publishes the
   source release as a **prerelease** and defers binary-package publication
   (`SWIFT_GODOT_DEFER_BINARY_PUBLISH=1`).
2. The `publish-binary-package` job clones `SwiftGodotBinary`, verifies the public
   asset URLs and checksums, and builds a clean consumer against the exact published
   package before promoting the source release to stable.

A failed final validation leaves the prerelease and all release inputs intact, so
the failed `publish-binary-package` job can be re-run to retry validation without
rebuilding platform artifacts: it re-downloads the preserved binary-package metadata
and re-runs the clean consumer build. `scripts/release` can also regenerate that
metadata from an existing prerelease's published asset digests instead of recomputing
checksums from a local rebuild. Publication stays fail-closed: the binary tag is only
pushed and the source release only promoted after the clean consumer build passes.

The clean consumer build (`scripts/test-binary-package-consumer`) separates resolution
from compilation and timestamps every phase, so a stall is attributable to downloading
XCFrameworks, compiling `swift-syntax`, compiling the macro target, or
compiling/linking the consumer. Each phase runs under a watchdog that terminates the
whole SwiftPM process tree and dumps the active toolchain processes and the phase log
tail on timeout. The per-phase bound is derived from the `consumer_validation_timeout`
workflow input (default 25 minutes) and capped at 600 seconds, so the watchdog always
fires before the workflow's hard timeout kills the step.

To diagnose a hosted download stall without rebuilding anything, run the `Release`
workflow with **Diagnose published SwiftPM binary downloads** enabled. It probes each
published artifact, then builds a clean consumer twice — once with SwiftPM
prefetching enabled and once with `--disable-prefetching` — so the two paths can be
compared on a GitHub-hosted macOS runner.

## License

MIT — see [LICENSE](LICENSE).

Upstream project: [migueldeicaza/SwiftGodot](https://github.com/migueldeicaza/SwiftGodot)
