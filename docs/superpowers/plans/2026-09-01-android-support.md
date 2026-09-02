# Android Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship and runtime-verify a Godot 4.7.2 v2 Android plugin AAR containing shared SwiftGodot libraries for `arm64-v8a` and `x86_64` inside the existing release addon.

**Architecture:** Generate SwiftGodot sources on the host, cross-compile a dynamic Android distribution with the official Swift 6.3.3 SDK, and package the ELF libraries plus their shared runtime closure in a pinned Gradle AAR. A separately compiled Swift test extension depends dynamically on `libSwiftGodot.so`; Godot exports and runs the combined plugins on Android emulators.

**Tech Stack:** Swift 6.3.3, SwiftPM cross-compilation SDK, Android API 28, NDK r27d, JDK 17, Gradle 8.14.3, Android Gradle Plugin 8.13.2, Kotlin 2.2.21, Cafecito Godot 4.7.2 v2 Android plugins, Bash, `llvm-readelf`, `adb`.

---

## File Structure

- `Generator/Generator/Printer.swift`: emits portable Darwin/Android imports in generated bindings.
- `Package.android.swift`: generated-source distribution manifest for Android shared libraries.
- `Package.swift`: exposes the Android runtime test extension product.
- `Sources/AndroidTestExtension/AndroidTestExtension.swift`: independently registered Swift class used by the APK smoke test.
- `scripts/stage-android-package`: creates a generated-source Android package without changing the checkout.
- `scripts/build-android-libraries`: cross-compiles both ABI slices and stages their runtime dependency closure.
- `scripts/validate-android-elf`: validates ABI, SONAME, entry symbols, and `DT_NEEDED` closure.
- `scripts/package-android-aar`: populates the Gradle project and emits the release AAR.
- `scripts/test-android-*`: focused regression tests for portability, build orchestration, ELF validation, AAR layout, addon packaging, and runtime harness behavior.
- `Android/SwiftGodotPlugin/`: pinned Gradle v2 plugin project and Kotlin initializer.
- `Tests/AndroidTestProject/`: Godot project, downstream plugin metadata, export preset, and success-marker script.
- `scripts/test-android-runtime`: exports, installs, launches, and verifies the APK through `adb`.
- `scripts/package-godot-addon`, `scripts/release`, `.github/workflows/*.yml`: integrate Android artifacts into CI and release.
- `Sources/SwiftGodot/SwiftGodot.docc/Android.md`, `README.md`: user and downstream-addon instructions.

## Task 1: Restore Android Source Portability

**Files:**
- Create: `scripts/test-android-portability`
- Modify: `Generator/Generator/Printer.swift:33-44`
- Modify: `Tests/SwiftGodotTestExtension/Math/BasisTests.swift:1-8`

- [ ] **Step 1: Write the failing portability test**

Create an executable shell test that requires the generator preamble to contain `#if canImport(Darwin)`, an Android branch accepting `Android` or `Bionic`, and a terminal unsupported-C-library error. Require Android math tests to import the Android C module conditionally.

```bash
rg -q '#if canImport\(Darwin\)' Generator/Generator/Printer.swift
rg -q '#elseif canImport\((Android|Bionic)\)' Generator/Generator/Printer.swift
rg -q '#error\("Unable to identify your C library\."\)' Generator/Generator/Printer.swift
rg -q '#if os\(Android\)' Tests/SwiftGodotTestExtension/Math/BasisTests.swift
```

- [ ] **Step 2: Run the test and confirm RED**

Run: `scripts/test-android-portability`

Expected: failure because `Printer.basePreamble` imports Darwin unconditionally.

- [ ] **Step 3: Implement portable imports**

Emit this conditional preamble and add the conditional Android math import:

```swift
#if canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#elseif canImport(Bionic)
import Bionic
#else
#error("Unable to identify your C library.")
#endif
```

- [ ] **Step 4: Confirm GREEN and preserve Apple behavior**

Run: `scripts/test-android-portability && swift test --skip-build`

Expected: portability test passes; existing 96-test suite passes.

- [ ] **Step 5: Commit**

```bash
git add Generator/Generator/Printer.swift Tests/SwiftGodotTestExtension/Math/BasisTests.swift scripts/test-android-portability
git commit -m "feat: restore Android source portability"
```

## Task 2: Stage an Android Distribution Package

**Files:**
- Create: `Package.android.swift`
- Create: `scripts/stage-android-package`
- Create: `scripts/test-stage-android-package`

- [ ] **Step 1: Write a failing staging test**

The test supplies a fake generated-source directory, runs `scripts/stage-android-package`, and requires:

```text
Package.swift
Sources/GDExtension/
Sources/SwiftGodot/
Sources/SwiftGodot/_generated/FakeGenerated.swift
Sources/SwiftGodotEmbed/
```

It also asserts the staged manifest contains dynamic `SwiftGodot` and `SwiftGodotEmbed` products, Swift language mode 6, library evolution, and no `-internalize-at-link` flag.

- [ ] **Step 2: Run the test and confirm RED**

Run: `scripts/test-stage-android-package`

Expected: failure because the staging script and Android manifest do not exist.

- [ ] **Step 3: Add the minimal Android manifest and staging script**

`Package.android.swift` declares only `GDExtensionC`, dynamic `SwiftGodot`, and dynamic `SwiftGodotEmbed`. `SwiftGodot` defines `CUSTOM_BUILTIN_IMPLEMENTATIONS`, uses Swift 6 mode, and passes `-enable-library-evolution` without Apple framework or LTO-specific flags.

`scripts/stage-android-package GENERATED_SOURCES OUTPUT` copies tracked sources with `rsync`, installs the Android manifest as `OUTPUT/Package.swift`, and copies every generated `.swift` file to `Sources/SwiftGodot/_generated`.

- [ ] **Step 4: Confirm GREEN**

Run: `scripts/test-stage-android-package && swift package dump-package >/dev/null`

Expected: staging test passes and the development manifest remains valid.

- [ ] **Step 5: Commit**

```bash
git add Package.android.swift scripts/stage-android-package scripts/test-stage-android-package
git commit -m "feat: stage Android distribution package"
```

## Task 3: Cross-Compile Both Android ABIs

**Files:**
- Create: `scripts/android-config`
- Create: `scripts/build-android-libraries`
- Create: `scripts/test-build-android-libraries`
- Modify: `.gitignore`

- [ ] **Step 1: Write failing orchestration tests**

Use fake `swift` and fake staging commands to record invocations. Require exact targets:

```text
aarch64-unknown-linux-android28 -> arm64-v8a
x86_64-unknown-linux-android28 -> x86_64
```

Require `-c release`, `--product SwiftGodot`, and `--product SwiftGodotEmbed`, plus diagnostics for a missing `swift-6.3.3-RELEASE_android` SDK.

- [ ] **Step 2: Run the test and confirm RED**

Run: `scripts/test-build-android-libraries`

Expected: failure because the build orchestrator does not exist.

- [ ] **Step 3: Implement pinned configuration and orchestration**

`scripts/android-config` exports immutable defaults:

```bash
SWIFT_ANDROID_VERSION=6.3.3
SWIFT_ANDROID_SDK_ID=swift-6.3.3-RELEASE_android
SWIFT_ANDROID_API=28
SWIFT_ANDROID_NDK_VERSION=27.3.13750724
SWIFT_ANDROID_TRIPLES="aarch64-unknown-linux-android28 x86_64-unknown-linux-android28"
```

`scripts/build-android-libraries OUTPUT` validates `swift --version`, `swift sdk list`, `ANDROID_HOME`, `ANDROID_NDK_ROOT`, and Java 17; finds generated plugin output or generates it on the host; stages the package; builds each product for each triple in a separate scratch path; and copies the `.so` files into `OUTPUT/jni/<abi>`.

- [ ] **Step 4: Confirm orchestration GREEN**

Run: `scripts/test-build-android-libraries`

Expected: both ABI/product invocations and failure diagnostics pass.

- [ ] **Step 5: Install/configure the real toolchain and cross-build**

Use the official Swift 6.3.3 Android SDK and NDK r27d, then run:

```bash
scripts/build-android-libraries .build/android
file .build/android/jni/arm64-v8a/libSwiftGodot.so
file .build/android/jni/x86_64/libSwiftGodot.so
```

Expected: AArch64 and x86-64 ELF shared objects.

- [ ] **Step 6: Commit**

```bash
git add .gitignore scripts/android-config scripts/build-android-libraries scripts/test-build-android-libraries
git commit -m "feat: cross-compile SwiftGodot for Android"
```

## Task 4: Validate and Stage Native Dependency Closure

**Files:**
- Create: `scripts/validate-android-elf`
- Create: `scripts/stage-android-runtime-libraries`
- Create: `scripts/test-validate-android-elf`
- Modify: `scripts/build-android-libraries`

- [ ] **Step 1: Write failing ELF-validator tests**

Compile tiny NDK fixture libraries for both ABIs. Cover correct architecture, wrong ABI directory, absent `swift_godot_embed_entry_point`, absent SONAME, missing non-system `DT_NEEDED`, and a consumer without `libSwiftGodot.so` in `DT_NEEDED`.

- [ ] **Step 2: Run the test and confirm RED**

Run: `scripts/test-validate-android-elf`

Expected: failure because the validator does not exist.

- [ ] **Step 3: Implement validation and dependency closure staging**

Use the NDK's `llvm-readelf -h -d -Ws`. Treat `libc.so`, `libdl.so`, `liblog.so`, `libm.so`, `libz.so`, `libandroid.so`, and the dynamic linker as system libraries. Resolve all other `DT_NEEDED` entries from the Swift Android SDK or NDK sysroot, copy them beside the owning ABI, recurse to closure, and reject unresolved names.

- [ ] **Step 4: Confirm fixtures and real binaries GREEN**

Run:

```bash
scripts/test-validate-android-elf
scripts/validate-android-elf .build/android/jni
```

Expected: negative fixtures fail for the intended reason and real libraries pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/validate-android-elf scripts/stage-android-runtime-libraries scripts/test-validate-android-elf scripts/build-android-libraries
git commit -m "feat: validate Android native dependencies"
```

## Task 5: Build the Godot v2 Plugin AAR

**Files:**
- Create: `Android/SwiftGodotPlugin/settings.gradle.kts`
- Create: `Android/SwiftGodotPlugin/build.gradle.kts`
- Create: `Android/SwiftGodotPlugin/gradle.properties`
- Create: `Android/SwiftGodotPlugin/gradle/wrapper/gradle-wrapper.properties`
- Generate: `Android/SwiftGodotPlugin/gradle/wrapper/gradle-wrapper.jar`
- Create: `Android/SwiftGodotPlugin/gradlew`
- Create: `Android/SwiftGodotPlugin/plugin/build.gradle.kts`
- Create: `Android/SwiftGodotPlugin/plugin/src/main/AndroidManifest.xml`
- Create: `Android/SwiftGodotPlugin/plugin/src/main/java/games/cafecito/swiftgodot/SwiftGodotPlugin.kt`
- Create: `Android/SwiftGodotPlugin/plugin/src/main/assets/addons/SwiftGodot/SwiftGodotEmbed.gdextension`
- Create: `scripts/package-android-aar`
- Create: `scripts/test-package-android-aar`

- [ ] **Step 1: Write the failing AAR layout test**

Provide fake ELF inputs, invoke `scripts/package-android-aar`, unzip the result, and require `AndroidManifest.xml`, `classes.jar`, both `jni/<abi>` trees, and `assets/addons/SwiftGodot/SwiftGodotEmbed.gdextension`. Assert manifest metadata names `org.godotengine.plugin.v2.SwiftGodot` and the Kotlin initializer.

- [ ] **Step 2: Run the test and confirm RED**

Run: `scripts/test-package-android-aar`

Expected: failure because the Gradle plugin project and packager do not exist.

- [ ] **Step 3: Add the pinned Gradle project**

Pin Gradle 8.14.3, AGP 8.13.2, Kotlin 2.2.21, `compileSdk = 36`, `minSdk = 28`, Java/Kotlin 17, Godot Maven compile dependency `org.godotengine:godot:4.7.2.stable`, and both ABI filters. The Kotlin class extends `GodotPlugin`, returns `SwiftGodot`, and returns `res://addons/SwiftGodot/SwiftGodotEmbed.gdextension` from `getPluginGDExtensionLibrariesPaths()`.

- [ ] **Step 4: Add packaging and verify GREEN**

`scripts/package-android-aar JNI_ROOT OUTPUT` copies JNI trees into `plugin/src/main/jniLibs`, runs `./gradlew :plugin:assembleRelease`, copies `SwiftGodot-release.aar`, and restores a clean generated-input directory through a trap.

Run: `scripts/test-package-android-aar && scripts/package-android-aar .build/android/jni .build/android/aar`

Expected: layout regression passes and the real release AAR validates.

- [ ] **Step 5: Commit**

```bash
git add Android/SwiftGodotPlugin scripts/package-android-aar scripts/test-package-android-aar
git commit -m "feat: package SwiftGodot Android AAR"
```

## Task 6: Add Android to the Godot Addon

**Files:**
- Modify: `scripts/package-godot-addon`
- Modify: `scripts/test-package-godot-addon`
- Modify: `Makefile`

- [ ] **Step 1: Extend the existing test and confirm RED**

Pass a fake AAR as the fourth required binary input. Require:

```text
addons/SwiftGodot/bin/android/SwiftGodot.aar
addons/SwiftGodot/export_plugin.gd
addons/SwiftGodot/plugin.cfg
addons/SwiftGodot/SwiftGodotEmbed.gdextension
```

Require `plugin.cfg` to reference `export_plugin.gd`, the export plugin to select the release AAR, and the `.gdextension` to contain `android_aar_plugin = true` plus arm64 and x86_64 library entries.

- [ ] **Step 2: Run and confirm RED**

Run: `scripts/test-package-godot-addon`

Expected: failure because the packager accepts only Apple artifacts.

- [ ] **Step 3: Implement addon integration**

Change usage to:

```text
scripts/package-godot-addon TAG SWIFTGODOT_XCFRAMEWORK SWIFTGODOTEMBED_XCFRAMEWORK ANDROID_AAR [OUTPUT_DIR]
```

Copy the AAR, emit the Godot Android `EditorExportPlugin`, set the plugin script, add Android entries, and preserve the existing Apple dependency block.

- [ ] **Step 4: Confirm GREEN**

Run: `scripts/test-package-godot-addon`

Expected: existing Apple assertions and new Android assertions pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/package-godot-addon scripts/test-package-godot-addon Makefile
git commit -m "feat: include Android AAR in Godot addon"
```

## Task 7: Build an Independent Runtime Test Extension

**Files:**
- Modify: `Package.swift`
- Create: `Sources/AndroidTestExtension/AndroidTestExtension.swift`
- Create: `Tests/AndroidTestProject/addons/SwiftGodotAndroidTest/SwiftGodotAndroidTest.gdextension`
- Create: `Tests/AndroidTestProject/main.gd`
- Create: `Tests/AndroidTestProject/main.tscn`
- Create: `Tests/AndroidTestProject/project.godot`
- Create: `Tests/AndroidTestProject/export_presets.cfg`
- Create: `Android/SwiftGodotPlugin/test-plugin/build.gradle.kts`
- Create: `Android/SwiftGodotPlugin/test-plugin/src/main/AndroidManifest.xml`
- Create: `Android/SwiftGodotPlugin/test-plugin/src/main/java/games/cafecito/swiftgodot/test/SwiftGodotAndroidTestPlugin.kt`
- Create: `Android/SwiftGodotPlugin/test-plugin/src/main/assets/addons/SwiftGodotAndroidTest/SwiftGodotAndroidTest.gdextension`
- Create: `scripts/build-android-test-extension`
- Create: `scripts/test-build-android-test-extension`

- [ ] **Step 1: Write the failing dynamic-link test**

Require an `AndroidTestExtension` dynamic product. Build-script fixture assertions require both Android triples, packaging omission of `libSwiftGodot.so`, and `validate-android-elf --consumer libAndroidTestExtension.so`.

- [ ] **Step 2: Run and confirm RED**

Run: `scripts/test-build-android-test-extension`

Expected: failure because the target and builder do not exist.

- [ ] **Step 3: Implement the test class, plugin module, and builder**

Register `AndroidRuntimeProbe` with `#initSwiftExtension(cdecl: "swiftgodot_android_test_entry", types: [AndroidRuntimeProbe.self])`. Expose a callable returning `"SWIFTGODOT_ANDROID_OK:<abi>:42"`. Add a second Gradle library module whose Kotlin initializer returns the test `.gdextension` path. Cross-build the dynamic product against the exact root package version, assert `DT_NEEDED` contains `libSwiftGodot.so`, and package only `libAndroidTestExtension.so` plus its own non-SwiftGodot dependencies in `SwiftGodotAndroidTest-release.aar`.

- [ ] **Step 4: Add the Godot fixture**

The GDScript instantiates `AndroidRuntimeProbe`, calls the probe, prints the exact marker, and calls `get_tree().quit(0)`; any missing class or wrong result prints `SWIFTGODOT_ANDROID_FAIL` and exits nonzero.

- [ ] **Step 5: Confirm GREEN**

Run: `scripts/test-build-android-test-extension && scripts/build-android-test-extension .build/android-test`

Expected: both ABI consumers depend dynamically on `libSwiftGodot.so` and do not contain SwiftGodot runtime definitions.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/AndroidTestExtension Tests/AndroidTestProject Android/SwiftGodotPlugin/test-plugin Android/SwiftGodotPlugin/settings.gradle.kts scripts/build-android-test-extension scripts/test-build-android-test-extension
git commit -m "test: add Android runtime extension fixture"
```

## Task 8: Export and Execute the Android APK

**Files:**
- Create: `scripts/test-android-runtime`
- Create: `scripts/test-android-runtime-harness`

- [ ] **Step 1: Write failing harness tests**

Use fake `godot`, `adb`, and log streams. Cover successful marker, `SWIFTGODOT_ANDROID_FAIL`, `dlopen failed`, GDExtension initialization errors, adb timeout, and nonzero Godot export.

- [ ] **Step 2: Run and confirm RED**

Run: `scripts/test-android-runtime-harness`

Expected: failure because the harness does not exist.

- [ ] **Step 3: Implement bounded export/runtime orchestration**

The harness installs the Android templates from Cafecito custom Godot release `v4.7.2-20260826.1` when absent, verifies the archive SHA-256 `a3570264cfedba3b716d6b1bc33ff1b78351b965d0dcae6262b4c1a009b01bb8`, stages both AAR addons into the fixture, exports a debug APK with Gradle Build, checks both APK ABI directories, starts the requested emulator/device serial, clears logcat, installs with `adb install -r`, launches the Godot activity, and waits at most 120 seconds for the exact success marker. The macOS editor archive is pinned to SHA-256 `6e9945ad00d7c6877f1c3a98224c17c5ff0caf8cf42b716e9152569f6b2ac71e` and must report `4.7.2.stable.cafecito_dc0a505af.ed1daf0bf`.

- [ ] **Step 4: Confirm harness GREEN**

Run: `scripts/test-android-runtime-harness`

Expected: all simulated success and failure paths pass.

- [ ] **Step 5: Run real x86_64 and arm64 verification**

Run:

```bash
scripts/test-android-runtime x86_64
scripts/test-android-runtime arm64-v8a
```

Expected: both runs report `SWIFTGODOT_ANDROID_OK:<abi>:42` and no loader errors.

- [ ] **Step 6: Commit**

```bash
git add scripts/test-android-runtime scripts/test-android-runtime-harness
git commit -m "test: verify SwiftGodot in Android runtime"
```

## Task 9: Integrate CI and Release Packaging

**Files:**
- Modify: `.github/workflows/swift.yml`
- Modify: `.github/workflows/release.yml`
- Modify: `scripts/release`
- Modify: `scripts/test-distribution-package-staging`
- Modify: `scripts/test-release-build-configuration`
- Modify: `scripts/test-package-godot-addon`

- [ ] **Step 1: Extend workflow/release regression tests and confirm RED**

Require an Android CI job using Swift 6.3.3, both ABI builds, AAR/APK validation, x86_64 emulator execution, an Android release artifact job, release-job dependency/download, and the AAR argument passed to `package-godot-addon`.

Run: `scripts/test-distribution-package-staging && scripts/test-release-build-configuration && scripts/test-package-godot-addon`

Expected: Android workflow assertions fail.

- [ ] **Step 2: Implement pull-request CI**

Add an Ubuntu Android job that installs the pinned official Swift SDK/NDK/JDK, builds both ABIs and AARs, exports the APK, uploads diagnostics, and runs the x86_64 emulator smoke test.

- [ ] **Step 3: Implement release wiring**

Add an Android build job that uploads `SwiftGodot-release.aar`; make the release job require and download it; pass it into `scripts/release` through `SWIFT_GODOT_ANDROID_AAR`; require the file in skip-build mode; and upload the addon containing it.

- [ ] **Step 4: Confirm workflow regression GREEN**

Run:

```bash
scripts/test-distribution-package-staging
scripts/test-release-build-configuration
scripts/test-package-godot-addon
```

Expected: all release regressions pass.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/swift.yml .github/workflows/release.yml scripts/release scripts/test-distribution-package-staging scripts/test-release-build-configuration scripts/test-package-godot-addon
git commit -m "ci: build and release Android addon"
```

## Task 10: Document Android Support and Run Final Verification

**Files:**
- Modify: `README.md`
- Create: `Sources/SwiftGodot/SwiftGodot.docc/Android.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Write documentation assertions and confirm RED**

Extend `scripts/test-android-portability` to require README support for Android, the Android guide, exact version/ABI/API contract, Gradle export instructions, downstream source/addon lockstep, and `adb logcat` diagnosis.

Run: `scripts/test-android-portability`

Expected: documentation assertions fail.

- [ ] **Step 2: Write user and downstream documentation**

Document prerequisites, addon installation, source cross-build, downstream AAR rules, Gradle export, emulator/device testing, supported versions, and loader troubleshooting. Update the fork scope and changelog.

- [ ] **Step 3: Confirm documentation GREEN**

Run: `scripts/test-android-portability`

Expected: all documentation assertions pass.

- [ ] **Step 4: Run the complete local verification matrix**

```bash
swift test
swift run SwiftGodotTestRunner
scripts/test-android-portability
scripts/test-stage-android-package
scripts/test-build-android-libraries
scripts/test-validate-android-elf
scripts/test-package-android-aar
scripts/test-package-godot-addon
scripts/test-build-android-test-extension
scripts/test-android-runtime-harness
scripts/test-android-runtime x86_64
scripts/test-android-runtime arm64-v8a
scripts/test-make-swiftgodot-framework
scripts/test-release-build-configuration
scripts/test-binary-manifest
scripts/test-package-resolution
scripts/test-distribution-package-staging
scripts/test-release-toolchain
git diff --check
```

Expected: every command exits zero; both runtime runs emit their ABI-specific success markers.

- [ ] **Step 5: Commit**

```bash
git add README.md CHANGELOG.md Sources/SwiftGodot/SwiftGodot.docc/Android.md scripts/test-android-portability
git commit -m "docs: document Android distribution workflow"
```
