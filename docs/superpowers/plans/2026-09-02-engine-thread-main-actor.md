# Engine Thread as Main Actor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the thread that runs Godot's main loop the Swift main actor's thread on Android, so blanket `@MainActor` isolation is checked correctly and main-actor jobs run, per `docs/superpowers/specs/2026-09-02-engine-thread-main-actor-design.md`.

**Architecture:** Three runtime components in `Sources/SwiftGodot/Runtime/Core/`: `EngineThread` (thread identity), `MainActorJobQueue` (FIFO drained per frame), `ConcurrencyRuntimeHooks` (Android-only installation of the Swift runtime's `checkIsolated`, `isIsolatingCurrentContext` and `enqueueMainExecutor` hooks). The entry point adopts the engine thread at load, `.scene` init and main loop startup, and drains the queue from Godot's `frame_func`. The `_assumeGodotMainActor` workaround is removed.

**Tech Stack:** Swift 6.3.3, Swift SDK for Android 6.3.3, GDExtension 4.7.2 `register_main_loop_callbacks`, XCTest for host tests, Godot-hosted tests for engine behaviour, bash smoke test for Android.

---

### Task 1: EngineThread and MainActorJobQueue with host tests

**Files:**
- Create: `Sources/SwiftGodot/Runtime/Core/EngineThread.swift`
- Create: `Sources/SwiftGodot/Runtime/Core/MainActorJobQueue.swift`
- Test: `Tests/SwiftGodotUniversalTests/EngineThreadTests.swift`
- Test: `Tests/SwiftGodotUniversalTests/MainActorJobQueueTests.swift`

**Acceptance Criteria:**
- [ ] `EngineThread.isCurrent` is false before adoption, true on the adopting thread, false on another thread, follows re-adoption.
- [ ] `MainActorJobQueue` preserves FIFO order, defers jobs enqueued during a drain to the next drain, is empty after a drain, and sees jobs enqueued from another thread.

**Verify:** `swift test --filter "EngineThreadTests|MainActorJobQueueTests"` → all pass.

**Steps:**
- [ ] Write the tests. `EngineThread` keeps a `nonisolated(unsafe)` static `Atomic<UInt>` bit pattern of `pthread_t`; `MainActorJobQueue` keeps `NIOLock`-guarded `[UnownedJob]` and exposes `enqueue(_:)`, `drainFrame()` and `drainFrame(using:)` for tests, where the parameter runs a job. Tests create jobs with `Task` and confirm ordering via a lock-protected log.
- [ ] Implement, run, commit.

### Task 2: Entry point wiring

**Files:**
- Modify: `Sources/SwiftGodot/Runtime/EntryPoint.swift` (`GodotInterface`, `loadGodotInterface`, `initializeSwiftModule`, `extension_initialize`)

**Acceptance Criteria:**
- [ ] `GodotInterface.register_main_loop_callbacks` is loaded with `loadOptional`.
- [ ] `EngineThread.adopt()` runs in `initializeSwiftModule`, at `.scene` init and in `startup_func`.
- [ ] `frame_func` and `shutdown_func` call `MainActorJobQueue.drainFrame()`.
- [ ] Callbacks are registered once per process.

**Verify:** `swift build` succeeds on macOS; `swift test --filter SwiftGodotUniversalTests` passes.

### Task 3: ConcurrencyRuntimeHooks (Android only)

**Files:**
- Create: `Sources/SwiftGodot/Runtime/Core/ConcurrencyRuntimeHooks.swift`
- Modify: `Sources/SwiftGodot/Runtime/EntryPoint.swift` (call `installOnce()` on Android)

**Acceptance Criteria:**
- [ ] Hook slots found via `dlopen("libswift_Concurrency.so", RTLD_NOW | RTLD_NOLOAD)` + `dlsym`; missing symbol is a `fatalError` naming it.
- [ ] `isIsolatingCurrentContext` returns 1 for the main executor on the engine thread, else delegates.
- [ ] `checkIsolated` returns for the main executor on the engine thread, else delegates.
- [ ] `enqueueMainExecutor` forwards to `MainActorJobQueue.enqueue`.
- [ ] Spike logging: with environment `SWIFTGODOT_HOOK_TRACE=1`, each hook logs its decision through Godot's `print_warning`-free path (`print`), so logcat shows it. The Android smoke test sets this variable via `am start` extras is not possible; instead the extension logs the first hook hit unconditionally once.

**Verify:** macOS build unaffected (`swift build`); Android compile verified by CI's `build-android-libraries` job.

### Task 4: Remove `_assumeGodotMainActor`

**Files:**
- Delete: `Sources/SwiftGodot/Runtime/Core/GodotMainActorAssumption.swift`
- Modify: every call site in `Sources/SwiftGodot/Runtime/**`, `Generator/Generator/ClassGen.swift`, `Sources/SwiftGodotMacroLibrary/MacroGodot.swift`
- Modify: `Tests/SwiftGodotMacrosTests/Resources/*.swift` via `SWIFTGODOT_REGENERATE_MACRO_TEST_RESOURCES=1`

**Verify:** `grep -rn _assumeGodotMainActor Sources Generator Tests` is empty; `swift build`; `swift test --filter SwiftGodotMacrosTests` passes.

### Task 5: Android smoke test checks

**Files:**
- Modify: `Sources/AndroidTestExtension/AndroidTestExtension.swift`
- Modify: `Tests/AndroidTestProject/main.gd`
- Modify: `scripts/test-android-runtime`, `scripts/test-android-runtime-harness`
- Modify: `Sources/SwiftGodot/SwiftGodot.docc/Android.md` (success lines)

**Acceptance Criteria:**
- [ ] Probe prints `SWIFTGODOT_ANDROID_CONSTRUCTED`, `SWIFTGODOT_ANDROID_NODE_API_OK`, `SWIFTGODOT_ANDROID_MAIN_ACTOR_HOP_OK` and the existing `SWIFTGODOT_ANDROID_OK:<abi>:42`.
- [ ] The scene polls `hopCompleted` for up to 60 frames.
- [ ] `scripts/test-android-runtime` requires all four lines; harness fake adb emits them.

**Verify:** `scripts/test-android-runtime-harness` passes locally.

### Task 6: Engine test for the main-actor hop

**Files:**
- Create: `Tests/SwiftGodotTestExtension/MainActorHopTests.swift`
- Modify: `Tests/SwiftGodotTestExtension/TestRunnerNode.swift` (start the hop in `_ready`, run tests once it completes or after 60 frames)
- Modify: `Tests/SwiftGodotTestExtension/EntryPoint.swift` if a new class needs registration

**Verify:** `swift run SwiftGodotTestRunner` locally if a Godot binary is available; otherwise CI.

### Task 7: Documentation

**Files:**
- Modify: `Sources/SwiftGodot/SwiftGodot.docc/Android.md` ("Concurrency model" section)

**Verify:** section present; `scripts/test-android-runtime-harness` still passes.
