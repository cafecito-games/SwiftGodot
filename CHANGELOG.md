# Changelog

## Unreleased

### Added
- Android API 28 support for `arm64-v8a` and `x86_64`, built with Swift 6.3.3 and the official matching Swift Android SDK.
- A publishable Godot Android v2 plugin AAR containing `libSwiftGodot.so`, `libSwiftGodotEmbed.so`, and their complete shared runtime dependency closure.
- Android export integration in the cross-platform Godot addon, plus an independently linked runtime probe exercised on an x86_64 emulator in CI.

### Changed
- The supported engine contract is now Cafecito Godot 4.7.2.
- Release assets now include `SwiftGodot-release.aar`, and the Godot addon includes that AAR alongside its Apple xcframeworks.

## 0.2.0

### Added
- The Godot addon now ships a registered no-op GDExtension, **SwiftGodotEmbed**, whose sole purpose is to own embedding `SwiftGodot.framework` / `SwiftGodot.xcframework` into exported iOS and macOS apps. The addon zip layout grows the following entries:
  - `addons/SwiftGodot/SwiftGodotEmbed.gdextension`
  - `addons/SwiftGodot/bin/ios/SwiftGodotEmbed.xcframework`
  - `addons/SwiftGodot/bin/macos_arm64/SwiftGodotEmbed.framework`
- A matching `SwiftGodotEmbed` SwiftPM library product/target backed by `Sources/SwiftGodotEmbed/SwiftGodotEmbed.swift`.

### Changed
- The addon `plugin.cfg` description now reflects that the addon registers an embed-only extension.
- The release pipeline builds and packages both `SwiftGodot.xcframework` and `SwiftGodotEmbed.xcframework`. `scripts/make-swiftgodot-framework` now writes both xcframeworks into an output directory (its second argument is now a directory, not a `.xcframework` path).
- `scripts/package-godot-addon` now requires both xcframeworks: `package-godot-addon TAG SWIFTGODOT_XCFRAMEWORK SWIFTGODOTEMBED_XCFRAMEWORK [OUTPUT_DIR]`.

### Compatibility — breaking for downstream addon authors

Any GDExtension that previously listed SwiftGodot under its own `.gdextension`'s `[dependencies]` (for example to satisfy `@rpath/SwiftGodot.framework/SwiftGodot` at runtime) must **remove that entry** when targeting the SwiftGodot addon ≥ 0.2.0.

Godot 4.6's iOS exporter does not deduplicate `[dependencies]` entries by resolved on-disk path. When two extensions both reference the same `SwiftGodot.xcframework`, the exporter emits two `Embed Frameworks` build files, and Xcode rejects the archive with `Multiple commands produce '.../Frameworks/SwiftGodot.framework'`.

SwiftGodotEmbed owns the embed entry; downstream extensions resolve SwiftGodot symbols at load time through the `@rpath` lookup against the already-embedded framework. The SwiftGodot addon must be installed alongside the consumer extension (this was already a documented requirement).

Coordinated downstream releases drop the dependency:
- `cafecito-games/AuthenticationKit` 0.3.0
- `cafecito-games/PurchaseKit` 0.3.0
