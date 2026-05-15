# iOS Simulator Slice for SwiftGodotBinary Releases

## Problem

The release pipeline (`.github/workflows/release.yml` + `scripts/release` +
`scripts/make-swiftgodot-framework`) builds and publishes `SwiftGodot.xcframework`
and `SwiftGodotRuntime.xcframework` to the `SwiftGodotBinary` repository. Today
those xcframeworks contain only two slices:

- macOS universal (`arm64` + `x86_64` merged with `lipo`)
- iOS device (`generic/platform=iOS` → `Release-iphoneos`)

There is no iOS Simulator slice. A developer building a Godot game against the
iOS Simulator cannot link the published binary release, because the xcframework
has no `ios-arm64-simulator` slice.

## Goal

Add an iOS Simulator slice to both published xcframeworks so the binary release
links against the iOS Simulator. The slice covers Apple Silicon only
(`arm64`); Intel Macs running the iOS Simulator are out of scope.

## Approach

Mirror the existing iOS device path everywhere it appears. The simulator build
products land in `Build/Products/<configuration>-iphonesimulator` and use the
`iphonesimulator` platform suffix for `GeneratedModuleMaps`.

### 1. `scripts/make-swiftgodot-framework`

- Add `bd_ios_sim="$derived_data/Build/Products/$configuration-iphonesimulator"`.
- Add a `stage_ios_simulator_framework` function mirroring `stage_ios_framework`,
  staging into `$stage_root/iphonesimulator/<module>.framework`.
- Add `require_path` guards for the simulator `SwiftGodot.framework` and
  `SwiftGodotRuntime.framework`.
- Stage simulator metadata via `stage_swiftgodot_metadata` / `stage_runtime_metadata`
  with the `iphonesimulator` platform suffix.
- Add a third `-framework` argument (the simulator framework) to both
  `xcodebuild -create-xcframework` calls.

### 2. `.github/workflows/release.yml`

- Add a `build-ios-simulator` job parallel to `build-ios`, depending on
  `prepare` and `stage-package`, with:
  - `SWIFT_GODOT_DESTINATION: generic/platform=iOS Simulator,arch=arm64`
  - products packed from `Build/Products/Release-iphonesimulator/...` and
    `Build/Intermediates.noindex/GeneratedModuleMaps-iphonesimulator` into
    `swiftgodot-ios-simulator-products.tgz`, uploaded as artifact
    `swiftgodot-ios-simulator-products`.
- Add `build-ios-simulator` to the `release` job's `needs`.
- In the `release` job's "Stage release products" step, extract
  `swiftgodot-ios-simulator-products.tgz` into the shared `DERIVED_DATA`.

### 3. `scripts/release`

- In the build path (non-`SKIP_BUILD`), add a `build_distribution_products`
  call for `generic/platform=iOS Simulator,arch=arm64` into `$derived_data`.
- In the `SKIP_BUILD` path, add `require_prebuilt_artifact` checks for the
  `-iphonesimulator` `PackageFrameworks`, `.swiftmodule` products, and
  `GeneratedModuleMaps-iphonesimulator` modulemap / `-Swift.h` metadata.

### 4. `scripts/test-make-swiftgodot-framework`

- Add `Build/Intermediates.noindex/GeneratedModuleMaps-iphonesimulator` to the
  list of artifacts the release workflow must package.

## Out of Scope

- Intel (`x86_64`) iOS Simulator support.
- tvOS / visionOS slices (the package declares only `macOS` and `iOS`).
- Changes to `binaries.json` or the consuming `Package.swift` — they reference
  the xcframework by path and simply gain a slice.

## Verification

- `scripts/test-make-swiftgodot-framework` passes.
- A produced `SwiftGodot.xcframework` lists three slices in `Info.plist`:
  `macos-arm64_x86_64`, `ios-arm64`, `ios-arm64-simulator`.
- The release workflow's job graph includes `build-ios-simulator` upstream of
  `release`.
