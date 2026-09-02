# Android Support Design

## Goal

Make Android a first-class supported SwiftGodot target. Releases must include a publishable Godot v2 Android plugin AAR with prebuilt `arm64-v8a` and `x86_64` libraries, distributed inside the existing versioned GitHub Release/Godot addon zip. Verification must prove that a separately built Swift GDExtension dynamically links to the packaged SwiftGodot runtime and executes inside the Cafecito Godot 4.7.2 Android application.

## Compatibility Contract

- Godot API and runtime: Cafecito Games custom Godot release `v4.7.2-20260826.1`, reporting `4.7.2.stable.cafecito_dc0a505af.ed1daf0bf`.
- Godot Android Gradle compile dependency: `org.godotengine:godot:4.7.2.stable`; runtime verification uses the custom release rather than the Maven artifact's stock runtime.
- Swift: 6.3.3 host toolchain and the exactly matching official Swift SDK for Android.
- Android API: 28 minimum.
- Android NDK: r27d.
- JDK: 17.
- Android ABIs: `arm64-v8a` and `x86_64`.
- Android plugin format: Godot v2 plugin AAR, using the Gradle export flow.
- Distribution: the existing GitHub Release addon zip. Maven publication is not part of this work.

The macOS and iOS products and their existing release layouts remain supported. A macOS binary remains available to Godot's desktop editor for editor-time class discovery; Android binaries are selected only for Android export and runtime.

## Chosen Architecture

SwiftGodot will use the same shared-runtime ownership model on Android that the addon uses on Apple platforms:

1. `libSwiftGodot.so` contains the SwiftGodot runtime and generated Godot API bindings.
2. `libSwiftGodotEmbed.so` is a small no-op GDExtension whose entry point causes Godot to discover the plugin and ensures that the shared runtime is packaged once.
3. Downstream Swift GDExtensions build their own `.so` files and dynamically link to `libSwiftGodot.so` instead of statically embedding SwiftGodot.
4. The SwiftGodot Android AAR owns the Swift runtime libraries required by `libSwiftGodot.so`. Downstream AARs must not package duplicate copies.

This avoids duplicate SwiftGodot state and keeps downstream addon sizes bounded when an application installs several Swift GDExtensions.

### Alternatives Rejected

- **Statically embed SwiftGodot in every extension:** simpler loading, but duplicates code and runtime state across addons and makes artifacts substantially larger.
- **Publish static archives as a development SDK:** flexible, but requires downstream consumers to recreate the native packaging pipeline and is not a turnkey Godot addon.

## Components and Responsibilities

### Portable SwiftGodot sources

The generator and hand-written runtime regain Android portability without restoring unrelated Windows or Linux support. Generated source preambles select the appropriate C library module for Darwin and Android rather than importing Darwin unconditionally. Hand-written code must use APIs available in the official Swift Android SDK or isolate Apple-only conveniences behind `canImport` checks.

### Android cross-build script

A dedicated script owns the Android build. It:

1. validates the Swift host toolchain, matching Swift Android SDK, Android SDK, NDK, JDK, the committed Gradle wrapper, and required command-line tools;
2. generates SwiftGodot sources on the host so build-tool executables and macros do not need to run on Android;
3. stages a distribution package without modifying tracked source files;
4. cross-compiles Release libraries for `aarch64-unknown-linux-android28` and `x86_64-unknown-linux-android28`;
5. builds `SwiftGodotEmbed` for both ABIs;
6. stages the Swift and NDK runtime dependency closure required by the resulting ELF libraries;
7. invokes the Android plugin Gradle build; and
8. validates the completed AAR.

All generated files live under `.build` or a caller-provided output directory. The build must be deterministic with respect to input source, toolchain version, configuration, and release version.

### Godot v2 Android plugin

The Android plugin contains:

- an Android manifest with the Godot v2 plugin registration metadata;
- a minimal Kotlin initializer derived from `GodotPlugin`;
- a `.gdextension` resource using `android_aar_plugin = true`;
- `libSwiftGodot.so`, `libSwiftGodotEmbed.so`, and required runtime libraries under both `jni/arm64-v8a` and `jni/x86_64`;
- an implementation of `getPluginGDExtensionLibrariesPaths()` that returns the packaged `.gdextension` asset path; and
- no application-specific classes or permissions.

The `.gdextension` identifies `SwiftGodotEmbed` as its entry library. The shared SwiftGodot runtime is an explicit native dependency packaged by the same AAR, not another independently registered GDExtension.

The Android plugin project commits a pinned Gradle wrapper and plugin versions compatible with Godot 4.7.2. Builds use that wrapper rather than an arbitrary system Gradle installation.

### Addon and release packaging

The existing SwiftGodot addon zip retains its Apple files and adds:

- the versioned Android AAR;
- the Godot editor export plugin and plugin configuration needed to include that AAR in Gradle Android exports; and
- Android-specific installation documentation.

The release workflow publishes one versioned addon asset through the existing GitHub Release flow. Android support does not introduce a Maven repository.

### Downstream consumer contract

Downstream Swift GDExtension authors receive:

- a documented cross-build command for both supported ABIs;
- link settings that record `libSwiftGodot.so` as a required shared library;
- a Godot v2 AAR layout for their own `.so` files;
- `.gdextension` examples containing macOS editor entries and Android runtime entries; and
- a rule that SwiftGodot and its Swift runtime dependency files are owned only by the SwiftGodot addon.

Until SwiftPM supports a portable prebuilt Swift library artifact for Android, downstream projects use the exact matching tagged SwiftGodot source package during compilation. SwiftPM builds the dynamic `SwiftGodot` product and records `libSwiftGodot.so` in the extension's `DT_NEEDED` entries. The downstream AAR packager intentionally omits that locally built copy; at runtime, Android resolves the dependency to the version owned by the installed SwiftGodot AAR. The SwiftGodot addon version, SwiftGodot source-package version, Swift 6.3.3 toolchain, and Swift Android SDK version therefore operate in lockstep.

The test fixture follows this contract exactly so it detects accidental static linkage, a version mismatch, or undeclared native dependencies.

## Artifact Layout

The SwiftGodot AAR must contain this logical layout (Gradle may add standard metadata files):

```text
SwiftGodot.aar
├── AndroidManifest.xml
├── classes.jar
├── assets/
│   └── swiftgodot/
│       └── SwiftGodotEmbed.gdextension
└── jni/
    ├── arm64-v8a/
    │   ├── libSwiftGodot.so
    │   ├── libSwiftGodotEmbed.so
    │   └── <required Swift/NDK runtime libraries>
    └── x86_64/
        ├── libSwiftGodot.so
        ├── libSwiftGodotEmbed.so
        └── <required Swift/NDK runtime libraries>
```

The addon zip places the AAR under `addons/SwiftGodot/bin/android/` and places the Android editor export plugin beside the existing addon configuration. Exact filenames include the release version where the existing release convention requires it, while installed resource paths remain stable across versions.

## Binary Validation and Failure Behavior

The build fails before packaging when any prerequisite is missing or incompatible. Diagnostics name the missing command, expected version, detected value, and remediation command where one is deterministic.

Every native library is inspected before the AAR is accepted:

- `arm64-v8a` files report AArch64 ELF machine type;
- `x86_64` files report x86-64 ELF machine type;
- GDExtension entry libraries export their configured entry symbols;
- `libSwiftGodot.so` has a stable SONAME;
- the downstream test extension has a dynamic `DT_NEEDED` entry for `libSwiftGodot.so`;
- the downstream test extension does not define SwiftGodot's runtime symbols itself;
- every non-system `DT_NEEDED` library is present in the same ABI directory;
- no binary contains a Darwin load command or build-host path; and
- neither ABI directory is missing a required file.

Gradle packaging validation rejects duplicate native library paths, unexpected ABIs, missing assets, or plugin metadata that does not reference the packaged `.gdextension`.

## Verification Strategy

### Regression tests

Shell-level regression tests exercise the Android scripts with controlled fixtures. They cover platform import generation, Swift/Android ABI mapping, toolchain validation messages, AAR layout, addon layout, and negative cases for absent or malformed libraries.

Existing macOS unit, macro, Godot integration, and release regression suites remain required and must not regress.

### Cross-compilation and binary tests

CI cross-compiles SwiftGodot, SwiftGodotEmbed, and the independent Android test extension for both supported ABIs. ELF inspection enforces the binary rules above. The test extension must dynamically reference `libSwiftGodot.so`; this is the primary guard against a misleading self-contained build.

### APK export test

A minimal Godot 4.7.2 project installs the completed SwiftGodot addon and a separately packaged test-extension AAR. With Gradle Build enabled, the custom Cafecito editor and Android templates export a debug APK. APK inspection confirms that both ABI directories contain the SwiftGodot, embed, test-extension, and runtime libraries exactly once.

### Runtime test

At startup, the independent Swift extension:

1. registers a Swift Godot class;
2. is instantiated from project script through Godot's class database;
3. executes a callable that returns a known value;
4. emits a unique success marker containing the ABI and expected value; and
5. terminates the test application cleanly.

The harness installs and launches the APK, captures `adb logcat`, fails on loader/GDExtension errors, waits with a bounded timeout, and requires the exact success marker.

`x86_64` runtime execution is mandatory in CI. `arm64-v8a` runtime execution is performed on an ARM64 Android emulator from the Apple Silicon development host. If infrastructure prevents an ABI from executing, results must label it **build-verified** rather than **runtime-verified**; release support is not described as fully runtime-verified until both have executed successfully.

## CI and Release Integration

The workflow pins the private `cafecito-games/custom-godot` release tag `v4.7.2-20260826.1`. It verifies the macOS editor archive SHA-256 `6e9945ad00d7c6877f1c3a98224c17c5ff0caf8cf42b716e9152569f6b2ac71e` and Android archive SHA-256 `a3570264cfedba3b716d6b1bc33ff1b78351b965d0dcae6262b4c1a009b01bb8` before use. CI accesses the private release with the existing Cafecito CI GitHub App credentials.

The normal pull-request workflow gains Android jobs that:

1. install pinned matching Swift and Android SDKs plus the NDK;
2. run Android regression tests;
3. cross-build and validate both ABIs;
4. build and inspect the AAR and APK; and
5. execute the x86_64 emulator runtime test.

The release workflow builds the Android AAR from the release commit and feeds it into the existing addon packager. A release fails if either ABI, its dependency closure, the Godot plugin metadata, or the Android test export validation is missing. Release checksums continue to be produced by the existing release process.

## Documentation

The README support statement changes from Apple-only to macOS, iOS, and Android, while explaining that Android consumes a Godot v2 plugin and Gradle export. A dedicated Android guide documents:

- required Swift 6.3.3, Swift Android SDK 6.3.3, Android API 28, NDK r27d, JDK 17, the bundled Gradle wrapper, and the exact Cafecito Godot 4.7.2 release;
- installing and building the SwiftGodot addon;
- cross-building downstream Swift extensions;
- creating their AAR and `.gdextension` entries;
- enabling the addon and Gradle Build in Godot;
- testing on `arm64-v8a` devices and `x86_64` emulators; and
- diagnosing missing native libraries and GDExtension load failures with `adb logcat`.

## Non-Goals

- Maven Central or another Maven repository.
- `armeabi-v7a`, `x86`, RISC-V, or Android API levels below 28.
- Running the Godot editor on Android.
- Restoring generic Linux or Windows support removed from this fork.
- Providing Swift-to-Java/Kotlin API generation beyond the minimal Godot plugin initializer.
- Shipping application-specific Android permissions or services.

## Acceptance Criteria

Android support is complete when all of the following are true:

1. SwiftGodot, SwiftGodotEmbed, and the independent test extension compile for `arm64-v8a` and `x86_64` with Swift 6.3 and API 28.
2. The generated Swift code and hand-written runtime build without Darwin-only imports on Android.
3. The AAR contains both ABI directories, the complete native dependency closure, valid Godot v2 metadata, and the `.gdextension` asset.
4. The independent test extension dynamically depends on the packaged `libSwiftGodot.so` and does not embed a second copy.
5. Cafecito Godot 4.7.2 exports the fixture project through the Gradle Android exporter using the matching custom Android templates.
6. The exported APK contains every required native library exactly once for both ABIs.
7. The x86_64 APK executes successfully on an emulator in CI.
8. The arm64-v8a APK executes successfully on an ARM64 emulator or device and records the same runtime marker.
9. Existing macOS/iOS builds, tests, addon packaging, and release checks pass unchanged.
10. The GitHub Release addon zip contains the publishable Android AAR and installation metadata.
11. User and downstream-addon documentation describes the supported workflow without relying on repository-internal knowledge.
