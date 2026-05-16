# Merge SwiftGodotRuntime into SwiftGodot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the standalone `SwiftGodotRuntime` Swift module by folding it into `SwiftGodot`, so the shipped `SwiftGodot.xcframework` is self-contained and a consumer that only `import SwiftGodot`s no longer fails with `unable to resolve module dependency: 'SwiftGodotRuntime'`.

**Architecture:** `SwiftGodotRuntime` exists today only as a separate SwiftPM target whose symbols `SwiftGodot` re-exports via `@_exported import SwiftGodotRuntime`. That re-export leaks the module name into `SwiftGodot`'s `.swiftinterface`. The fix merges the two targets into one `SwiftGodot` target: runtime source moves under `Sources/SwiftGodot/Runtime/`, the code generator emits builtins + runtime classes + the rest of the API into a single module with no import preamble, and the macro library / generator stop emitting `SwiftGodotRuntime.`-qualified references. The release pipeline drops everything that staged a second module.

**Tech Stack:** Swift 6 / SwiftPM, Xcode `xcodebuild`, `swift-syntax` macros, bash release scripts, GitHub Actions.

---

## Background / Context

The split into `SwiftGodot` + `SwiftGodotRuntime` was scaffolding for a future multi-module split (see the unused `SwiftGodotCore`/`SwiftGodotControls`/... cases in `Plugins/CodeGeneratorPlugin/plugin.swift`). Today `SwiftGodot` already generates the *entire* API surface; `SwiftGodotRuntime` is the only genuinely separate module, and `SwiftGodot` simply re-exports it. Commit `cec3201` (#18) already decided the runtime ships only inside `SwiftGodot.xcframework`. This plan finishes that direction by removing the module boundary entirely.

**Module split today:**
- `SwiftGodotRuntime` target: hand-written core (`Sources/SwiftGodotRuntime/`), generates `knownBuiltin` builtins + the `runtime` class set. Carries extra unsafe flags (`-conditional-runtime-records`, `-internalize-at-link`, `-lto=llvm-full`). Uses plugins `CodeGeneratorPlugin` + `SwiftGodotMacroLibrary`.
- `SwiftGodot` target: hand-written API layer (`Sources/SwiftGodot/`), generates the rest of the classes, `@_exported import SwiftGodotRuntime`. Uses plugin `CodeGeneratorPlugin`.

**After the merge:** one `SwiftGodot` target containing all hand-written source and generating builtins + every class, no preamble import, carrying the union of build flags and plugins.

**Source filename collisions** when merging directories — runtime files are moved under a new `Runtime/` subdirectory to sidestep all of them (`GodotInterface.swift` and `Extensions/GDUtilityFunctions.swift` exist in both trees).

---

## File Structure

Files created / moved / modified:

- Move: `Sources/SwiftGodotRuntime/**` (except `_generated/`) → `Sources/SwiftGodot/Runtime/**`
- Delete: `Sources/SwiftGodot/SwiftGodotExports.swift`, `Sources/SwiftGodotRuntime/` (entire directory)
- Modify: `Package.swift`, `Package.distribution.swift` — drop the `SwiftGodotRuntime` target and its products
- Modify: `Plugins/CodeGeneratorPlugin/plugin.swift` — `SwiftGodot` config absorbs runtime, drop `SwiftGodotRuntime` case
- Modify: `Generator/Generator/TypeHelpers.swift`, `Generator/Generator/BuiltinGen.swift` — stop emitting `SwiftGodotRuntime.`
- Modify: `Sources/SwiftGodotMacroLibrary/{MacroExport,MacroCallable,MacroGodot}.swift` — emit `SwiftGodot.` instead of `SwiftGodotRuntime.`
- Modify: `Tests/SwiftGodotMacrosTests/Resources/*.swift` (68 fixtures) — `SwiftGodotRuntime.` → `SwiftGodot.`
- Modify: `Tests/SwiftGodotTestExtension/{WrappedTests,TestObjectCleanup,MarshalTests,MacroIntegrationTests}.swift`
- Modify: `Sources/SwiftGodotTestRunner/SwiftGodotTestRunner.swift`
- Modify: `scripts/build-distribution-products`, `scripts/release`, `scripts/make-swiftgodot-framework`, `scripts/test-make-swiftgodot-framework`
- Modify: `.github/workflows/release.yml`, `README.md`, `.gitignore`

---

## Task 1: Relocate runtime source into the SwiftGodot target

**Goal:** Move all hand-written `SwiftGodotRuntime` source under `Sources/SwiftGodot/Runtime/` and remove every in-source reference to the `SwiftGodotRuntime` module, with the package still in a state where the manifest (Task 2) can compile it.

**Files:**
- Move: `Sources/SwiftGodotRuntime/*` → `Sources/SwiftGodot/Runtime/`
- Delete: `Sources/SwiftGodot/SwiftGodotExports.swift`
- Modify: `Sources/SwiftGodot/GodotInterface.swift:7`
- Modify: `Sources/SwiftGodot/Extensions/NodeExtensions.swift:7`
- Modify: `Sources/SwiftGodot/VariantConvertibeNode.swift`
- Modify: `.gitignore:22-25`

**Acceptance Criteria:**
- [ ] `Sources/SwiftGodotRuntime/` no longer exists.
- [ ] All hand-written runtime `.swift` files live under `Sources/SwiftGodot/Runtime/`.
- [ ] No `.swift` file under `Sources/SwiftGodot/` contains `import SwiftGodotRuntime`.
- [ ] `Sources/SwiftGodot/VariantConvertibeNode.swift` no longer contains the `SwiftGodotRuntime.` qualifier.
- [ ] `.gitignore` references `Sources/SwiftGodot/_generated` only.

**Verify:** `! grep -rn "import SwiftGodotRuntime" Sources/ && ! test -d Sources/SwiftGodotRuntime && echo OK` → prints `OK`

**Steps:**

- [ ] **Step 1: Move the runtime source tree (excluding generated output)**

```bash
mkdir -p Sources/SwiftGodot/Runtime
# Move every tracked runtime source file/dir except the generated-output folder.
for entry in Sources/SwiftGodotRuntime/*; do
    name=$(basename "$entry")
    [[ "$name" == "_generated" ]] && continue
    git mv "$entry" "Sources/SwiftGodot/Runtime/$name"
done
# Drop the now-empty runtime directory (only _generated placeholder remains).
git rm -r --ignore-unmatch Sources/SwiftGodotRuntime/_generated/.gitkeep
rm -rf Sources/SwiftGodotRuntime
```

- [ ] **Step 2: Delete the re-export shim file**

`Sources/SwiftGodot/SwiftGodotExports.swift` contains exactly one line (`@_exported import SwiftGodotRuntime`). Remove it:

```bash
git rm Sources/SwiftGodot/SwiftGodotExports.swift
```

- [ ] **Step 3: Remove the SPI import lines**

In `Sources/SwiftGodot/GodotInterface.swift`, delete line 7:

```swift
@_spi(SwiftGodotRuntimePrivate) import SwiftGodotRuntime
```

In `Sources/SwiftGodot/Extensions/NodeExtensions.swift`, delete line 7:

```swift
@_spi(SwiftGodotRuntimePrivate) import SwiftGodotRuntime
```

(The runtime files moved in Step 1 may also carry `@_spi(SwiftGodotRuntimePrivate) import SwiftGodotRuntime` — none do per audit, but if any are found, delete those lines too. The `@_spi(SwiftGodotRuntimePrivate)` *declaration* attributes stay; they only label SPI within the merged module.)

- [ ] **Step 4: Drop the `SwiftGodotRuntime.` qualifier in VariantConvertibeNode.swift**

`Sources/SwiftGodot/VariantConvertibeNode.swift` references `SwiftGodotRuntime.PropertyHint`, `SwiftGodotRuntime.PropertyUsageFlags`, `SwiftGodotRuntime.PropInfo`. Those types are now in the same module — strip the module qualifier:

```bash
sed -i '' 's/SwiftGodotRuntime\.//g' Sources/SwiftGodot/VariantConvertibeNode.swift
```

Confirm the file still reads sensibly (the affected lines become `hint: PropertyHint?`, `usage: PropertyUsageFlags?`, `-> PropInfo`, `return PropInfo(`).

- [ ] **Step 5: Update `.gitignore`**

Replace the four generated-output lines (currently lines 22-25):

```
Sources/SwiftGodotRuntime/_generated/*
!Sources/SwiftGodotRuntime/_generated/.gitkeep
Sources/SwiftGodot/_generated/*
!Sources/SwiftGodot/_generated/.gitkeep
```

with just:

```
Sources/SwiftGodot/_generated/*
!Sources/SwiftGodot/_generated/.gitkeep
```

- [ ] **Step 6: Verify and commit**

```bash
grep -rn "import SwiftGodotRuntime" Sources/   # expect no output
test -d Sources/SwiftGodotRuntime && echo FAIL || echo OK
git add -A
git commit -m "Relocate SwiftGodotRuntime source into the SwiftGodot target"
```

---

## Task 2: Merge the targets in Package.swift

**Goal:** Make `SwiftGodot` a single self-contained target in the development manifest and remove the `SwiftGodotRuntime` target and products.

**Files:**
- Modify: `Package.swift` (products block ~lines 9-30, targets block ~lines 196-228)

**Acceptance Criteria:**
- [ ] `Package.swift` has no `SwiftGodotRuntime` target.
- [ ] `Package.swift` has no `SwiftGodotRuntime` / `SwiftGodotRuntimeStatic` product.
- [ ] The `SwiftGodot` target depends only on `GDExtension`, uses plugins `CodeGeneratorPlugin` + `SwiftGodotMacroLibrary`, and carries the union of build flags from both former targets.

**Verify:** `swift package dump-package > /dev/null && echo OK` → prints `OK`

**Steps:**

- [ ] **Step 1: Remove the `SwiftGodotRuntime` and `SwiftGodotRuntimeStatic` products**

In the `products` array (top of `Package.swift`), delete the `.library(name: "SwiftGodotRuntime", ...)` and `.library(name: "SwiftGodotRuntimeStatic", ...)` entries. Keep `SwiftGodot` and `SwiftGodotStatic`.

- [ ] **Step 2: Delete the `SwiftGodotRuntime` target**

Remove the entire `.target(name: "SwiftGodotRuntime", ...)` block (the one with the "core runtime" comment).

- [ ] **Step 3: Update the `SwiftGodot` target**

Replace the `.target(name: "SwiftGodot", ...)` block with:

```swift
    // The full SwiftGodot API: hand-written core + the generated Godot API,
    // all in one module. The release build stages CodeGeneratorPlugin output
    // into Sources/SwiftGodot/_generated/ inside a temporary package.
    .target(
        name: "SwiftGodot",
        dependencies: ["GDExtension"],
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
```

- [ ] **Step 4: Verify the manifest parses**

```bash
swift package dump-package > /dev/null && echo OK
```

- [ ] **Step 5: Commit**

```bash
git add Package.swift
git commit -m "Merge SwiftGodotRuntime target into SwiftGodot in Package.swift"
```

---

## Task 3: Merge the targets in Package.distribution.swift

**Goal:** Apply the same target/product merge to the release manifest.

**Files:**
- Modify: `Package.distribution.swift`

**Acceptance Criteria:**
- [ ] No `SwiftGodotRuntime` target or product remains.
- [ ] The `SwiftGodot` target depends only on `GDExtension` and carries the union of build flags.

**Verify:** `cp Package.swift /tmp/pkg.bak && cp Package.distribution.swift Package.swift && swift package dump-package > /dev/null && echo OK; cp /tmp/pkg.bak Package.swift`

**Steps:**

- [ ] **Step 1: Remove the `SwiftGodotRuntime` and `SwiftGodotRuntimeStatic` products**

In the `products` array, delete the `.library(name: "SwiftGodotRuntime", type: .dynamic, ...)` and `.library(name: "SwiftGodotRuntimeStatic", ...)` entries. Keep `SwiftGodot` (`.dynamic`) and `SwiftGodotStatic`.

- [ ] **Step 2: Delete the `SwiftGodotRuntime` target**

Remove the entire `.target(name: "SwiftGodotRuntime", ...)` block.

- [ ] **Step 3: Update the `SwiftGodot` target**

Replace the `.target(name: "SwiftGodot", ...)` block with:

```swift
        // The full SwiftGodot API in one module. The release build stages
        // CodeGeneratorPlugin output into Sources/SwiftGodot/_generated/
        // inside this temporary package.
        .target(
            name: "SwiftGodot",
            dependencies: ["GDExtension"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .define("CUSTOM_BUILTIN_IMPLEMENTATIONS"),
                .define("SWIFTGODOT_WITH_MULTI_PROCESS", .when(traits: [withMultiProcessTrait])),
                .unsafeFlags(
                    [
                        "-enable-library-evolution",
                        "-suppress-warnings",
                        "-Xfrontend", "-conditional-runtime-records",
                        "-Xfrontend", "-internalize-at-link",
                        "-Xfrontend", "-lto=llvm-full",
                    ]
                ),
            ]
        ),
```

(`Package.distribution.swift` declares no `plugins:` — generated sources are pre-staged into `_generated/` and committed into the temporary package by `scripts/build-distribution-products`.)

- [ ] **Step 4: Verify and commit**

```bash
cp Package.swift /tmp/pkg.bak
cp Package.distribution.swift Package.swift
swift package dump-package > /dev/null && echo OK
cp /tmp/pkg.bak Package.swift
git add Package.distribution.swift
git commit -m "Merge SwiftGodotRuntime target into SwiftGodot in the distribution manifest"
```

---

## Task 4: Collapse the code generator plugin config

**Goal:** Make the `CodeGeneratorPlugin` generate builtins + every class into the single `SwiftGodot` target with no import preamble, and remove the `SwiftGodotRuntime` target case.

**Files:**
- Modify: `Plugins/CodeGeneratorPlugin/plugin.swift`

**Acceptance Criteria:**
- [ ] `generationConfig(for:)` returns, for `"SwiftGodot"`, a config whose `classFiles` is `runtime + core + controls + threeD + gltf + twoD + xr + editor + visualShaderNodes` (uniqued), `builtinFiles` is `knownBuiltin`, `preamble` is `nil`.
- [ ] The `case "SwiftGodotRuntime"` is removed.
- [ ] No string literal in `plugin.swift` emits `import SwiftGodotRuntime`.

**Verify:** `! grep -n "import SwiftGodotRuntime" Plugins/CodeGeneratorPlugin/plugin.swift && echo OK`

**Steps:**

- [ ] **Step 1: Replace the `SwiftGodot` and `SwiftGodotRuntime` cases**

In `generationConfig(for:)`, delete the whole `case "SwiftGodotRuntime":` block, and replace the `case "SwiftGodot":` block with:

```swift
        // SwiftGodot is a single self-contained module: it generates the
        // builtins and every class, with no dependency on another module.
        case "SwiftGodot":
            return GenerationConfig(
                classFiles: (runtime + core + controls + threeD + gltf + twoD + xr + editor + visualShaderNodes).uniqued(),
                builtinFiles: knownBuiltin,
                preamble: nil,
                allowedClassFallbacks: []
            )
```

Leave the `SwiftGodotCore` / `SwiftGodotControls` / ... cases unchanged — they remain dormant scaffolding for a future split and are not built by any current target.

- [ ] **Step 2: Verify no import preamble remains**

```bash
grep -n "import SwiftGodotRuntime" Plugins/CodeGeneratorPlugin/plugin.swift   # expect no output
```

The `SwiftGodotCore` case still contains `@_exported import SwiftGodotRuntime` text — that case is unused; leave it. The check above must show no hits *outside* the `SwiftGodotCore` block. If it shows the `SwiftGodotCore` lines only, that is acceptable; if it shows lines inside the `SwiftGodot` case, fix them.

- [ ] **Step 3: Commit**

```bash
git add Plugins/CodeGeneratorPlugin/plugin.swift
git commit -m "Generate builtins and all classes into the single SwiftGodot module"
```

---

## Task 5: Stop the generator emitting `SwiftGodotRuntime.`-qualified code

**Goal:** Generated Swift no longer module-qualifies symbols with `SwiftGodotRuntime`, since that module no longer exists.

**Files:**
- Modify: `Generator/Generator/TypeHelpers.swift:346`
- Modify: `Generator/Generator/BuiltinGen.swift:623-624`

**Acceptance Criteria:**
- [ ] `Generator/` emits no `SwiftGodotRuntime.`-qualified type references.
- [ ] `@_spi(SwiftGodotRuntimePrivate)` attributes in `ClassGen.swift` / `UnsafePointerHelpers.swift` are left intact (SPI group label, valid within one module).

**Verify:** `! grep -rn 'SwiftGodotRuntime\.' Generator/ && echo OK`

**Steps:**

- [ ] **Step 1: Fix the qualified `Variant.GType` reference**

In `Generator/Generator/TypeHelpers.swift` line 346, change:

```swift
            return "SwiftGodotRuntime.Variant.GType"
```

to:

```swift
            return "Variant.GType"
```

- [ ] **Step 2: Update the stale module-split comment**

In `Generator/Generator/BuiltinGen.swift` lines 623-624, the comment currently reads:

```swift
    // - SwiftGodotRuntime: emits builtin sources
    // - SwiftGodot (and split targets): imports SwiftGodotRuntime and emits only classes
```

Replace with a comment that matches the merged reality, e.g.:

```swift
    // SwiftGodot is a single module: it emits both builtin sources and classes.
```

(Read the surrounding lines first; keep the comment consistent with the conditional it documents. If the conditional itself branched on a module distinction that no longer exists, simplify it accordingly — but only the comment is required to change for correctness.)

- [ ] **Step 3: Verify and commit**

```bash
grep -rn 'SwiftGodotRuntime\.' Generator/   # expect no output
git add Generator/
git commit -m "Stop the generator emitting SwiftGodotRuntime-qualified references"
```

---

## Task 6: Update the macro library to emit `SwiftGodot.`

**Goal:** Macro expansions reference `SwiftGodot.*` instead of `SwiftGodotRuntime.*`, so generated user code resolves against the merged module.

**Files:**
- Modify: `Sources/SwiftGodotMacroLibrary/MacroExport.swift`
- Modify: `Sources/SwiftGodotMacroLibrary/MacroCallable.swift`
- Modify: `Sources/SwiftGodotMacroLibrary/MacroGodot.swift`

**Acceptance Criteria:**
- [ ] No file under `Sources/SwiftGodotMacroLibrary/` emits the string `SwiftGodotRuntime.`.
- [ ] Every former `SwiftGodotRuntime.X` reference now reads `SwiftGodot.X`.

**Verify:** `! grep -rn 'SwiftGodotRuntime' Sources/SwiftGodotMacroLibrary/ && echo OK`

**Steps:**

- [ ] **Step 1: Replace the module qualifier in all three files**

```bash
sed -i '' 's/SwiftGodotRuntime\./SwiftGodot./g' \
    Sources/SwiftGodotMacroLibrary/MacroExport.swift \
    Sources/SwiftGodotMacroLibrary/MacroCallable.swift \
    Sources/SwiftGodotMacroLibrary/MacroGodot.swift
```

- [ ] **Step 2: Verify**

```bash
grep -rn 'SwiftGodotRuntime' Sources/SwiftGodotMacroLibrary/   # expect no output
```

- [ ] **Step 3: Commit**

```bash
git add Sources/SwiftGodotMacroLibrary/
git commit -m "Emit SwiftGodot-qualified references from the macro library"
```

---

## Task 7: Update the macro test fixtures

**Goal:** The 68 expected macro-expansion fixtures match the new `SwiftGodot.`-qualified output.

**Files:**
- Modify: `Tests/SwiftGodotMacrosTests/Resources/*.swift` (every fixture containing `SwiftGodotRuntime.`)

**Acceptance Criteria:**
- [ ] No fixture under `Tests/SwiftGodotMacrosTests/Resources/` contains `SwiftGodotRuntime.`.

**Verify:** `! grep -rln 'SwiftGodotRuntime' Tests/SwiftGodotMacrosTests/Resources/ && echo OK`

**Steps:**

- [ ] **Step 1: Rewrite the qualifier across all fixtures**

```bash
grep -rl 'SwiftGodotRuntime\.' Tests/SwiftGodotMacrosTests/Resources/ \
    | while IFS= read -r f; do
        sed -i '' 's/SwiftGodotRuntime\./SwiftGodot./g' "$f"
    done
```

- [ ] **Step 2: Verify**

```bash
grep -rln 'SwiftGodotRuntime' Tests/SwiftGodotMacrosTests/Resources/   # expect no output
```

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiftGodotMacrosTests/Resources/
git commit -m "Update macro expansion fixtures for the merged SwiftGodot module"
```

---

## Task 8: Update test targets and the test runner

**Goal:** Test sources import / reference `SwiftGodot` instead of `SwiftGodotRuntime`, and the test runner stops listing the removed product.

**Files:**
- Modify: `Tests/SwiftGodotTestExtension/WrappedTests.swift:10`
- Modify: `Tests/SwiftGodotTestExtension/TestObjectCleanup.swift:2`
- Modify: `Tests/SwiftGodotTestExtension/MarshalTests.swift:3`
- Modify: `Tests/SwiftGodotTestExtension/MacroIntegrationTests.swift`
- Modify: `Sources/SwiftGodotTestRunner/SwiftGodotTestRunner.swift:54,95`

**Acceptance Criteria:**
- [ ] No `import SwiftGodotRuntime` (plain, `@testable`, or `@_spi(...)`-prefixed) remains in `Tests/`.
- [ ] `MacroIntegrationTests.swift` references `SwiftGodot.FastVariant`, not `SwiftGodotRuntime.FastVariant`.
- [ ] `SwiftGodotTestRunner.swift` no longer lists `"SwiftGodotRuntime"` in its product/library arrays.

**Verify:** `! grep -rn 'SwiftGodotRuntime' Tests/ Sources/SwiftGodotTestRunner/ && echo OK`

**Steps:**

- [ ] **Step 1: Fix the test-extension imports**

`WrappedTests.swift` line 10 — `@_spi(SwiftGodotRuntimePrivate) import SwiftGodotRuntime` becomes:

```swift
@_spi(SwiftGodotRuntimePrivate) import SwiftGodot
```

`TestObjectCleanup.swift` line 2 — `@_spi(SwiftGodotRuntimePrivate) @testable import SwiftGodotRuntime` becomes:

```swift
@_spi(SwiftGodotRuntimePrivate) @testable import SwiftGodot
```

`MarshalTests.swift` line 3 — `@testable import SwiftGodotRuntime` becomes:

```swift
@testable import SwiftGodot
```

If a file ends up with two identical `import SwiftGodot` lines (because it already imported `SwiftGodot`), delete the duplicate, keeping the one with the widest attributes (`@_spi`/`@testable`).

- [ ] **Step 2: Fix the qualified references in MacroIntegrationTests.swift**

```bash
sed -i '' 's/SwiftGodotRuntime\./SwiftGodot./g' Tests/SwiftGodotTestExtension/MacroIntegrationTests.swift
```

- [ ] **Step 3: Drop the removed product from the test runner**

In `Sources/SwiftGodotTestRunner/SwiftGodotTestRunner.swift`, lines 54 and 95 currently read:

```swift
        let products = [extensionTarget, "SwiftGodot", "SwiftGodotRuntime"]
```
```swift
        let libraryNames = [extensionTarget, "SwiftGodot", "SwiftGodotRuntime"]
```

Remove the `"SwiftGodotRuntime"` element from both:

```swift
        let products = [extensionTarget, "SwiftGodot"]
```
```swift
        let libraryNames = [extensionTarget, "SwiftGodot"]
```

- [ ] **Step 4: Verify and commit**

```bash
grep -rn 'SwiftGodotRuntime' Tests/ Sources/SwiftGodotTestRunner/   # expect no output
git add Tests/ Sources/SwiftGodotTestRunner/
git commit -m "Point tests and the test runner at the merged SwiftGodot module"
```

---

## Task 9: Build and test the development package

**Goal:** Prove the merged package compiles and the existing test suite passes before touching the release pipeline.

**Files:** none (verification task)

**Acceptance Criteria:**
- [ ] `swift build` succeeds.
- [ ] `swift test` succeeds (in particular `SwiftGodotMacrosTests`, which exercises the updated fixtures).

**Verify:** `swift build && swift test`

**Steps:**

- [ ] **Step 1: Clean build**

```bash
swift build 2>&1 | tail -30
```

Expected: build completes with no errors. Common failure modes and fixes:
- `cannot find type 'X' in scope` in a moved runtime file → a missed `import SwiftGodotRuntime` removal or a still-qualified `SwiftGodotRuntime.X` reference; grep and fix.
- duplicate output file / duplicate filename → two source files with the same name in the same directory; the `Runtime/` subdirectory move (Task 1) should prevent this, but if it surfaces, rename or re-nest the offending file.

- [ ] **Step 2: Run the test suite**

```bash
swift test 2>&1 | tail -40
```

Expected: all tests pass. If `SwiftGodotMacrosTests` fails with a fixture diff, the macro library output (Task 6) and the fixture (Task 7) disagree — reconcile them so the fixture matches actual macro output exactly.

- [ ] **Step 3: Commit any fixes**

```bash
git add -A
git commit -m "Fix up merged-module build and test failures"
```

(If Steps 1-2 passed with no changes, skip the commit.)

---

## Task 10: Update the release framework scripts

**Goal:** The release pipeline scripts build, stage, and package only the single `SwiftGodot` module.

**Files:**
- Modify: `scripts/build-distribution-products`
- Modify: `scripts/release`
- Modify: `scripts/make-swiftgodot-framework`
- Modify: `scripts/test-make-swiftgodot-framework`

**Acceptance Criteria:**
- [ ] `scripts/build-distribution-products` stages only `Sources/SwiftGodot`, copies both `generated/` and `generated-builtin/` output into `Sources/SwiftGodot/_generated/`, and runs `xcodebuild` only for the `SwiftGodot` scheme.
- [ ] `scripts/release` (the `SWIFT_GODOT_SKIP_BUILD` branch) no longer requires `SwiftGodotRuntime` prebuilt artifacts.
- [ ] `scripts/make-swiftgodot-framework` no longer stages `SwiftGodotRuntime.swiftmodule` into the framework `Modules/` or as a sidecar.
- [ ] `scripts/test-make-swiftgodot-framework` no longer requires the `SwiftGodotRuntime.swiftmodule` token.

**Verify:** `bash -n scripts/build-distribution-products scripts/release scripts/make-swiftgodot-framework scripts/test-make-swiftgodot-framework && ! grep -ln 'SwiftGodotRuntime' scripts/build-distribution-products scripts/release scripts/make-swiftgodot-framework && echo OK`

**Steps:**

- [ ] **Step 1: `scripts/build-distribution-products` — Phase 1 staging**

In the `else` branch (non-prepared package), replace the generated-source discovery and staging. Currently it finds two generated dirs and stages two source trees. Change to a single module:

Replace:
```bash
    plugin_intermediates="$generation_derived_data/Build/Intermediates.noindex/BuildToolPluginIntermediates"
    runtime_gen_src=$(find "$plugin_intermediates" -type d \
        -path "*/SwiftGodotRuntime/CodeGeneratorPlugin/GeneratedSources/SwiftGodotRuntime" 2>/dev/null | head -1)
    swiftgodot_gen_src=$(find "$plugin_intermediates" -type d \
        -path "*/SwiftGodot/CodeGeneratorPlugin/GeneratedSources/SwiftGodot" 2>/dev/null | head -1)

    if [[ -z "$runtime_gen_src" || -z "$swiftgodot_gen_src" ]]; then
        echo "Error: Could not find CodeGeneratorPlugin output under $plugin_intermediates"
        exit 1
    fi

    echo "Staging temporary distribution package..."
    rm -rf "$release_package"
    mkdir -p "$release_package/Sources"
    cp Package.distribution.swift "$release_package/Package.swift"
    rsync -a --delete Sources/GDExtension "$release_package/Sources/"
    rsync -a --delete --exclude "_generated" Sources/SwiftGodotRuntime "$release_package/Sources/"
    rsync -a --delete --exclude "_generated" Sources/SwiftGodot "$release_package/Sources/"

    mkdir -p "$release_package/Sources/SwiftGodotRuntime/_generated"
    mkdir -p "$release_package/Sources/SwiftGodot/_generated"

    # SwiftGodotRuntime: copy both generated/ and generated-builtin/ output files.
    find "$runtime_gen_src" -name "*.swift" -exec cp {} "$release_package/Sources/SwiftGodotRuntime/_generated/" \;

    # SwiftGodot: copy generated/ only. Builtins are compiled by SwiftGodotRuntime.
    find "$swiftgodot_gen_src/generated" -name "*.swift" -exec cp {} "$release_package/Sources/SwiftGodot/_generated/" \;
```

with:
```bash
    plugin_intermediates="$generation_derived_data/Build/Intermediates.noindex/BuildToolPluginIntermediates"
    swiftgodot_gen_src=$(find "$plugin_intermediates" -type d \
        -path "*/SwiftGodot/CodeGeneratorPlugin/GeneratedSources/SwiftGodot" 2>/dev/null | head -1)

    if [[ -z "$swiftgodot_gen_src" ]]; then
        echo "Error: Could not find CodeGeneratorPlugin output under $plugin_intermediates"
        exit 1
    fi

    echo "Staging temporary distribution package..."
    rm -rf "$release_package"
    mkdir -p "$release_package/Sources"
    cp Package.distribution.swift "$release_package/Package.swift"
    rsync -a --delete Sources/GDExtension "$release_package/Sources/"
    rsync -a --delete --exclude "_generated" Sources/SwiftGodot "$release_package/Sources/"

    mkdir -p "$release_package/Sources/SwiftGodot/_generated"

    # SwiftGodot is a single module: copy both generated/ and generated-builtin/ output.
    find "$swiftgodot_gen_src" -name "*.swift" -exec cp {} "$release_package/Sources/SwiftGodot/_generated/" \;
```

- [ ] **Step 2: `scripts/build-distribution-products` — Phase 2 build**

In the Phase 2 block, delete the second `xcodebuild` invocation (`-scheme SwiftGodotRuntime`). Keep only the `-scheme SwiftGodot` invocation:

```bash
echo "Phase 2: building distribution products..."
(
    cd "$release_package"
    xcodebuild \
        -quiet \
        -scheme SwiftGodot \
        -destination "$destination" \
        -configuration "$configuration" \
        -derivedDataPath "$derived_data" \
        -archivePath "$archive_path" \
        "${build_settings[@]}"
)
```

- [ ] **Step 3: `scripts/release` — prebuilt-artifact checks**

In the `else` branch under `Using prebuilt DerivedData`, delete every `require_prebuilt_artifact` line that names `SwiftGodotRuntime` (the `PackageFrameworks/SwiftGodotRuntime.framework`, `SwiftGodotRuntime.swiftmodule`, `GeneratedModuleMaps*/SwiftGodotRuntime.modulemap`, and `GeneratedModuleMaps*/SwiftGodotRuntime-Swift.h` entries — for the macOS, macOS x86, iphoneos, and iphonesimulator sections). Keep all the `SwiftGodot.*` entries.

- [ ] **Step 4: `scripts/make-swiftgodot-framework` — drop runtime module staging**

In `stage_swiftgodot_metadata`, remove the block that stages the runtime swiftmodule:

```bash
    require_path "$product_dir/SwiftGodotRuntime.swiftmodule"
    rsync -a "$product_dir/SwiftGodotRuntime.swiftmodule" "$modules_dir/"

    if [[ -n "$secondary_product_dir" ]]; then
        require_path "$secondary_product_dir/SwiftGodotRuntime.swiftmodule"
        rsync -a "$secondary_product_dir/SwiftGodotRuntime.swiftmodule" "$modules_dir/"
    fi
```

After removal, `stage_swiftgodot_metadata` only needs `stage_module_metadata "SwiftGodot" ...` plus the `modules_dir` assignment if it is still referenced; if `modules_dir` becomes unused, delete that line too.

Then delete the `copy_runtime_module_sidecars` function definition entirely, and delete the `copy_runtime_module_sidecars "$output"` call at the end of the script.

Update the usage heredoc: the lines describing `SwiftGodotRuntime.swiftmodule` carried in `Modules/` are no longer true — replace with a sentence stating `SwiftGodot` is a single self-contained module.

- [ ] **Step 5: `scripts/test-make-swiftgodot-framework` — drop the runtime token**

In the `for required in ...` list, delete the `"SwiftGodotRuntime.swiftmodule"` line. The remaining tokens (`GeneratedModuleMaps`, `module-Swift.h`, `module.modulemap`, `stage_module_metadata "SwiftGodot"`, `merge_swift_headers`, `lipo -create`) stay.

- [ ] **Step 6: Verify syntax and commit**

```bash
bash -n scripts/build-distribution-products scripts/release scripts/make-swiftgodot-framework scripts/test-make-swiftgodot-framework && echo "syntax OK"
bash scripts/test-make-swiftgodot-framework && echo "framework script test OK"
git add scripts/
git commit -m "Drop SwiftGodotRuntime from the release framework scripts"
```

---

## Task 11: Update the release workflow and README

**Goal:** CI no longer packs `SwiftGodotRuntime` build products, and user-facing docs no longer advertise a `SwiftGodotRuntime` product.

**Files:**
- Modify: `.github/workflows/release.yml`
- Modify: `README.md`

**Acceptance Criteria:**
- [ ] `.github/workflows/release.yml` contains no `SwiftGodotRuntime` reference.
- [ ] `README.md` contains no `SwiftGodotRuntime` reference.

**Verify:** `! grep -rn 'SwiftGodotRuntime' .github/workflows/release.yml README.md && echo OK`

**Steps:**

- [ ] **Step 1: Remove runtime products from the `tar` commands**

In `.github/workflows/release.yml`, each "Pack release products" step `tar`s a product set. Delete the two `SwiftGodotRuntime` lines from each of the four `tar` invocations (around lines 191/193, 256/258, 322/324, 387/389):

```
            Build/Products/<Config>/PackageFrameworks/SwiftGodotRuntime.framework \
            Build/Products/<Config>/SwiftGodotRuntime.swiftmodule \
```

Keep the corresponding `SwiftGodot.framework` / `SwiftGodot.swiftmodule` / `GeneratedModuleMaps*` lines. Ensure the line that becomes the last argument of each `tar` still ends without a trailing backslash continuation error (the `GeneratedModuleMaps*` line is last in each list and already has no trailing `\`, so removing the runtime lines above it is safe).

- [ ] **Step 2: Remove the `SwiftGodotRuntime` row from README**

In `README.md`, delete the table row:

```
| `SwiftGodotRuntime` | Minimal runtime — core variant types, `Object`, `ClassDB`, `RefCounted` only |
```

and the sentence:

```
Use `SwiftGodotRuntime` when you want a smaller binary and don't need the full API surface.
```

Read the surrounding section first; if removing the row leaves a now-pointless products table or heading, tidy it so the section still reads coherently (e.g. if `SwiftGodot` is the only remaining product, a one-line description is enough).

- [ ] **Step 3: Verify and commit**

```bash
grep -rn 'SwiftGodotRuntime' .github/workflows/release.yml README.md   # expect no output
git add .github/workflows/release.yml README.md
git commit -m "Remove SwiftGodotRuntime from the release workflow and README"
```

---

## Task 12: Full release-build verification

**Goal:** Confirm the merged xcframework actually builds and is self-contained — its `SwiftGodot.swiftinterface` does not import `SwiftGodotRuntime`.

**Files:** none (verification task)

**Acceptance Criteria:**
- [ ] `scripts/release` runs to completion with `SWIFT_GODOT_NODEPLOY=1` (builds the xcframework, skips publishing).
- [ ] No `.swiftinterface` inside the produced `SwiftGodot.xcframework` contains `import SwiftGodotRuntime`.
- [ ] No `SwiftGodotRuntime.swiftmodule` directory exists anywhere inside the produced `SwiftGodot.xcframework`.

**Verify:** see Step 2 below.

**Steps:**

- [ ] **Step 1: Build the xcframework without deploying**

```bash
SWIFT_GODOT_NODEPLOY=1 SWIFT_GODOT_OUTPUT_DIR="$PWD/.build/release-verify" \
    scripts/release 0.0.0-merge-verify /dev/null "$(git rev-parse HEAD)" 2>&1 | tail -40
```

Expected: the script prints `Skipping deployment stage.` and exits 0. (`/dev/null` is accepted as the release-notes file only if it exists as a file — if the script rejects it, pass a small temp file: `echo notes > /tmp/notes.md` and use `/tmp/notes.md`.)

- [ ] **Step 2: Assert the xcframework is self-contained**

```bash
XC="$PWD/.build/release-verify/SwiftGodot.xcframework"
if grep -rln 'import SwiftGodotRuntime' "$XC" ; then
    echo "FAIL: interface still imports SwiftGodotRuntime"; exit 1
fi
if find "$XC" -name 'SwiftGodotRuntime.swiftmodule' | grep -q . ; then
    echo "FAIL: SwiftGodotRuntime.swiftmodule still bundled"; exit 1
fi
echo "OK: SwiftGodot.xcframework is self-contained"
```

Expected: prints `OK: SwiftGodot.xcframework is self-contained`.

- [ ] **Step 3: (Optional but recommended) consumer smoke test**

If a scratch consumer package is available, point a `binaryTarget` at the produced `SwiftGodot.xcframework`, add a source file containing `import SwiftGodot`, and run `xcodebuild`/`swift build`. It must compile without any `-I` workaround flag. Document the result in the PR description.

- [ ] **Step 4: Commit (if any fixes were needed)**

```bash
git add -A
git commit -m "Fixes from full release-build verification"
```

(Skip if Steps 1-2 passed cleanly with no changes.)

---

## Self-Review Notes

- **Spec coverage:** Bug report "suggested fix 1" (make `SwiftGodot` self-contained / no `@_exported import` of a distinct module) — Tasks 1-9 remove the module boundary; Task 12 asserts the interface no longer imports it. The other two suggested fixes are intentionally not pursued (the user chose the merge).
- **`@_spi(SwiftGodotRuntimePrivate)`** group name is deliberately *kept* as a label — it is valid within a single module and renaming it is out of scope. Only `import SwiftGodotRuntime` statements and `SwiftGodotRuntime.`-qualified references are removed.
- **Dormant split-module cases** (`SwiftGodotCore`, etc.) in `plugin.swift` are intentionally left untouched; no target builds them.
- **Risk:** the `Runtime/` subdirectory move is what prevents `GodotInterface.swift` / `Extensions/GDUtilityFunctions.swift` filename collisions. Task 9 Step 1 explicitly calls out the duplicate-filename failure mode if that assumption is wrong.
