# Optional macOS x86_64 Builds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every macOS x86_64 (Intel) output of the release pipeline opt-in, so the default release ships an arm64-only macOS slice and arm64-only macro plugin without using the `macos-26-intel` runner.

**Architecture:** The arm64 macOS build becomes the primary slice, staged into the main `$DERIVED_DATA` directory; the optional x86_64 build is staged into a `${DERIVED_DATA}_x86` sidecar and merged only when present. A `workflow_dispatch` boolean input `include_macos_x86` (default false) gates CI; an env var `SWIFT_GODOT_INCLUDE_MACOS_X86` gates the local `scripts/release` and the macro bundle.

**Tech Stack:** Bash, GitHub Actions, xcodebuild, `xcodebuild -create-xcframework`, `swift build`.

---

### Task 1: Flip the optional macOS slice to x86_64 in `make-swiftgodot-framework`

**Goal:** `make-swiftgodot-framework` treats `$derived_data` (arm64) as the primary macOS slice and `${derived_data}_x86` as the optional secondary merged via `lipo`.

**Files:**
- Modify: `scripts/make-swiftgodot-framework`

**Context:** Today the script treats `$derived_data` as the *primary* macOS slice and `${derived_data}_arm` as the optional secondary — and the staging in CI puts x86_64 in `$derived_data`, arm64 in `${derived_data}_arm`. Tasks 2 and 3 swap the staging so arm64 lands in `$derived_data` and x86_64 in `${derived_data}_x86`. Because the script already treats the suffixed directory as an *optional* secondary (guarded by `[[ -d ]]`), this task is purely a rename: `bd_mac_arm` → `bd_mac_x86`, and the directory suffix `_arm` → `_x86`. No logic change.

**Acceptance Criteria:**
- [ ] The variable `bd_mac_arm` is renamed to `bd_mac_x86` everywhere it appears.
- [ ] Every `${derived_data}_arm` occurrence becomes `${derived_data}_x86`.
- [ ] `bd_mac` is unchanged (still `$derived_data/Build/Products/$configuration`).
- [ ] No other lines change.

**Verify:** `bash -n scripts/make-swiftgodot-framework` → exit 0; `scripts/test-make-swiftgodot-framework` → exit 0

**Steps:**

- [ ] **Step 1: Rename `bd_mac_arm` → `bd_mac_x86` and the directory suffix**

Apply two global replacements to `scripts/make-swiftgodot-framework`:
- Replace every occurrence of `bd_mac_arm` with `bd_mac_x86`.
- Replace every occurrence of `${derived_data}_arm` with `${derived_data}_x86`.

After the change, these are the affected lines (before → after):

Variable definition:
```bash
bd_mac_arm="${derived_data}_arm/Build/Products/$configuration"
```
becomes
```bash
bd_mac_x86="${derived_data}_x86/Build/Products/$configuration"
```

Inside `stage_macos_framework`:
```bash
    local secondary_framework="$bd_mac_arm/PackageFrameworks/$module.framework"
```
becomes
```bash
    local secondary_framework="$bd_mac_x86/PackageFrameworks/$module.framework"
```

The metadata assembly block:
```bash
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
```
becomes
```bash
if [[ -d "$bd_mac_x86/PackageFrameworks/SwiftGodot.framework" ]]; then
    stage_swiftgodot_metadata "$mac_swiftgodot_framework" "$bd_mac" "$derived_data" "" "$bd_mac_x86" "${derived_data}_x86" ""
else
    stage_swiftgodot_metadata "$mac_swiftgodot_framework" "$bd_mac" "$derived_data" ""
fi

if [[ -d "$bd_mac_x86/PackageFrameworks/SwiftGodotRuntime.framework" ]]; then
    stage_runtime_metadata "$mac_runtime_framework" "$bd_mac" "$derived_data" "" "$bd_mac_x86" "${derived_data}_x86" ""
else
    stage_runtime_metadata "$mac_runtime_framework" "$bd_mac" "$derived_data" ""
fi
```

- [ ] **Step 2: Verify**

Run: `bash -n scripts/make-swiftgodot-framework`
Expected: no output, exit 0.

Run: `scripts/test-make-swiftgodot-framework`
Expected: PASS, exit 0.

- [ ] **Step 3: Commit**

```bash
git add scripts/make-swiftgodot-framework
git commit -m "refactor: make x86_64 the optional macOS slice in make-swiftgodot-framework"
```

---

### Task 2: Gate the `build-x86` job behind a `workflow_dispatch` input

**Goal:** `release.yml` gains an `include_macos_x86` input; `build-x86` runs only when it is true; the `release` job tolerates a skipped `build-x86`, stages arm64 as the primary macOS slice, and stages x86_64 into a sidecar only when present.

**Files:**
- Modify: `.github/workflows/release.yml`

**Acceptance Criteria:**
- [ ] A `workflow_dispatch` boolean input `include_macos_x86` exists, `default: false`.
- [ ] The `build-x86` job has `if: ${{ inputs.include_macos_x86 }}`.
- [ ] The `release` job has an `if:` that runs it when the required jobs succeeded and `build-x86` is `success` or `skipped`.
- [ ] The "Stage release products" step extracts the arm64 tarball into `$DERIVED_DATA` and the x86 tarball into `${DERIVED_DATA}_x86` only if that artifact exists.
- [ ] The "Run release script" step passes `SWIFT_GODOT_INCLUDE_MACOS_X86` mapped to `1`/empty.

**Verify:** `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"` → no output, exit 0

**Steps:**

- [ ] **Step 1: Add the `include_macos_x86` input**

In the `workflow_dispatch.inputs` block, the last input is currently:
```yaml
      release_notes:
        description: Release notes for the GitHub release.
        required: true
        type: string
```
Add a new input immediately after it:
```yaml
      release_notes:
        description: Release notes for the GitHub release.
        required: true
        type: string
      include_macos_x86:
        description: Also build a macOS x86_64 (Intel) slice.
        required: false
        type: boolean
        default: false
```

- [ ] **Step 2: Gate the `build-x86` job**

The `build-x86` job header currently reads:
```yaml
  build-x86:
    name: Build macOS x86_64
    needs:
      - prepare
      - stage-package
    runs-on: macos-26-intel
```
Add an `if:` after `runs-on:`:
```yaml
  build-x86:
    name: Build macOS x86_64
    needs:
      - prepare
      - stage-package
    runs-on: macos-26-intel
    if: ${{ inputs.include_macos_x86 }}
```

- [ ] **Step 3: Add the `release` job `if:` condition**

The `release` job header currently reads:
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
Add an `if:` after `runs-on:` so the job runs when `build-x86` is skipped but the
others succeeded:
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
    if: >-
      ${{ !cancelled()
      && needs.prepare.result == 'success'
      && needs.build-ios.result == 'success'
      && needs.build-ios-simulator.result == 'success'
      && needs.build-arm64.result == 'success'
      && (needs.build-x86.result == 'success' || needs.build-x86.result == 'skipped') }}
```

- [ ] **Step 4: Rewrite the "Stage release products" step**

That step currently reads:
```yaml
      - name: Stage release products
        env:
          DERIVED_DATA: ${{ runner.temp }}/sg-builds/release/derived
        run: |
          # The x86, iOS-device, and iOS-simulator tarballs all extract into the
          # same DERIVED_DATA. This is safe only because each job packs SDK-suffixed,
          # disjoint top-level paths (Release / Release-iphoneos / Release-iphonesimulator
          # and their matching GeneratedModuleMaps dirs). Keep that invariant if you
          # change what any build job packs.
          mkdir -p "$DERIVED_DATA" "${DERIVED_DATA}_arm"
          tar -xzf "$RUNNER_TEMP/release-products/swiftgodot-x86-products/swiftgodot-x86-products.tgz" -C "$DERIVED_DATA"
          tar -xzf "$RUNNER_TEMP/release-products/swiftgodot-ios-products/swiftgodot-ios-products.tgz" -C "$DERIVED_DATA"
          tar -xzf "$RUNNER_TEMP/release-products/swiftgodot-ios-simulator-products/swiftgodot-ios-simulator-products.tgz" -C "$DERIVED_DATA"
          tar -xzf "$RUNNER_TEMP/release-products/swiftgodot-arm64-products/swiftgodot-arm64-products.tgz" -C "${DERIVED_DATA}_arm"
```
Replace the whole step with:
```yaml
      - name: Stage release products
        env:
          DERIVED_DATA: ${{ runner.temp }}/sg-builds/release/derived
        run: |
          # The arm64-macOS, iOS-device, and iOS-simulator tarballs all extract
          # into the same DERIVED_DATA. This is safe only because each job packs
          # SDK-suffixed, disjoint top-level paths (Release / Release-iphoneos /
          # Release-iphonesimulator and their matching GeneratedModuleMaps dirs).
          # The optional macOS x86_64 products extract into a separate
          # ${DERIVED_DATA}_x86 sidecar. Keep that invariant if you change what
          # any build job packs.
          mkdir -p "$DERIVED_DATA"
          tar -xzf "$RUNNER_TEMP/release-products/swiftgodot-arm64-products/swiftgodot-arm64-products.tgz" -C "$DERIVED_DATA"
          tar -xzf "$RUNNER_TEMP/release-products/swiftgodot-ios-products/swiftgodot-ios-products.tgz" -C "$DERIVED_DATA"
          tar -xzf "$RUNNER_TEMP/release-products/swiftgodot-ios-simulator-products/swiftgodot-ios-simulator-products.tgz" -C "$DERIVED_DATA"
          x86_tarball="$RUNNER_TEMP/release-products/swiftgodot-x86-products/swiftgodot-x86-products.tgz"
          if [[ -f "$x86_tarball" ]]; then
            mkdir -p "${DERIVED_DATA}_x86"
            tar -xzf "$x86_tarball" -C "${DERIVED_DATA}_x86"
          fi
```

- [ ] **Step 5: Pass `SWIFT_GODOT_INCLUDE_MACOS_X86` to the release script**

The "Run release script" step's `env:` block currently reads:
```yaml
      - name: Run release script
        env:
          GH_TOKEN: ${{ github.token }}
          SWIFT_GODOT_SOURCE_REPO: ${{ github.repository }}
          SWIFT_GODOT_BINARY_REPO: cafecito-games/SwiftGodotBinary
          SWIFT_GODOT_BINARY_REPO_DIR: ${{ runner.temp }}/SwiftGodotBinary
          SWIFT_GODOT_OUTPUT_DIR: ${{ runner.temp }}/sg-builds
          SWIFT_GODOT_DERIVED_DATA: ${{ runner.temp }}/sg-builds/release/derived
          SWIFT_GODOT_CONFIGURATION: Release
          SWIFT_GODOT_SKIP_BUILD: 1
        run: |
          scripts/release "${{ inputs.tag }}" "$RUNNER_TEMP/release-notes.md" "${{ needs.prepare.outputs.commit }}"
```
Add one env line (`SWIFT_GODOT_INCLUDE_MACOS_X86`) after `SWIFT_GODOT_SKIP_BUILD: 1`:
```yaml
          SWIFT_GODOT_SKIP_BUILD: 1
          SWIFT_GODOT_INCLUDE_MACOS_X86: ${{ inputs.include_macos_x86 && '1' || '' }}
        run: |
          scripts/release "${{ inputs.tag }}" "$RUNNER_TEMP/release-notes.md" "${{ needs.prepare.outputs.commit }}"
```

- [ ] **Step 6: Verify**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"`
Expected: no output, exit 0.

- [ ] **Step 7: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: make macOS x86_64 release slice opt-in via workflow input"
```

---

### Task 3: Make x86_64 opt-in in `scripts/release`

**Goal:** `scripts/release` always builds/validates the arm64 macOS products as the primary slice and handles x86_64 only when `SWIFT_GODOT_INCLUDE_MACOS_X86` is set.

**Files:**
- Modify: `scripts/release`

**Acceptance Criteria:**
- [ ] `include_macos_x86` is parsed from `SWIFT_GODOT_INCLUDE_MACOS_X86` (default empty).
- [ ] `usage()` documents `SWIFT_GODOT_INCLUDE_MACOS_X86`.
- [ ] The build path always builds macOS arm64 into `$derived_data`, and builds x86_64 into `${derived_data}_x86` only when `include_macos_x86` is set.
- [ ] The `SKIP_BUILD` path validates the x86 prebuilt artifacts under `${derived_data}_x86` only when `include_macos_x86` is set.

**Verify:** `bash -n scripts/release` → no output, exit 0

**Steps:**

- [ ] **Step 1: Document and parse the env var**

In `usage()`, the env-var list ends with:
```bash
    echo "  SWIFT_GODOT_NODEPLOY          Build the xcframework but skip GitHub release publishing"
```
Add a line after it:
```bash
    echo "  SWIFT_GODOT_NODEPLOY          Build the xcframework but skip GitHub release publishing"
    echo "  SWIFT_GODOT_INCLUDE_MACOS_X86 Also build a macOS x86_64 (Intel) slice"
```

The variable-parsing block currently ends with:
```bash
configuration=${SWIFT_GODOT_CONFIGURATION:-Release}
```
Add a line after it:
```bash
configuration=${SWIFT_GODOT_CONFIGURATION:-Release}
include_macos_x86=${SWIFT_GODOT_INCLUDE_MACOS_X86:-}
```

- [ ] **Step 2: Swap the macOS build path**

In the build path (inside `if [[ -z "${SWIFT_GODOT_SKIP_BUILD:-}" ]]`), this block currently builds x86_64 unconditionally and arm64 only on an arm64 host:
```bash
    build_distribution_products \
        "platform=macOS,arch=x86_64" \
        "$derived_data" \
        "$build_dir/generated-x86_64" \
        "$build_dir/distribution-x86_64" \
        "$build_dir/x86_64.log"

    if [[ "$arch" = "arm64" ]]; then
        build_distribution_products \
            "platform=macOS,arch=arm64" \
            "${derived_data}_arm" \
            "$build_dir/generated-arm64" \
            "$build_dir/distribution-arm64" \
            "$build_dir/arm64.log"
    fi
```
Replace it with arm64-always (primary) and x86_64-optional:
```bash
    build_distribution_products \
        "platform=macOS,arch=arm64" \
        "$derived_data" \
        "$build_dir/generated-arm64" \
        "$build_dir/distribution-arm64" \
        "$build_dir/arm64.log"

    if [[ -n "$include_macos_x86" ]]; then
        build_distribution_products \
            "platform=macOS,arch=x86_64" \
            "${derived_data}_x86" \
            "$build_dir/generated-x86_64" \
            "$build_dir/distribution-x86_64" \
            "$build_dir/x86_64.log"
    fi
```

- [ ] **Step 3: Swap the `SKIP_BUILD` x86 validation**

In the `SKIP_BUILD` branch, the artifacts under the unsuffixed `$derived_data`
are now the arm64 (primary) products and stay validated unconditionally — those
`require_prebuilt_artifact` lines do not change. The conditional block currently
reads:
```bash
    if [[ "$arch" = "arm64" ]]; then
        require_prebuilt_artifact "${derived_data}_arm/Build/Products/$configuration/PackageFrameworks/SwiftGodot.framework"
        require_prebuilt_artifact "${derived_data}_arm/Build/Products/$configuration/PackageFrameworks/SwiftGodotRuntime.framework"
        require_prebuilt_artifact "${derived_data}_arm/Build/Products/$configuration/SwiftGodot.swiftmodule"
        require_prebuilt_artifact "${derived_data}_arm/Build/Products/$configuration/SwiftGodotRuntime.swiftmodule"
        require_prebuilt_artifact "${derived_data}_arm/Build/Intermediates.noindex/GeneratedModuleMaps/SwiftGodot.modulemap"
        require_prebuilt_artifact "${derived_data}_arm/Build/Intermediates.noindex/GeneratedModuleMaps/SwiftGodot-Swift.h"
        require_prebuilt_artifact "${derived_data}_arm/Build/Intermediates.noindex/GeneratedModuleMaps/SwiftGodotRuntime.modulemap"
        require_prebuilt_artifact "${derived_data}_arm/Build/Intermediates.noindex/GeneratedModuleMaps/SwiftGodotRuntime-Swift.h"
    fi
```
Replace it (condition `arch` → `include_macos_x86`, paths `_arm` → `_x86`):
```bash
    if [[ -n "$include_macos_x86" ]]; then
        require_prebuilt_artifact "${derived_data}_x86/Build/Products/$configuration/PackageFrameworks/SwiftGodot.framework"
        require_prebuilt_artifact "${derived_data}_x86/Build/Products/$configuration/PackageFrameworks/SwiftGodotRuntime.framework"
        require_prebuilt_artifact "${derived_data}_x86/Build/Products/$configuration/SwiftGodot.swiftmodule"
        require_prebuilt_artifact "${derived_data}_x86/Build/Products/$configuration/SwiftGodotRuntime.swiftmodule"
        require_prebuilt_artifact "${derived_data}_x86/Build/Intermediates.noindex/GeneratedModuleMaps/SwiftGodot.modulemap"
        require_prebuilt_artifact "${derived_data}_x86/Build/Intermediates.noindex/GeneratedModuleMaps/SwiftGodot-Swift.h"
        require_prebuilt_artifact "${derived_data}_x86/Build/Intermediates.noindex/GeneratedModuleMaps/SwiftGodotRuntime.modulemap"
        require_prebuilt_artifact "${derived_data}_x86/Build/Intermediates.noindex/GeneratedModuleMaps/SwiftGodotRuntime-Swift.h"
    fi
```

- [ ] **Step 4: Verify**

Run: `bash -n scripts/release`
Expected: no output, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/release
git commit -m "feat: make macOS x86_64 opt-in in release script"
```

---

### Task 4: Make the macro artifact bundle x86_64 opt-in

**Goal:** `build-macro-artifactbundle` builds an arm64-only plugin by default and a universal plugin when `SWIFT_GODOT_INCLUDE_MACOS_X86` is set; the PR-coverage step in `swift.yml` keeps exercising the universal build.

**Files:**
- Modify: `scripts/build-macro-artifactbundle`
- Modify: `.github/workflows/swift.yml`

**Acceptance Criteria:**
- [ ] `build-macro-artifactbundle` parses `SWIFT_GODOT_INCLUDE_MACOS_X86` (default empty).
- [ ] When set: `swift build --arch arm64 --arch x86_64`, validates a universal binary, `info.json` lists both triples.
- [ ] When unset: `swift build --arch arm64`, validates an arm64 binary, `info.json` lists only `arm64-apple-macosx`.
- [ ] The `swift.yml` macro step sets `SWIFT_GODOT_INCLUDE_MACOS_X86: 1`.

**Verify:** `bash -n scripts/build-macro-artifactbundle` → exit 0; `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/swift.yml'))"` → exit 0

**Steps:**

- [ ] **Step 1: Parse the env var**

In `scripts/build-macro-artifactbundle`, the argument parsing currently reads:
```bash
output_dir=$1
version=$2

mkdir -p "$output_dir"
```
Add the env-var line:
```bash
output_dir=$1
version=$2
include_macos_x86=${SWIFT_GODOT_INCLUDE_MACOS_X86:-}

mkdir -p "$output_dir"
```

- [ ] **Step 2: Build with conditional architectures**

The build block currently reads:
```bash
echo "Building SwiftGodotMacroLibrary universal (arm64 + x86_64)..."
(
    cd "$scratch/MacroBuilder"
    swift build \
        -c release \
        --arch arm64 \
        --arch x86_64 \
        --product SwiftGodotMacroLibrary
)
```
Replace it with:
```bash
build_archs=(--arch arm64)
if [[ -n "$include_macos_x86" ]]; then
    build_archs+=(--arch x86_64)
    echo "Building SwiftGodotMacroLibrary universal (arm64 + x86_64)..."
else
    echo "Building SwiftGodotMacroLibrary (arm64)..."
fi
(
    cd "$scratch/MacroBuilder"
    swift build \
        -c release \
        "${build_archs[@]}" \
        --product SwiftGodotMacroLibrary
)
```

- [ ] **Step 3: Validate the built binary conditionally**

The validation block currently reads:
```bash
arch_info=$(lipo -info "$plugin_bin")
echo "$arch_info"
if ! echo "$arch_info" | grep -qE "(x86_64.*arm64|arm64.*x86_64)"; then
    echo "Plugin is not a universal binary (expected arm64 + x86_64)." >&2
    exit 1
fi
```
Replace it with:
```bash
arch_info=$(lipo -info "$plugin_bin")
echo "$arch_info"
if [[ -n "$include_macos_x86" ]]; then
    if ! echo "$arch_info" | grep -qE "(x86_64.*arm64|arm64.*x86_64)"; then
        echo "Plugin is not a universal binary (expected arm64 + x86_64)." >&2
        exit 1
    fi
else
    if ! echo "$arch_info" | grep -q "arm64"; then
        echo "Plugin is not an arm64 binary." >&2
        exit 1
    fi
fi
```

- [ ] **Step 4: Write conditional `supportedTriples` into `info.json`**

The `info.json` heredoc currently contains:
```bash
cat > "$bundle_root/info.json" <<EOF
{
  "schemaVersion": "1.0",
  "artifacts": {
    "SwiftGodotMacroLibrary": {
      "type": "executable",
      "version": "$version",
      "variants": [
        {
          "path": "SwiftGodotMacroLibrary-macos/bin/SwiftGodotMacroLibrary",
          "supportedTriples": [
            "arm64-apple-macosx",
            "x86_64-apple-macosx"
          ]
        }
      ]
    }
  }
}
EOF
```
Immediately before that `cat`, add a block that builds the triples list, and
replace the two hard-coded triple lines with the variable:
```bash
if [[ -n "$include_macos_x86" ]]; then
    supported_triples='"arm64-apple-macosx",
            "x86_64-apple-macosx"'
else
    supported_triples='"arm64-apple-macosx"'
fi

cat > "$bundle_root/info.json" <<EOF
{
  "schemaVersion": "1.0",
  "artifacts": {
    "SwiftGodotMacroLibrary": {
      "type": "executable",
      "version": "$version",
      "variants": [
        {
          "path": "SwiftGodotMacroLibrary-macos/bin/SwiftGodotMacroLibrary",
          "supportedTriples": [
            $supported_triples
          ]
        }
      ]
    }
  }
}
EOF
```

- [ ] **Step 5: Update the `usage()` text**

The `usage()` heredoc opens with:
```
Builds SwiftGodotMacroLibrary as a universal macOS (arm64 + x86_64)
compiler-plugin executable and packages it as a SwiftPM artifact bundle
named SwiftGodotMacros.artifactbundle.zip in <output_dir>.
```
Replace those three lines with:
```
Builds SwiftGodotMacroLibrary as a macOS compiler-plugin executable and
packages it as a SwiftPM artifact bundle named
SwiftGodotMacros.artifactbundle.zip in <output_dir>. The plugin is arm64-only
by default; set SWIFT_GODOT_INCLUDE_MACOS_X86=1 to build a universal
(arm64 + x86_64) plugin.
```

- [ ] **Step 6: Exercise the universal build in `swift.yml`**

In `.github/workflows/swift.yml` the macro step currently reads:
```yaml
    - name: Build macro artifact bundle (exercise release script)
      run: scripts/build-macro-artifactbundle "$RUNNER_TEMP/sg-macro-artifact" "0.0.0-ci"
```
Add an `env:` block so it keeps covering the universal build path:
```yaml
    - name: Build macro artifact bundle (exercise release script)
      env:
        SWIFT_GODOT_INCLUDE_MACOS_X86: 1
      run: scripts/build-macro-artifactbundle "$RUNNER_TEMP/sg-macro-artifact" "0.0.0-ci"
```

- [ ] **Step 7: Verify**

Run: `bash -n scripts/build-macro-artifactbundle`
Expected: no output, exit 0.

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/swift.yml'))"`
Expected: no output, exit 0.

- [ ] **Step 8: Commit**

```bash
git add scripts/build-macro-artifactbundle .github/workflows/swift.yml
git commit -m "feat: make macro artifact bundle x86_64 opt-in"
```

---

## Self-Review Notes

- **Spec coverage:** Spec §1 (release.yml) → Task 2; §2 (make-swiftgodot-framework) → Task 1; §3 (scripts/release) → Task 3; §4 (build-macro-artifactbundle) + the `swift.yml` coverage step → Task 4. "Out of scope" confirms no `binaries.json`/`Package.swift`/test-script changes — none are in the plan.
- **Type consistency:** The variable name `include_macos_x86`, env var `SWIFT_GODOT_INCLUDE_MACOS_X86`, directory suffix `_x86` / `${DERIVED_DATA}_x86` / `${derived_data}_x86`, and the framework variable `bd_mac_x86` are used consistently across all tasks. The arm64 build is always staged into the unsuffixed `$DERIVED_DATA` / `$derived_data`; x86_64 always into the `_x86` sidecar.
- **Ordering:** The four tasks edit disjoint files (Task 2 and Task 4 both touch `.github/workflows/` but different files) and have no code dependency on each other; they may be implemented in any order. The PR as a whole is internally consistent.
- **Boolean-input pitfall:** Task 2 maps the boolean input via `${{ inputs.include_macos_x86 && '1' || '' }}` so the off case yields an empty string, which the presence-based `[[ -n ... ]]` checks in Tasks 3 and 4 correctly read as "off" (a literal `"false"` string would read as "on").
