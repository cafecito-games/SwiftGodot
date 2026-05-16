# SwiftGodot Code Review

Scope: simplify the codebase around an Apple-only target set, especially iOS and macOS, and replace the current framework packaging scripts with a more standard build flow where possible.

## Executive Summary

The package already declares only Apple platforms in `Package.swift:279`, but a lot of the repository still behaves like Linux, Windows, and Android are supported targets. That extra surface shows up in CI, docs, test fixtures, runtime conditional code, generated-source imports, and shell scripts. Removing those paths would simplify the project without changing the stated supported platforms.

The framework release pipeline is the biggest source of complexity. The current flow works around a real problem: applying `BUILD_LIBRARY_FOR_DISTRIBUTION=YES` to the normal package graph also reaches `swift-syntax` and fails. The workaround is fragile because it builds once to run the plugin, copies generated Swift files into `Sources/.../_generated`, swaps `Package.swift`, builds again, then manually repairs the framework contents. A standard release package or temporary generated-source package would keep the workaround explicit without mutating the repo checkout or hand-writing framework internals.

## Findings

### 1. Release framework packaging is fragile and duplicates a lot of logic

Evidence:

- `.github/workflows/release.yml:106` starts the macOS x86_64 "Phase 1" generation build, `.github/workflows/release.yml:118` copies generated files out of DerivedData, and `.github/workflows/release.yml:140` replaces `Package.swift` with `Package.distribution.swift`.
- The same shape is repeated for iOS at `.github/workflows/release.yml:194`, `.github/workflows/release.yml:206`, and `.github/workflows/release.yml:228`.
- The same shape is repeated again for macOS arm64 at `.github/workflows/release.yml:282`, `.github/workflows/release.yml:294`, and `.github/workflows/release.yml:316`.
- `scripts/release:97` to `scripts/release:187` implements the same two-phase build locally, including copying generated files into `Sources/SwiftGodotRuntime/_generated` and `Sources/SwiftGodot/_generated` at `scripts/release:120` to `scripts/release:126`.

Impact:

This is hard to reason about and easy to break because release correctness depends on DerivedData paths, in-place source-tree mutation, cleanup traps, duplicated workflow code, and an alternate manifest with different build settings.

Recommended direction:

Use a dedicated generated-source distribution workspace instead of copying plugin output into the live checkout. The flow can still be a two-stage build, but the mutation should happen in a temporary release package:

1. Run the normal package build once to execute `CodeGeneratorPlugin`.
2. Copy generated source output into a temporary package directory, for example `.build/release-package`.
3. Copy or generate a release manifest there that contains only the targets needed for binary distribution and omits the generator, plugin, macro, and `swift-syntax` build graph.
4. Run `xcodebuild archive` for macOS and iOS from that temporary package with `SKIP_INSTALL=NO` and `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`.
5. Use `xcodebuild -create-xcframework` directly from archive products.

This keeps the real reason for `Package.distribution.swift` while removing in-place `cp Package.distribution.swift Package.swift` from `.github/workflows/release.yml:140`, `.github/workflows/release.yml:228`, `.github/workflows/release.yml:316`, and `scripts/release:131`.

### 2. `make-swiftgodot-framework` manually reconstructs framework contents

Evidence:

- `scripts/make-swiftgodot-framework:29` creates a temporary `universal` directory and copies framework products.
- `scripts/make-swiftgodot-framework:32` to `scripts/make-swiftgodot-framework:35` uses `lipo` and then calls `xcodebuild -create-xcframework`.
- `scripts/make-swiftgodot-framework:46` to `scripts/make-swiftgodot-framework:59` manually creates framework symlinks and copies `.swiftmodule` directories.
- `scripts/make-swiftgodot-framework:61` writes `module.modulemap`.
- `scripts/make-swiftgodot-framework:75` begins a large handwritten `SwiftGodot-Swift.h`.
- `scripts/make-swiftgodot-framework:688` to `scripts/make-swiftgodot-framework:746` repeats similar logic for `SwiftGodotRuntime.xcframework`.

Impact:

The script is doing work that Xcode archive products are supposed to own. The handwritten Swift header is especially risky because it can drift from the Swift compiler version, target ABI, or actual exported Objective-C surface.

Recommended direction:

Prefer archived frameworks as the source of truth:

```sh
xcodebuild archive \
  -scheme SwiftGodot \
  -destination "generic/platform=macOS" \
  -archivePath "$archives/SwiftGodot-macos.xcarchive" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

xcodebuild archive \
  -scheme SwiftGodot \
  -destination "generic/platform=iOS" \
  -archivePath "$archives/SwiftGodot-ios.xcarchive" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

xcodebuild -create-xcframework \
  -framework "$archives/SwiftGodot-macos.xcarchive/Products/Library/Frameworks/SwiftGodot.framework" \
  -framework "$archives/SwiftGodot-ios.xcarchive/Products/Library/Frameworks/SwiftGodot.framework" \
  -output "$output/SwiftGodot.xcframework"
```

If universal macOS is still required, keep the arch handling at the archive layer or as a small, isolated `lipo` step. Avoid writing headers, module maps, and symlink layouts by hand unless a specific Xcode limitation requires it.

### 3. Public platform story conflicts with the Apple-only package declaration

Evidence:

- `Package.swift:279` declares `.macOS(.v14)` and `.iOS(.v17)` only.
- `README.md:8` advertises iOS, Linux, macOS, and Windows.
- `README.md:70` to `README.md:75` says iOS, Linux, macOS, and Windows are supported.
- The README GDExtension example includes Windows, Linux, and Android library entries at `README.md:259` to `README.md:272`.
- `.github/workflows/swift.yml:68` to `.github/workflows/swift.yml:76` actively builds Android.
- `.github/workflows/swift.yml:78` to `.github/workflows/swift.yml:110` actively builds and tests Linux.
- `Tests/SwiftGodotTestProject/SwiftTests.gdextension:8` to `Tests/SwiftGodotTestProject/SwiftTests.gdextension:19` still declares Linux and Windows test libraries and dependencies.

Impact:

The repository sends mixed signals to contributors and CI. If only iOS and macOS are supported, non-Apple CI and documentation are cost without product value.

Recommended direction:

Update the project story to match the actual support matrix:

- README platform badge and "Supported Platforms" section: macOS and iOS only.
- README `.gdextension` examples: macOS and iOS only, or explicitly label other entries as Godot examples not supported by this fork.
- CI: remove Android and Linux jobs, and add an iOS build/archive check if needed.
- Test project `.gdextension`: keep only macOS entries unless the test runner is expected to run on non-Apple systems.

### 4. The Godot test runner can report stale results

Evidence:

- `Sources/SwiftGodotTestRunner/SwiftGodotTestRunner.swift:14` fixes the result path at `Tests/SwiftGodotTestProject/test_results.json`.
- The runner never removes that file before launching Godot.
- The import process at `Sources/SwiftGodotTestRunner/SwiftGodotTestRunner.swift:167` to `Sources/SwiftGodotTestRunner/SwiftGodotTestRunner.swift:182` does not check `importProcess.terminationStatus`.
- The runner reads whatever JSON is present at `Sources/SwiftGodotTestRunner/SwiftGodotTestRunner.swift:203` to `Sources/SwiftGodotTestRunner/SwiftGodotTestRunner.swift:209`.

Impact:

If Godot fails before writing a new result file and an old `test_results.json` exists, the runner can decode stale results and report success. This is a correctness issue in the main integration-test harness.

Recommended direction:

Before running Godot, delete `test_results.json`. Better yet, pass a unique run id or output path into the Godot test project and require the decoded results to match that run. Also fail immediately if the import process exits non-zero.

### 5. Apple-only support would remove a lot of conditional runtime code

Evidence:

- `Sources/SwiftGodotRuntime/Core/NIOLock.swift:15` to `Sources/SwiftGodotRuntime/Core/NIOLock.swift:33` imports Darwin, Windows, Glibc, Musl, Bionic, and WASI variants.
- `Sources/SwiftGodotRuntime/Core/NIOLock.swift:35` to `Sources/SwiftGodotRuntime/Core/NIOLock.swift:41` abstracts over `SRWLOCK` and `pthread_mutex_t`.
- The lock is used internally at `Sources/SwiftGodotRuntime/Core/Wrapped.swift:740` and `Sources/SwiftGodotRuntime/Core/Wrapped.swift:743`.
- `Sources/SwiftGodotRuntime/Core/InitializationLevel.swift:29` to `Sources/SwiftGodotRuntime/Core/InitializationLevel.swift:35` branches only to handle Windows raw integer types.
- `Sources/SwiftGodotRuntime/EntryPoint.swift:538` to `Sources/SwiftGodotRuntime/EntryPoint.swift:543` repeats the Windows raw integer branch.
- `Generator/Generator/Printer.swift:38` to `Generator/Generator/Printer.swift:52` emits generated code imports for Darwin, Windows, Android, Glibc, and Musl.
- `Generator/Generator/Data.swift:7` to `Generator/Generator/Data.swift:12` keeps a Windows-specific Foundation workaround.

Impact:

This code was reasonable for a broad portability goal, but it now obscures the implementation. The declared Apple minimums are macOS 14 and iOS 17, so a much smaller synchronization and platform layer is available.

Recommended direction:

Replace `NIOLock` with a small internal Apple-only lock wrapper. Given the current minimums, `OSAllocatedUnfairLock` is an option; `NSLock` is also simpler if allocation and Foundation dependency are acceptable. Then remove Windows/Linux/Android/WASI import branches from the runtime and generated preambles.

### 6. Some code appears aspirational or dead

Evidence:

- `Plugins/CodeGeneratorPlugin/plugin.swift:129` to `Plugins/CodeGeneratorPlugin/plugin.swift:229` contains generation configs for split targets such as `SwiftGodotCore`, `SwiftGodotControls`, `SwiftGodot2D`, `SwiftGodot3D`, `SwiftGodotGLTF`, `SwiftGodotXR`, `SwiftGodotEditor`, and `SwiftGodotVisualShaderNodes`.
- Those split targets are not declared in the current package manifest. The active targets are `SwiftGodotRuntime` and `SwiftGodot` at `Package.swift:197` and `Package.swift:218`.
- `Sources/SwiftGodotEditorExtension/EditorExtensionMain.swift` is 8 lines and only imports Foundation.
- `Sources/SwiftGodotEditorExtension/GodotEditor.gdextension` is empty.
- `Tests/SampleLink/a.swift` is empty.

Impact:

Aspirational target code increases the mental model for contributors without producing a package product. Empty tracked files look accidental and make it harder to distinguish live functionality from placeholders.

Recommended direction:

Either commit to the split-target package shape or remove the inactive generation cases until the manifest actually uses them. Delete empty tracked files if they are not used by external tooling.

### 7. Normal builds warn about missing generated-source directories

Evidence:

- `Package.swift:200` excludes `Sources/SwiftGodotRuntime/_generated`.
- `Package.swift:221` excludes `Sources/SwiftGodot/_generated`.
- `.gitignore:23` and `.gitignore:24` ignore those directories.

Impact:

When the directories do not exist, SwiftPM prints warnings about invalid excludes during normal builds. It is minor, but it makes real warnings harder to see.

Recommended direction:

The best fix is the release-package refactor in Finding 1. If keeping the current approach temporarily, create stable placeholder directories or move the `_generated` references entirely into the distribution manifest.

### 8. Package resolution is not reproducible in the repo

Evidence:

- `Package.resolved` exists locally, but `git ls-files Package.resolved` returns nothing.
- `.gitignore:19` ignores `Package.resolved`.

Impact:

CI and release builds resolve dependency versions from the manifest constraints instead of a checked-in lock file. For a library this can be a deliberate choice, but this repo has a toolchain-sensitive release path involving `swift-syntax`, macros, plugins, and binary distribution.

Recommended direction:

Consider checking in `Package.resolved` if deterministic CI and release reproduction are more valuable than always floating to the newest compatible dependencies.

### 9. `make-libgodot` scripts look local-machine-specific

Evidence:

- `scripts/make-libgodot:1` hard-codes `~/cvs/libgodot`.
- `scripts/Makefile:1` hard-codes `~/cvs/libgodot-4.6`.
- `scripts/make-libgodot.framework:11` to `scripts/make-libgodot.framework:27` uses unquoted path variables, a predictable `/tmp/dir-$$`, and a header rewrite with `sed -e 's/bool/int/'`.

Impact:

These scripts are not portable build infrastructure. They are closer to local notes for packaging a separate Godot artifact.

Recommended direction:

If they are still needed, move them behind documented environment variables and use `mktemp -d`. If they are not part of the supported Apple-only SwiftGodot release path, archive or remove them.

## Suggested Cleanup Order

1. Align docs and CI with Apple-only support. This is low risk and immediately reduces confusion.
2. Fix the stale-results issue in `SwiftGodotTestRunner`.
3. Remove non-Apple branches from test fixtures and runtime code that are obviously unreachable under the current package platforms.
4. Replace `NIOLock` with an internal Apple-only lock wrapper.
5. Build the generated-source release package in a temporary directory and stop mutating `Package.swift` in place.
6. Replace `scripts/make-swiftgodot-framework` with archive-based `xcodebuild -create-xcframework` packaging.
7. Delete or implement the inactive split-target generator configs and empty tracked files.

## Verification Performed During Review

- `swift test --no-parallel --skip-build`: 96 tests passed.
- `swift run SwiftGodotTestRunner`: 450 passed, 0 failed, 0 skipped.
- A targeted one-phase Xcode build with `BUILD_LIBRARY_FOR_DISTRIBUTION=YES` against the normal manifest failed inside `swift-syntax`/`SwiftParser`, confirming that the current distribution manifest workaround is solving a real build-graph problem. The issue is the shape of the workaround, not the motivation for separating the release build graph.

