# Optional macOS x86_64 in SwiftGodotBinary Releases

## Problem

The release pipeline always builds a macOS x86_64 (Intel) slice for both the
runtime xcframeworks and the `SwiftGodotMacros` compiler-plugin artifact bundle.
For a project that develops and ships on Apple Silicon, the x86_64 outputs are
dead weight: the `build-x86` CI job consumes a scarce `macos-26-intel` runner,
and the macro plugin carries an unused x86_64 slice.

The x86_64 outputs should still be producible on demand — for collaborators on
Intel Macs — but should not be built by default.

## Goal

Make every x86_64 macOS output opt-in:

- A `workflow_dispatch` boolean input `include_macos_x86` (default `false`)
  controls the CI release.
- An env var `SWIFT_GODOT_INCLUDE_MACOS_X86` (default off) controls the local
  `scripts/release` build and the macro artifact bundle.

When x86_64 is off (the default):

- The macOS runtime slice is arm64-only (`macos-arm64`), not universal.
- The `SwiftGodotMacros` artifact bundle is an arm64-only plugin.
- The `macos-26-intel` runner is not used at all.

When x86_64 is on, behavior is exactly as today: a universal
`macos-arm64_x86_64` runtime slice and a universal macro plugin.

## Background: current macOS slice assembly

`make-swiftgodot-framework` currently treats **x86_64 as the primary** macOS
framework and `lipo`-merges arm64 into it. Build products are staged so that:

- `$DERIVED_DATA/Build/Products/Release` holds the **x86_64** macOS products.
- `${DERIVED_DATA}_arm/Build/Products/Release` holds the **arm64** macOS products.

Making x86_64 optional requires arm64 to become the primary slice.

## Approach

Swap the staging directories so the primary arm64 build occupies the main
`$DERIVED_DATA` directory (alongside the iOS builds) and the optional x86_64
build occupies a `${DERIVED_DATA}_x86` sidecar. `make-swiftgodot-framework`
treats `$DERIVED_DATA` as the primary macOS slice and merges `_x86` only when
present. This keeps directory naming honest: the suffixed directory is clearly
the optional extra.

### 1. `.github/workflows/release.yml`

- Add a `workflow_dispatch` input `include_macos_x86`: boolean, `required: false`,
  `default: false`, description "Also build a macOS x86_64 (Intel) slice."
- `build-x86` job: add `if: ${{ inputs.include_macos_x86 }}`.
- `build-arm64` job: unchanged build, but the `release` job now extracts its
  tarball into `$DERIVED_DATA` (the primary slot).
- `release` job:
  - Add an `if:` so it runs when `prepare`, `build-ios`, `build-ios-simulator`,
    and `build-arm64` all succeeded and `build-x86` is `success` or `skipped`:
    ```yaml
    if: >-
      ${{ !cancelled()
      && needs.prepare.result == 'success'
      && needs.build-ios.result == 'success'
      && needs.build-ios-simulator.result == 'success'
      && needs.build-arm64.result == 'success'
      && (needs.build-x86.result == 'success' || needs.build-x86.result == 'skipped') }}
    ```
  - "Stage release products" step: extract the arm64 tarball into `$DERIVED_DATA`,
    extract the x86 tarball into `${DERIVED_DATA}_x86` only if that artifact file
    exists, extract the iOS and iOS-simulator tarballs into `$DERIVED_DATA` (as
    today).
  - "Run release script" step: pass `SWIFT_GODOT_INCLUDE_MACOS_X86: ${{ inputs.include_macos_x86 }}`.

### 2. `scripts/make-swiftgodot-framework`

- `bd_mac` becomes the **primary arm64** products: `$derived_data/Build/Products/$configuration`.
- New `bd_mac_x86`: `${derived_data}_x86/Build/Products/$configuration`, optional.
- `require_path` guards `bd_mac` (arm64) unconditionally; the x86 framework and
  metadata are used only when `[[ -d "$bd_mac_x86/PackageFrameworks/..." ]]`.
- `stage_macos_framework` stages the arm64 framework as primary and merges the
  x86 binary via `lipo` only when `bd_mac_x86` is present.
- Metadata staging (`stage_swiftgodot_metadata` / `stage_runtime_metadata`)
  sources the primary from arm64 (`bd_mac` / `$derived_data`) and the optional
  secondary from x86 (`bd_mac_x86` / `${derived_data}_x86`).
- Result: a universal `macos-arm64_x86_64` slice when x86 products are present,
  an arm64-only `macos-arm64` slice otherwise.

### 3. `scripts/release`

- Add opt-in env var `SWIFT_GODOT_INCLUDE_MACOS_X86` (default off).
- Build path: always build macOS arm64 into `$derived_data`; build macOS x86_64
  into `${derived_data}_x86` only when the var is set. The existing host-arch
  gate on the arm64 build is removed (arm64 is always the primary build).
- `SKIP_BUILD` path: require the arm64 macOS prebuilt artifacts under
  `$derived_data` unconditionally; require the x86 artifacts under
  `${derived_data}_x86` only when the var is set.

### 4. `scripts/build-macro-artifactbundle`

- Read `SWIFT_GODOT_INCLUDE_MACOS_X86` (default off).
- When on: build `swift build --arch arm64 --arch x86_64`, validate a universal
  binary, and list both triples in `info.json` — exactly as today.
- When off: build `swift build --arch arm64`, validate a single arm64 slice,
  and list only `arm64-apple-macosx` in `info.json`.
- No wiring change in `scripts/release`: it already invokes this script, and the
  env var propagates to the child process.

## Out of Scope

- Changes to `binaries.json` or the consuming `Package.swift` — they reference
  the xcframework and artifact bundle by path; the macOS xcframework slice id
  simply changes between `macos-arm64` and `macos-arm64_x86_64`.
- The PR-coverage workflow that builds the macro bundle: it leaves
  `SWIFT_GODOT_INCLUDE_MACOS_X86` unset, so it keeps validating a universal
  bundle. No change.

## Verification

- `release.yml` parses as valid YAML; the `build-x86` job is gated on the input;
  the `release` job tolerates a skipped `build-x86`.
- `bash -n` clean on `scripts/release`, `scripts/make-swiftgodot-framework`,
  `scripts/build-macro-artifactbundle`.
- Existing release test scripts (`test-make-swiftgodot-framework`,
  `test-release-build-configuration`, and any others asserting x86 presence)
  pass, updated where they assumed x86_64 was mandatory.
- Default release run (`include_macos_x86` unset/false): produces a `macos-arm64`
  xcframework slice and an arm64-only macro bundle; the `macos-26-intel` runner
  is not used.
- Opt-in release run (`include_macos_x86: true`): produces a
  `macos-arm64_x86_64` xcframework slice and a universal macro bundle.
