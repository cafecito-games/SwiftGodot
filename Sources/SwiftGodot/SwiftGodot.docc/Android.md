# Android

Ship Swift GDExtensions on Android with SwiftGodot's Godot v2 plugin and prebuilt native runtime.

## Supported contract

Android releases are built and tested as one pinned set:

- Cafecito Godot 4.7.2 (`4.7.2.stable.cafecito_6b0b715d9.ed1daf0bf`)
- Swift 6.3.3 and `swift-6.3.3-RELEASE_android`
- Android API 28 minimum, NDK r27d (`27.3.13750724`), and JDK 17
- `arm64-v8a` and `x86_64`

The release AAR owns `libSwiftGodot.so`, `libSwiftGodotEmbed.so`, and the shared Swift/NDK runtime libraries they need. Do not copy another SwiftGodot or Swift runtime closure into a consumer AAR.

## Install the Godot addon

Install the matching `SwiftGodot-v<X.Y.Z>.zip` GitHub release asset under `addons/SwiftGodot`. With gpm:

```toml
[addons.SwiftGodot]
source      = "github-release"
repo        = "cafecito-games/SwiftGodot"
version     = "v<X.Y.Z>"
asset       = "SwiftGodot-v<X.Y.Z>.zip"
source_path = "addons/SwiftGodot"
```

Enable the SwiftGodot editor plugin, install Godot's Android build template in the project, and enable **Gradle Build** in the Android export preset. The export plugin contributes `addons/SwiftGodot/bin/android/SwiftGodot.aar`; no manual AAR copy is required.

The standalone `SwiftGodot-release.aar` asset is available for tooling that manages Godot v2 Android plugins directly. It already contains both supported ABIs.

## Build a downstream Swift extension

SwiftPM does not yet provide a portable prebuilt Swift library artifact for Android compilation. Compile a downstream extension against the exact matching SwiftGodot source tag using the same Swift 6.3.3 toolchain and SDK:

The downstream `Package.swift` must declare its extension as a dynamic library and depend on SwiftGodot's dynamic product. For example (replace `0.3.0` with the exact version installed in the Godot project):

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "MyExtension",
    products: [
        .library(name: "MyExtension", type: .dynamic, targets: ["MyExtension"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/cafecito-games/SwiftGodot.git",
            exact: "0.3.0"
        ),
    ],
    targets: [
        .target(
            name: "MyExtension",
            dependencies: [
                .product(name: "SwiftGodot", package: "SwiftGodot"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-soname",
                    "-Xlinker", "libMyExtension.so",
                ]),
            ]
        ),
    ]
)
```

An extension source can use the normal SwiftGodot registration macros:

```swift
import SwiftGodot

@Godot
final class MyAndroidNode: Node {
    @Callable func platformName() -> String { "Android" }
}

#initSwiftExtension(
    cdecl: "my_extension_entry",
    types: [MyAndroidNode.self]
)
```

Install and configure the toolchain, then build into ABI-specific scratch directories:

```sh
swift sdk install \
  https://download.swift.org/swift-6.3.3-release/android-sdk/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_android.artifactbundle.tar.gz \
  --checksum d160cc3206dd1886dae3fef2337af5e25ec034692cd0ec225721c56cc69da7f5

swift build --scratch-path .build/android/arm64-v8a -c release \
  --swift-sdk aarch64-unknown-linux-android28 \
  --product MyExtension

swift build --scratch-path .build/android/x86_64 -c release \
  --swift-sdk x86_64-unknown-linux-android28 \
  --product MyExtension
```

Each result must have `libSwiftGodot.so` in `DT_NEEDED`. Its AAR packages only `libMyExtension.so`; do not copy the locally built `libSwiftGodot.so`, `libSwiftGodotEmbed.so`, or Swift runtime libraries into the consumer AAR.

## Package a downstream Godot v2 AAR

Create an Android library project with this layout. Copy each cross-built `libMyExtension.so` into its matching `jniLibs` directory and build the macOS library separately for editor-time use:

```text
MyExtensionAndroid/
├── settings.gradle.kts
├── build.gradle.kts
├── gradlew, gradlew.bat, gradle/wrapper/...
└── plugin/src/main/
    ├── AndroidManifest.xml
    ├── java/com/example/myextension/MyExtensionPlugin.kt
    ├── assets/addons/MyExtension/MyExtension.gdextension
    └── jniLibs/
        ├── arm64-v8a/libMyExtension.so
        └── x86_64/libMyExtension.so
```

Use Gradle 8.14.3, Android Gradle Plugin 8.13.2, Kotlin 2.2.21, JDK 17, compile SDK 36, and minimum SDK 28. Generate the pinned wrapper once with `gradle wrapper --gradle-version 8.14.3 --distribution-type bin`.

`settings.gradle.kts`:

```kotlin
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "MyExtensionAndroid"
include(":plugin")
```

Root `build.gradle.kts`:

```kotlin
plugins {
    id("com.android.library") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.2.21" apply false
}
```

`plugin/build.gradle.kts`:

```kotlin
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.myextension"
    compileSdk = 36
    defaultConfig {
        minSdk = 28
        ndk { abiFilters += setOf("arm64-v8a", "x86_64") }
        manifestPlaceholders["godotPluginName"] = "MyExtension"
        manifestPlaceholders["godotPluginInitializer"] =
            "com.example.myextension.MyExtensionPlugin"
        setProperty("archivesBaseName", "MyExtension")
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_17) } }
}

dependencies {
    implementation("org.godotengine:godot:4.7.2.stable")
}
```

`plugin/src/main/AndroidManifest.xml` registers the Godot v2 plugin:

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application>
        <meta-data
            android:name="org.godotengine.plugin.v2.${godotPluginName}"
            android:value="${godotPluginInitializer}" />
    </application>
</manifest>
```

`MyExtensionPlugin.kt` tells Godot which GDExtension resource the AAR provides:

```kotlin
package com.example.myextension

import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin

class MyExtensionPlugin(godot: Godot) : GodotPlugin(godot) {
    override fun getPluginName() = "MyExtension"
    override fun getPluginGDExtensionLibrariesPaths() =
        setOf("res://addons/MyExtension/MyExtension.gdextension")
}
```

`MyExtension.gdextension` keeps a macOS entry for the desktop editor and selects the packaged libraries on Android:

```ini
[configuration]

entry_symbol = "my_extension_entry"
compatibility_minimum = 4.7
android_aar_plugin = true

[libraries]

macos.debug = "res://addons/MyExtension/bin/macos/libMyExtension.dylib"
macos.release = "res://addons/MyExtension/bin/macos/libMyExtension.dylib"
android.debug.arm64 = "res://addons/MyExtension/bin/arm64-v8a/libMyExtension.so"
android.release.arm64 = "res://addons/MyExtension/bin/arm64-v8a/libMyExtension.so"
android.debug.x86_64 = "res://addons/MyExtension/bin/x86_64/libMyExtension.so"
android.release.x86_64 = "res://addons/MyExtension/bin/x86_64/libMyExtension.so"

[dependencies]

macos.debug = { "res://addons/SwiftGodot/bin/macos_arm64/SwiftGodot.framework": "" }
macos.release = { "res://addons/SwiftGodot/bin/macos_arm64/SwiftGodot.framework": "" }
```

Build the AAR with `./gradlew --no-daemon :plugin:assembleRelease`. Install the resulting `MyExtension-release.aar` through an editor export plugin whose `_get_android_libraries` returns its `res://` path, just as for the SwiftGodot AAR. Enable both editor plugins before exporting with Gradle Build.

The downstream source tag, installed SwiftGodot addon, Swift toolchain, and Swift Android SDK must move in lockstep. Mixing versions can compile successfully yet fail when Android resolves Swift symbols at load time.

This repository's reference pipeline is:

```sh
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_NDK_ROOT="$ANDROID_HOME/ndk/27.3.13750724"

scripts/build-android-libraries .build/android
scripts/package-android-aar .build/android/jni .build/android-aar
scripts/build-android-test-extension .build/android-test
scripts/package-android-test-aar .build/android-test/jni .build/android-test
```

Set `SWIFT_GODOT_ANDROID_ABIS` to cross-compile a subset, for example
`SWIFT_GODOT_ANDROID_ABIS=x86_64` while iterating against an emulator. CI uses
that selection to build each ABI on its own runner, then merges the per-ABI JNI
trees with `scripts/aggregate-android-jni` before packaging. A published AAR
always carries both ABIs regardless of the selection.

### Iterating locally on one ABI

CI builds both ABIs and runs the device test on an x86_64 emulator. On an Apple
Silicon Mac the faster loop is arm64-v8a end to end: the Swift Android SDK
cross-compiles from macOS, and an arm64 emulator runs natively rather than
under CPU emulation.

```sh
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_NDK_ROOT="$ANDROID_HOME/ndk/27.3.13750724"
export SWIFT_GODOT_ANDROID_ABIS=arm64-v8a
export SWIFT_GODOT_ANDROID_SINGLE_ABI=arm64-v8a

scripts/build-android-libraries .build/android
scripts/build-android-test-extension .build/android-test
scripts/package-android-aar .build/android/jni .build/android-aar
scripts/package-android-test-aar .build/android-test/jni .build/android-test
ANDROID_SERIAL=<serial> scripts/test-android-runtime arm64-v8a
```

`SWIFT_GODOT_ANDROID_ABIS` selects which ABIs are compiled.
`SWIFT_GODOT_ANDROID_SINGLE_ABI` additionally narrows the checks that otherwise
require a publishable artifact to carry every configured ABI — AAR packaging,
AAR validation, and the APK contents assertion. Anything built under it prints
a warning and must not be published; CI never sets it, and
`scripts/test-android-ci-topology` fails if a workflow does.

The SwiftPM scratch path persists between runs, so only the first build pays
full cost.

`scripts/build-android-test-extension` builds the consumer in a scratch path of
its own, so it recompiles SwiftGodot for each ABI. Pointing it at the scratch
path `scripts/build-android-libraries` populated does not work: SwiftPM reuses
that build description rather than replanning for the consumer's root package,
and the build fails with `No target named
'AndroidTestExtension-<triple>-release.dylib' in build description`. Set
`SWIFT_GODOT_GENERATED_SOURCES_CACHE` to a directory to reuse previously
generated bindings and skip the host generation build; it is repopulated
whenever generation does run.

## Export and verify

Use a Gradle Build export so Godot discovers and merges both v2 plugin AARs. The APK must contain one copy of each native library under `lib/arm64-v8a` and `lib/x86_64`.

Set the export preset's **Min SDK** to 28. The Godot Android build template
defaults to 24, and the SwiftGodot AAR declares 28 because that is the API
level the Swift Android SDK targets. A lower value fails during the export's
Gradle build with a manifest merger error that names the AAR rather than the
preset:

```
Manifest merger failed : uses-sdk:minSdkVersion 24 cannot be smaller than
version 28 declared in library [SwiftGodot-release.aar]
```

In `export_presets.cfg` that setting is `gradle_build/min_sdk="28"`.

Run the repository smoke test against an attached emulator or device:

```sh
ANDROID_SERIAL=<serial> scripts/test-android-runtime x86_64
ANDROID_SERIAL=<serial> scripts/test-android-runtime arm64-v8a
```

Success prints `SWIFTGODOT_ANDROID_OK:<abi>:42`, preceded by three markers that each prove a boundary crossing between Godot's engine thread and Swift's main actor:

| Marker | What it proves |
| --- | --- |
| `SWIFTGODOT_ANDROID_CONSTRUCTED` | A `@Godot` class registered and was constructed from GDScript. |
| `SWIFTGODOT_ANDROID_NODE_API_OK` | Generated bindings with declared isolation ran from a Godot callback. |
| `SWIFTGODOT_ANDROID_MAIN_ACTOR_HOP_OK` | A `Task` left the main actor and resumed on it within sixty frames. |

The test therefore verifies registration, dynamic loading, Swift execution and the concurrency model, not just APK contents.

## Concurrency model

Every Godot object is `@MainActor`, and on every platform the main actor's thread is the thread that runs Godot's main loop. On macOS and iOS that is the process main thread, so the platform's main executor recognises it unchanged. On Android the main loop runs on the renderer thread, which the Swift runtime and libdispatch would not recognise on their own, so at load SwiftGodot installs its own main executor through the Swift runtime's custom executor interface: isolation checks pass on the engine thread and fail elsewhere, and jobs enqueued on the main executor are held until Godot's per-frame main loop callback drains them. That interface is `@_spi(ExperimentalCustomExecutors)` in the Swift 6.3.3 toolchain the Android contract pins, so upgrading the Android toolchain means re-verifying it.

Consequences for extension code:

- Synchronous calls into Godot objects from Godot callbacks need no annotation; they are already on the main actor.
- A `Task` started from a Godot object inherits main-actor isolation. On Android its jobs run at the next frame boundary rather than immediately, so expect a one-frame delay before and after each `await` that leaves the main actor.
- Calling a Godot object from a Godot worker thread, a GDScript `Thread`, or any other thread is a fatal error on every platform. Marshal the work back with `callDeferred` or a signal instead.
- The engine thread is recorded when the extension loads, again when Godot initialises the `.scene` level, and once more when the main loop starts. Code that runs before the `.scene` level runs on the thread that loaded the extension and is treated as main-actor isolated there.

## Diagnose loader failures

Start with filtered Android logs:

```sh
adb logcat -c
adb logcat | grep -E 'SwiftGodot|GDExtension|dlopen|linker'
```

- `dlopen failed` or `library not found` usually means a required `DT_NEEDED` library is absent from the same APK ABI directory.
- `cannot locate symbol` usually indicates that the consumer source and installed SwiftGodot addon are not in lockstep.
- A missing GDExtension class with no Swift marker usually means the v2 plugin was not enabled or the project was exported without Gradle Build.
- An ABI error means the device ABI is not one of `arm64-v8a` or `x86_64`, or the corresponding library was removed by export configuration.
