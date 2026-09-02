# Android

Ship Swift GDExtensions on Android with SwiftGodot's Godot v2 plugin and prebuilt native runtime.

## Supported contract

Android releases are built and tested as one pinned set:

- Cafecito Godot 4.7.2 (`4.7.2.stable.cafecito_dc0a505af.ed1daf0bf`)
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

```sh
swift sdk install \
  https://download.swift.org/swift-6.3.3-release/android-sdk/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_android.artifactbundle.tar.gz \
  --checksum d160cc3206dd1886dae3fef2337af5e25ec034692cd0ec225721c56cc69da7f5

swift build -c release \
  --swift-sdk aarch64-unknown-linux-android28 \
  --product MyExtension
```

Repeat with `x86_64-unknown-linux-android28`. The extension must dynamically depend on `libSwiftGodot.so`. Its AAR packages its own GDExtension library, but omits `libSwiftGodot.so` and all Swift runtime files already owned by the SwiftGodot addon.

The downstream source tag, installed SwiftGodot addon, Swift toolchain, and Swift Android SDK must move in lockstep. Mixing versions can compile successfully yet fail when Android resolves Swift symbols at load time.

This repository's reference pipeline is:

```sh
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_NDK_ROOT="$ANDROID_HOME/ndk/27.3.13750724"

scripts/build-android-libraries .build/android
scripts/package-android-aar .build/android/jni .build/android-aar
scripts/build-android-test-extension .build/android-test
```

## Export and verify

Use a Gradle Build export so Godot discovers and merges both v2 plugin AARs. The APK must contain one copy of each native library under `lib/arm64-v8a` and `lib/x86_64`.

Run the repository smoke test against an attached emulator or device:

```sh
ANDROID_SERIAL=<serial> scripts/test-android-runtime x86_64
ANDROID_SERIAL=<serial> scripts/test-android-runtime arm64-v8a
```

Success prints `SWIFTGODOT_ANDROID_OK:<abi>:42`. The test creates a Swift class through Godot, invokes an `@Callable` method, and therefore verifies registration, dynamic loading, and Swift execution—not just APK contents.

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
