# iOS Simulator Release Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Apple-Silicon iOS Simulator (`arm64`) slice to the `SwiftGodot.xcframework` and `SwiftGodotRuntime.xcframework` published by the binary release pipeline.

**Architecture:** Mirror the existing iOS device path through all four release components. The simulator build uses xcodebuild destination `generic/platform=iOS Simulator,arch=arm64`, producing `Build/Products/Release-iphonesimulator` products and `GeneratedModuleMaps-iphonesimulator` metadata. A new `build-ios-simulator` CI job feeds those products into the existing `release` job, which assembles a third xcframework slice.

**Tech Stack:** Bash, GitHub Actions, xcodebuild, `xcodebuild -create-xcframework`.

---

### Task 1: Require the simulator metadata artifact in the framework-script test

**Goal:** Extend `scripts/test-make-swiftgodot-framework` so it fails until the release workflow packages iOS Simulator metadata. This is the failing test for Task 2.

**Files:**
- Modify: `scripts/test-make-swiftgodot-framework:34-41`

**Acceptance Criteria:**
- [ ] The test asserts `Build/Intermediates.noindex/GeneratedModuleMaps-iphonesimulator` appears in `.github/workflows/release.yml`.
- [ ] The test fails when run against the current (unmodified) workflow.

**Verify:** `scripts/test-make-swiftgodot-framework` → exits non-zero with `release workflow does not package Build/Intermediates.noindex/GeneratedModuleMaps-iphonesimulator`

**Steps:**

- [ ] **Step 1: Add the simulator artifact to the workflow-packaging assertion**

In `scripts/test-make-swiftgodot-framework`, the loop currently reads:

```bash
for artifact in \
    "Build/Intermediates.noindex/GeneratedModuleMaps" \
    "Build/Intermediates.noindex/GeneratedModuleMaps-iphoneos"
do
    if ! rg -q "$artifact" "$release_workflow"; then
        echo "release workflow does not package $artifact for make-swiftgodot-framework"
        exit 1
    fi
done
```

Add the simulator entry:

```bash
for artifact in \
    "Build/Intermediates.noindex/GeneratedModuleMaps" \
    "Build/Intermediates.noindex/GeneratedModuleMaps-iphoneos" \
    "Build/Intermediates.noindex/GeneratedModuleMaps-iphonesimulator"
do
    if ! rg -q "$artifact" "$release_workflow"; then
        echo "release workflow does not package $artifact for make-swiftgodot-framework"
        exit 1
    fi
done
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `scripts/test-make-swiftgodot-framework`
Expected: FAIL — `release workflow does not package Build/Intermediates.noindex/GeneratedModuleMaps-iphonesimulator for make-swiftgodot-framework`, exit code 1.

- [ ] **Step 3: Commit**

```bash
git add scripts/test-make-swiftgodot-framework
git commit -m "test: require iOS Simulator metadata in release workflow"
```

---

### Task 2: Add the `build-ios-simulator` CI job and wire it into the release job

**Goal:** Build the iOS Simulator (`arm64`) distribution products in CI, upload them as an artifact, and have the `release` job consume them. This makes Task 1's test pass.

**Files:**
- Modify: `.github/workflows/release.yml` (insert a `build-ios-simulator` job after the `build-ios` job, which ends at line 261; update the `release` job's `needs` list and its "Stage release products" step)

**Acceptance Criteria:**
- [ ] A `build-ios-simulator` job exists, depending on `prepare` and `stage-package`.
- [ ] It builds with destination `generic/platform=iOS Simulator,arch=arm64` and packs `Release-iphonesimulator` products plus `GeneratedModuleMaps-iphonesimulator`.
- [ ] It uploads artifact `swiftgodot-ios-simulator-products`.
- [ ] The `release` job lists `build-ios-simulator` in `needs` and extracts the simulator tarball into `DERIVED_DATA`.
- [ ] `scripts/test-make-swiftgodot-framework` passes.

**Verify:** `scripts/test-make-swiftgodot-framework` → exit 0; `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml'))"` → no output, exit 0

**Steps:**

- [ ] **Step 1: Insert the `build-ios-simulator` job**

In `.github/workflows/release.yml`, immediately after the `build-ios` job's
final line (`retention-days: 1` for `swiftgodot-ios-products`, line 261) and
before `  build-arm64:` (line 263), insert this job. It is the `build-ios` job
copied with the destination, tarball name, product directory, and artifact name
changed for the simulator:

```yaml
  build-ios-simulator:
    name: Build iOS Simulator
    needs:
      - prepare
      - stage-package
    runs-on: macos-26

    steps:
      - name: Checkout SwiftGodot
        uses: actions/checkout@v6
        with:
          ref: ${{ needs.prepare.outputs.commit }}

      - name: Set up Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: "${{ env.SWIFT_GODOT_RELEASE_XCODE }}"

      - name: Show build environment
        run: |
          uname -m
          xcodebuild -version
          swift --version

      - name: Download generated-source distribution package
        uses: actions/download-artifact@v4
        with:
          name: swiftgodot-distribution-package
          path: ${{ runner.temp }}

      - name: Extract generated-source distribution package
        run: |
          tar -xzf "$RUNNER_TEMP/swiftgodot-distribution-package.tgz" -C "$RUNNER_TEMP"

      - name: Build iOS Simulator distribution products
        env:
          SWIFT_GODOT_DESTINATION: generic/platform=iOS Simulator,arch=arm64
          SWIFT_GODOT_DERIVED_DATA: ${{ runner.temp }}/swiftgodot-derived
          SWIFT_GODOT_CONFIGURATION: Release
          SWIFT_GODOT_PREPARED_PACKAGE_DIR: ${{ runner.temp }}/swiftgodot-distribution-package
          SWIFT_GODOT_GENERATION_DERIVED_DATA: ${{ runner.temp }}/swiftgodot-generation-derived
          SWIFT_GODOT_RELEASE_PACKAGE_DIR: ${{ runner.temp }}/swiftgodot-distribution-build-package
          SWIFT_GODOT_ARCHIVE_PATH: ${{ runner.temp }}/swiftgodot-archive
        run: |
          scripts/build-distribution-products

      - name: Pack release products
        env:
          DERIVED_DATA: ${{ runner.temp }}/swiftgodot-derived
        run: |
          tar -czf "$RUNNER_TEMP/swiftgodot-ios-simulator-products.tgz" -C "$DERIVED_DATA" \
            Build/Products/Release-iphonesimulator/PackageFrameworks/SwiftGodot.framework \
            Build/Products/Release-iphonesimulator/PackageFrameworks/SwiftGodotRuntime.framework \
            Build/Products/Release-iphonesimulator/SwiftGodot.swiftmodule \
            Build/Products/Release-iphonesimulator/SwiftGodotRuntime.swiftmodule \
            Build/Intermediates.noindex/GeneratedModuleMaps-iphonesimulator

      - name: Upload release products
        uses: actions/upload-artifact@v4
        with:
          name: swiftgodot-ios-simulator-products
          path: ${{ runner.temp }}/swiftgodot-ios-simulator-products.tgz
          if-no-files-found: error
          retention-days: 1
```

- [ ] **Step 2: Add `build-ios-simulator` to the `release` job's `needs`**

The `release` job's `needs` list currently reads:

```yaml
  release:
    name: Package and publish binary release
    needs:
      - prepare
      - build-x86
      - build-ios
      - build-arm64
    runs-on: macos-26
```

Add the simulator job:

```yaml
  release:
    name: Package and publish binary release
    needs:
      - prepare
      - build-x86
      - build-ios
      - build-ios-simulator
      - build-arm64
    runs-on: macos-26
```

- [ ] **Step 3: Extract the simulator tarball in the "Stage release products" step**

The "Stage release products" step currently reads:

```yaml
      - name: Stage release products
        env:
          DERIVED_DATA: ${{ runner.temp }}/sg-builds/release/derived
        run: |
          mkdir -p "$DERIVED_DATA" "${DERIVED_DATA}_arm"
          tar -xzf "$RUNNER_TEMP/release-products/swiftgodot-x86-products/swiftgodot-x86-products.tgz" -C "$DERIVED_DATA"
          tar -xzf "$RUNNER_TEMP/release-products/swiftgodot-ios-products/swiftgodot-ios-products.tgz" -C "$DERIVED_DATA"
          tar -xzf "$RUNNER_TEMP/release-products/swiftgodot-arm64-products/swiftgodot-arm64-products.tgz" -C "${DERIVED_DATA}_arm"
```

Add the simulator extraction line (it shares `$DERIVED_DATA` with the x86 and iOS-device products):

```yaml
      - name: Stage release products
        env:
          DERIVED_DATA: ${{ runner.temp }}/sg-builds/release/derived
        run: |
          mkdir -p "$DERIVED_DATA" "${DERIVED_DATA}_arm"
          tar -xzf "$RUNNER_TEMP/release-products/swiftgodot-x86-products/swiftgodot-x86-products.tgz" -C "$DERIVED_DATA"
          tar -xzf "$RUNNER_TEMP/release-products/swiftgodot-ios-products/swiftgodot-ios-products.tgz" -C "$DERIVED_DATA"
          tar -xzf "$RUNNER_TEMP/release-products/swiftgodot-ios-simulator-products/swiftgodot-ios-simulator-products.tgz" -C "$DERIVED_DATA"
          tar -xzf "$RUNNER_TEMP/release-products/swiftgodot-arm64-products/swiftgodot-arm64-products.tgz" -C "${DERIVED_DATA}_arm"
```

- [ ] **Step 4: Verify the workflow is valid YAML and the test passes**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"`
Expected: no output, exit 0.

Run: `scripts/test-make-swiftgodot-framework`
Expected: PASS (exit 0, no error output).

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: build and publish iOS Simulator release slice"
```

---

### Task 3: Add the iOS Simulator slice to `make-swiftgodot-framework`

**Goal:** Stage the simulator framework and metadata, and add it as a third slice to both `xcodebuild -create-xcframework` invocations.

**Files:**
- Modify: `scripts/make-swiftgodot-framework` (add `bd_ios_sim` near line 35; add `stage_ios_simulator_framework` near line 324; extend the assembly section, lines 340-373)

**Acceptance Criteria:**
- [ ] `bd_ios_sim` points at `Build/Products/<configuration>-iphonesimulator`.
- [ ] `stage_ios_simulator_framework` stages into `$stage_root/iphonesimulator/<module>.framework`.
- [ ] `require_path` guards the simulator `SwiftGodot.framework` and `SwiftGodotRuntime.framework`.
- [ ] Simulator metadata is staged with the `iphonesimulator` platform suffix.
- [ ] Both `-create-xcframework` calls pass a third `-framework` (the simulator slice).

**Verify:** `bash -n scripts/make-swiftgodot-framework` → no output, exit 0; `scripts/test-make-swiftgodot-framework` → exit 0

**Steps:**

- [ ] **Step 1: Add the simulator build-products directory**

The build-products variables currently read (lines 33-36):

```bash
bd_mac="$derived_data/Build/Products/$configuration"
bd_mac_arm="${derived_data}_arm/Build/Products/$configuration"
bd_ios="$derived_data/Build/Products/$configuration-iphoneos"
runtime_output="$(dirname "$output")/SwiftGodotRuntime.xcframework"
```

Add `bd_ios_sim` after `bd_ios`:

```bash
bd_mac="$derived_data/Build/Products/$configuration"
bd_mac_arm="${derived_data}_arm/Build/Products/$configuration"
bd_ios="$derived_data/Build/Products/$configuration-iphoneos"
bd_ios_sim="$derived_data/Build/Products/$configuration-iphonesimulator"
runtime_output="$(dirname "$output")/SwiftGodotRuntime.xcframework"
```

- [ ] **Step 2: Add the `stage_ios_simulator_framework` function**

The `stage_ios_framework` function currently reads (lines 317-324):

```bash
stage_ios_framework() {
    local module=$1
    local staged_framework="$stage_root/iphoneos/$module.framework"
    local primary_framework="$bd_ios/PackageFrameworks/$module.framework"

    stage_framework_copy "$primary_framework" "$staged_framework"
    printf '%s\n' "$staged_framework"
}
```

Add `stage_ios_simulator_framework` immediately after it (before `copy_runtime_module_sidecars`):

```bash
stage_ios_simulator_framework() {
    local module=$1
    local staged_framework="$stage_root/iphonesimulator/$module.framework"
    local primary_framework="$bd_ios_sim/PackageFrameworks/$module.framework"

    stage_framework_copy "$primary_framework" "$staged_framework"
    printf '%s\n' "$staged_framework"
}
```

- [ ] **Step 3: Guard, stage, and assemble the simulator slice**

The assembly section currently reads (lines 340-373):

```bash
require_path "$bd_mac/PackageFrameworks/SwiftGodot.framework"
require_path "$bd_mac/PackageFrameworks/SwiftGodotRuntime.framework"
require_path "$bd_ios/PackageFrameworks/SwiftGodot.framework"
require_path "$bd_ios/PackageFrameworks/SwiftGodotRuntime.framework"

mac_swiftgodot_framework=$(stage_macos_framework "SwiftGodot")
mac_runtime_framework=$(stage_macos_framework "SwiftGodotRuntime")
ios_swiftgodot_framework=$(stage_ios_framework "SwiftGodot")
ios_runtime_framework=$(stage_ios_framework "SwiftGodotRuntime")

if [[ -d "$bd_mac_arm/PackageFrameworks/SwiftGodot.framework" ]]; then
    stage_swiftgodot_metadata "$mac_swiftgodot_framework" "$bd_mac" "$derived_data" "" "$bd_mac_arm" "${derived_data}_arm" ""
else
    stage_swiftgodot_metadata "$mac_swiftgodot_framework" "$bd_mac" "$derived_data" ""
fi

if [[ -d "$bd_mac_arm/PackageFrameworks/SwiftGodotRuntime.framework" ]]; then
    stage_runtime_metadata "$mac_runtime_framework" "$bd_mac" "$derived_data" "" "$bd_mac_arm" "${derived_data}_arm" ""
else
    stage_runtime_metadata "$mac_runtime_framework" "$bd_mac" "$derived_data" ""
fi

stage_swiftgodot_metadata "$ios_swiftgodot_framework" "$bd_ios" "$derived_data" "iphoneos"
stage_runtime_metadata "$ios_runtime_framework" "$bd_ios" "$derived_data" "iphoneos"

xcodebuild -quiet -create-xcframework \
    -framework "$mac_swiftgodot_framework" \
    -framework "$ios_swiftgodot_framework" \
    -output "$output"

xcodebuild -quiet -create-xcframework \
    -framework "$mac_runtime_framework" \
    -framework "$ios_runtime_framework" \
    -output "$runtime_output"
```

Replace that entire block with the version below. It adds the two simulator
`require_path` guards, stages the simulator frameworks and metadata, and adds the
third `-framework` argument to both `-create-xcframework` calls:

```bash
require_path "$bd_mac/PackageFrameworks/SwiftGodot.framework"
require_path "$bd_mac/PackageFrameworks/SwiftGodotRuntime.framework"
require_path "$bd_ios/PackageFrameworks/SwiftGodot.framework"
require_path "$bd_ios/PackageFrameworks/SwiftGodotRuntime.framework"
require_path "$bd_ios_sim/PackageFrameworks/SwiftGodot.framework"
require_path "$bd_ios_sim/PackageFrameworks/SwiftGodotRuntime.framework"

mac_swiftgodot_framework=$(stage_macos_framework "SwiftGodot")
mac_runtime_framework=$(stage_macos_framework "SwiftGodotRuntime")
ios_swiftgodot_framework=$(stage_ios_framework "SwiftGodot")
ios_runtime_framework=$(stage_ios_framework "SwiftGodotRuntime")
ios_sim_swiftgodot_framework=$(stage_ios_simulator_framework "SwiftGodot")
ios_sim_runtime_framework=$(stage_ios_simulator_framework "SwiftGodotRuntime")

if [[ -d "$bd_mac_arm/PackageFrameworks/SwiftGodot.framework" ]]; then
    stage_swiftgodot_metadata "$mac_swiftgodot_framework" "$bd_mac" "$derived_data" "" "$bd_mac_arm" "${derived_data}_arm" ""
else
    stage_swiftgodot_metadata "$mac_swiftgodot_framework" "$bd_mac" "$derived_data" ""
fi

if [[ -d "$bd_mac_arm/PackageFrameworks/SwiftGodotRuntime.framework" ]]; then
    stage_runtime_metadata "$mac_runtime_framework" "$bd_mac" "$derived_data" "" "$bd_mac_arm" "${derived_data}_arm" ""
else
    stage_runtime_metadata "$mac_runtime_framework" "$bd_mac" "$derived_data" ""
fi

stage_swiftgodot_metadata "$ios_swiftgodot_framework" "$bd_ios" "$derived_data" "iphoneos"
stage_runtime_metadata "$ios_runtime_framework" "$bd_ios" "$derived_data" "iphoneos"

stage_swiftgodot_metadata "$ios_sim_swiftgodot_framework" "$bd_ios_sim" "$derived_data" "iphonesimulator"
stage_runtime_metadata "$ios_sim_runtime_framework" "$bd_ios_sim" "$derived_data" "iphonesimulator"

xcodebuild -quiet -create-xcframework \
    -framework "$mac_swiftgodot_framework" \
    -framework "$ios_swiftgodot_framework" \
    -framework "$ios_sim_swiftgodot_framework" \
    -output "$output"

xcodebuild -quiet -create-xcframework \
    -framework "$mac_runtime_framework" \
    -framework "$ios_runtime_framework" \
    -framework "$ios_sim_runtime_framework" \
    -output "$runtime_output"
```

- [ ] **Step 4: Verify shell syntax and the static test**

Run: `bash -n scripts/make-swiftgodot-framework`
Expected: no output, exit 0.

Run: `scripts/test-make-swiftgodot-framework`
Expected: PASS (exit 0).

- [ ] **Step 5: Commit**

```bash
git add scripts/make-swiftgodot-framework
git commit -m "feat: add iOS Simulator slice to SwiftGodot xcframeworks"
```

---

### Task 4: Build and validate the iOS Simulator slice in `scripts/release`

**Goal:** Make the local release script build the simulator products in its build path and validate them in its `SKIP_BUILD` (prebuilt) path, so both CI and local runs feed a complete set of products to `make-swiftgodot-framework`.

**Files:**
- Modify: `scripts/release` (add a `build_distribution_products` call near line 147-151; add `require_prebuilt_artifact` checks near line 180-187)

**Acceptance Criteria:**
- [ ] The build path runs `build_distribution_products` for `generic/platform=iOS Simulator,arch=arm64` into `$derived_data`.
- [ ] The `SKIP_BUILD` path validates the `-iphonesimulator` `PackageFrameworks`, `.swiftmodule` products, and `GeneratedModuleMaps-iphonesimulator` metadata.

**Verify:** `bash -n scripts/release` → no output, exit 0; `SWIFT_GODOT_SKIP_BUILD=1 SWIFT_GODOT_DERIVED_DATA=/tmp/sg-empty-derived scripts/release v0.0.0-test /dev/null HEAD` → fails with `Missing prebuilt release artifact: .../Release-iphonesimulator/PackageFrameworks/SwiftGodot.framework`

**Steps:**

- [ ] **Step 1: Build the simulator products in the build path**

In `scripts/release`, the iOS device build call currently reads (lines 147-151):

```bash
    build_distribution_products \
        "generic/platform=iOS" \
        "$derived_data" \
        "$build_dir/generated-ios" \
        "$build_dir/distribution-ios" \
        "$build_dir/ios_arm64.log"
```

Add a simulator build call immediately after it (still inside the
`if [[ -z "${SWIFT_GODOT_SKIP_BUILD:-}" ]]` branch, before the closing `else`):

```bash
    build_distribution_products \
        "generic/platform=iOS" \
        "$derived_data" \
        "$build_dir/generated-ios" \
        "$build_dir/distribution-ios" \
        "$build_dir/ios_arm64.log"

    build_distribution_products \
        "generic/platform=iOS Simulator,arch=arm64" \
        "$derived_data" \
        "$build_dir/generated-ios-simulator" \
        "$build_dir/distribution-ios-simulator" \
        "$build_dir/ios_simulator_arm64.log"
```

- [ ] **Step 2: Validate the simulator products in the `SKIP_BUILD` path**

The prebuilt-artifact checks for iOS currently read (lines 180-187):

```bash
    require_prebuilt_artifact "$derived_data/Build/Products/$configuration-iphoneos/PackageFrameworks/SwiftGodot.framework"
    require_prebuilt_artifact "$derived_data/Build/Products/$configuration-iphoneos/PackageFrameworks/SwiftGodotRuntime.framework"
    require_prebuilt_artifact "$derived_data/Build/Products/$configuration-iphoneos/SwiftGodot.swiftmodule"
    require_prebuilt_artifact "$derived_data/Build/Products/$configuration-iphoneos/SwiftGodotRuntime.swiftmodule"
    require_prebuilt_artifact "$derived_data/Build/Intermediates.noindex/GeneratedModuleMaps-iphoneos/SwiftGodot.modulemap"
    require_prebuilt_artifact "$derived_data/Build/Intermediates.noindex/GeneratedModuleMaps-iphoneos/SwiftGodot-Swift.h"
    require_prebuilt_artifact "$derived_data/Build/Intermediates.noindex/GeneratedModuleMaps-iphoneos/SwiftGodotRuntime.modulemap"
    require_prebuilt_artifact "$derived_data/Build/Intermediates.noindex/GeneratedModuleMaps-iphoneos/SwiftGodotRuntime-Swift.h"
```

Add the matching simulator checks immediately after that block:

```bash
    require_prebuilt_artifact "$derived_data/Build/Products/$configuration-iphonesimulator/PackageFrameworks/SwiftGodot.framework"
    require_prebuilt_artifact "$derived_data/Build/Products/$configuration-iphonesimulator/PackageFrameworks/SwiftGodotRuntime.framework"
    require_prebuilt_artifact "$derived_data/Build/Products/$configuration-iphonesimulator/SwiftGodot.swiftmodule"
    require_prebuilt_artifact "$derived_data/Build/Products/$configuration-iphonesimulator/SwiftGodotRuntime.swiftmodule"
    require_prebuilt_artifact "$derived_data/Build/Intermediates.noindex/GeneratedModuleMaps-iphonesimulator/SwiftGodot.modulemap"
    require_prebuilt_artifact "$derived_data/Build/Intermediates.noindex/GeneratedModuleMaps-iphonesimulator/SwiftGodot-Swift.h"
    require_prebuilt_artifact "$derived_data/Build/Intermediates.noindex/GeneratedModuleMaps-iphonesimulator/SwiftGodotRuntime.modulemap"
    require_prebuilt_artifact "$derived_data/Build/Intermediates.noindex/GeneratedModuleMaps-iphonesimulator/SwiftGodotRuntime-Swift.h"
```

- [ ] **Step 3: Verify shell syntax and the prebuilt-path guard**

Run: `bash -n scripts/release`
Expected: no output, exit 0.

Run: `SWIFT_GODOT_SKIP_BUILD=1 SWIFT_GODOT_DERIVED_DATA=/tmp/sg-empty-derived scripts/release v0.0.0-test /dev/null HEAD`
Expected: FAIL — the script reaches the prebuilt-artifact checks and reports a `Missing prebuilt release artifact:` line. (It fails earlier on the macOS/iOS-device artifacts since the DerivedData is empty; the goal is only to confirm the script still parses and runs. Confirm no syntax error.)

- [ ] **Step 4: Commit**

```bash
git add scripts/release
git commit -m "feat: build and validate iOS Simulator products in release script"
```

---

## Self-Review Notes

- **Spec coverage:** Spec section 1 → Task 3; section 2 → Task 2; section 3 → Task 4; section 4 → Task 1. All four spec components are covered.
- **Type consistency:** Function name `stage_ios_simulator_framework` and variable `bd_ios_sim` are used consistently across Task 3 steps. Artifact path `GeneratedModuleMaps-iphonesimulator` matches between Tasks 1, 2, and 4.
- **Ordering:** Task 1 (failing test) precedes Task 2 (makes it pass). Tasks 3 and 4 are independent of each other and of the test, but depend on no earlier task's code — they may run in any order after Task 1.
