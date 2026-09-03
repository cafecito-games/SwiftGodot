# Engine Thread as Main Actor Design

Resolves [issue #44](https://github.com/cafecito-games/SwiftGodot/issues/44): blanket `@MainActor` isolation on `Wrapped` is fatal on Android.

## Goal

Keep the Swift 6 isolation model introduced in PR #4 (every Godot object is `@MainActor`) and make it correct, not merely unchecked, on every platform SwiftGodot ships to. On Android, the Swift runtime must treat the thread that runs Godot's main loop as the main actor's thread: synchronous isolation checks pass there and fail everywhere else, and asynchronous work bound to the main actor actually runs. On macOS and iOS, behaviour is unchanged and gains a regression test.

## Findings

These are the facts the design rests on. Each was verified against the Swift 6.3.3 runtime sources, the Swift SDK for Android bundle installed locally, and the Cafecito Godot fork.

### Why the assertion fails on Android

A `@MainActor` isolation check reached from code with no Swift concurrency context (every Godot callback) runs `swift_task_isCurrentExecutorWithFlagsImpl` in `Actor.cpp`. It takes these steps in order:

1. If the expected executor is the main executor and `Thread::onMainThread()` is true, pass.
2. Ask the executor `isIsolatingCurrentContext()`. A definite answer ends the check.
3. Call `checkIsolated()` on the executor, which is expected to crash unless it can prove the caller is on the right thread.

On Linux and Android, `Thread::onMainThread()` compares `pthread_self()` against the thread that ran libswiftCore's static initialisers. That is the thread that first loaded the Swift runtime. The engine fork loads GDExtension libraries during `Main::setup`, which on Android runs on the Java UI thread (`FoundryLib.setup`). The main loop, class registration at the `.scene` level, and every callback run later on the renderer thread (`FoundryLib.step` on `GLThread` or `VkThread`), where `Main::setup2` explicitly calls `Thread::make_main_thread()` for exactly this reason. So step 1 fails.

The default main executor on Android is `DispatchMainExecutor`. It does not implement `isIsolatingCurrentContext()`, so step 2 answers "unknown". Its `checkIsolated()` calls `dispatch_assert_queue(main)`. In swift-corelibs-libdispatch that only passes if the calling thread currently holds the main queue's drain lock, which requires `dispatch_main()` or a CoreFoundation run loop to be draining it. Godot never does either. Step 3 aborts.

On macOS and iOS the engine's main loop runs on the process main thread and Apple's libdispatch binds the main queue to that thread at load, so step 1 or step 3 passes.

### Why the current workaround cannot converge

`_assumeGodotMainActor` replaces explicit `MainActor.assumeIsolated` calls. It cannot reach the dynamic check the compiler inserts when a `nonisolated` caller invokes a declared `@MainActor` member. There are 45 such declarations in the runtime, and the generated bindings and consumer macros add more. That is the crash the issue's follow-up comment documents at `RefCounted.init(InitContext)`.

The workaround also removes the assertion entirely on Android. A Godot worker thread calling into Swift would then proceed without any check, which is a silent data race rather than a crash.

### Asynchronous main-actor work is also broken on Android

Independently of the assertion, any job enqueued on the main executor on Android goes to libdispatch's main queue, which nothing drains. A `Task` inheriting main-actor isolation from a Godot object, or an `await` that must resume on the main actor, never runs. Neither option A nor option B in the issue addresses this. The design below does.

### The Swift runtime lets a library replace the main executor

Two runtime surfaces were evaluated against the Swift 6.3.3 sources.

**Concurrency hooks.** `libswift_Concurrency.so` exports `swift_task_checkIsolated_hook`, `swift_task_isIsolatingCurrentContext_hook` and `swift_task_enqueueMainExecutor_hook`. The first two are consulted by steps 2 and 3 above and do make isolation checks pass on the engine thread; CI run 33706088533 proved that with the C trampolines described below. The third is not consulted for main-actor tasks: `swift_task_enqueueImpl` in `Actor.cpp` routes a job for the main executor straight to the executor's Swift `enqueue` witness (`DispatchMainExecutor.enqueue`, which calls libdispatch directly), and only legacy callers reach `swift_task_enqueueMainExecutor`. The hooks therefore cannot deliver the drain, and draining libdispatch's main queue by hand is not an option either: `_dispatch_main_queue_callback_4CF` requires the main queue to be thread-bound to the caller, and corelibs binds it at load to the thread that loaded libdispatch, the Java UI thread.

**Custom main executor.** The SE-0462 executor factory is present in the 6.3.3 stdlib behind `@_spi(ExperimentalCustomExecutors)`: `MainExecutor`, `ExecutorFactory`, `PlatformExecutorFactory` and `_createExecutors(factory:)`. `_createExecutors` assigns `MainActor._executor` and `Task._defaultExecutor` without a guard, and the lazy default creation then skips, so a library can install its own main executor at load. The runtime's isolation check reaches that executor's `isIsolatingCurrentContext()` through the Swift witness (step 2), `isMainExecutor` is derived from being `MainActor.executor`, and every enqueue for the main actor arrives at its `enqueue`. This is the chosen mechanism. It is SPI, so it is pinned to the exact Swift 6.3.3 toolchain the Android compatibility contract already requires; upgrading that toolchain includes re-verifying the SPI.

### Godot provides a per-frame callback

`gdextension_interface.h` since Godot 4.5 exposes `register_main_loop_callbacks` with `startup_func`, `shutdown_func` and `frame_func`. `frame_func` runs on the main loop thread every process frame, after `_process` and before `ScriptServer::frame()`. The fork is 4.7.2 and has it. SwiftGodot does not use it yet.

## Options considered

**A. Keep suppressing the check on Android.** Rejected. It cannot reach compiler-inserted checks, it removes the assertion rather than satisfying it, and it does nothing for asynchronous work.

**B. Drop blanket isolation and adopt upstream's opt-in model.** Rejected. It reverts the Swift 6 model that consumers already write against, forces `nonisolated(unsafe)` back into the runtime's shared state, and still leaves main-actor jobs undrained on Android. Upstream has no Android support, so it has never had to answer this question.

**C. Make the engine thread the main actor's thread.** Chosen. Install a main executor on Android that answers isolation checks from the engine thread's identity and queues main-executor jobs for the engine thread, and drain that queue from Godot's `frame_func`. The isolation model stays as it is, the check stays real, and asynchronous work works.

## Design

### Components

All new code lives in `Sources/SwiftGodot/Runtime/Core/`. The platform-neutral pieces are unit-tested on macOS; only the executor and its installation are Android-specific.

**`EngineThread`** records which thread is the engine thread and answers whether the caller is on it.

- `static func adopt()` records `pthread_self()` as the engine thread.
- `static var isCurrent: Bool` compares `pthread_self()` against the record with `pthread_equal`.
- The record is protected by a lock, which the macOS 14 deployment target requires in place of `Synchronization.Atomic`; an uncontended lock is cheap enough for the check path. Before any `adopt()` the answer is `false`.

**`MainActorJobQueue`** is a lock-protected FIFO of `UnownedJob`.

- `static func enqueue(_ job: UnownedJob)` may be called from any thread.
- `static func drainFrame()` must be called on the engine thread. It takes the jobs present at entry and runs each with `runSynchronously(on: MainActor.sharedUnownedExecutor)`. Jobs enqueued while draining wait for the next frame, so a job that re-enqueues itself cannot starve the frame.
- Running a job through `runSynchronously(on:)` installs the main executor as the current executor, so nested checks inside the job pass through the runtime's normal "current equals expected" path without reaching the executor.

**`EngineThreadMainExecutor`** (compiled only for `os(Android)`) is the main actor's executor, installed once per process through `_createExecutors(factory:)` with a factory that keeps `PlatformExecutorFactory.defaultExecutor` for global tasks.

- `enqueue` forwards to `MainActorJobQueue.enqueue`. Nothing is delegated to libdispatch, because its main queue is never drained.
- `isIsolatingCurrentContext()` returns `EngineThread.isCurrent`, so the runtime's check has a definite answer before it would reach `checkIsolated`.
- `checkIsolated()` is a fatal error off the engine thread, with the runtime's own wording, so worker-thread misuse still crashes rather than racing.
- `run()` and `stop()` are fatal errors: Godot owns the main loop and no async main exists.
- Installation happens first thing in `initializeSwiftModule`, before anything reads `MainActor.sharedUnownedExecutor`. Repeated entry points in one process are guarded so only the first installs.
- The first enqueue and the first isolation decision are written to the Android system log through a small C helper, so a device log shows the executor is live.

**Entry point changes** in `Sources/SwiftGodot/Runtime/EntryPoint.swift`:

- `GodotInterface` gains `register_main_loop_callbacks`, loaded with `loadOptional` so older engines still initialise.
- `initializeSwiftModule` calls `EngineThread.adopt()` on the loading thread, installs the executor on Android, and registers the main loop callbacks with the first library that initialises. Adopting the loading thread first means anything that touches the main actor between library load and `.scene` initialisation passes; on Android that thread is the UI thread, which is the correct answer during `Main::setup`.
- `extension_initialize` at the `.scene` level calls `EngineThread.adopt()` again. On Android this is the first callback on the renderer thread, and it precedes class registration, which is the first crash site in the issue.
- `startup_func` calls `EngineThread.adopt()` a final time as the authoritative main loop thread. `frame_func` calls `MainActorJobQueue.drainFrame()`. `shutdown_func` drains once more so jobs pending at exit run.

**Removal of the workaround.** `GodotMainActorAssumption.swift` and `_assumeGodotMainActor` are deleted. Every call site in the runtime, `Generator/Generator/ClassGen.swift` and `Sources/SwiftGodotMacroLibrary/MacroGodot.swift` return to `MainActor.assumeIsolated`. This removes the `unsafeBitCast` formulation that crashed the 6.3.3 compiler and restores the diff against upstream at those sites. Consumers recompile their macros with the package, so no compatibility shim is needed.

### Behaviour by platform

| | macOS and iOS | Android |
| --- | --- | --- |
| Engine thread | Process main thread | Renderer thread (`GLThread` or `VkThread`) |
| Custom main executor installed | No | Yes |
| Synchronous check on engine thread | Passes via dispatch | Passes via `isIsolatingCurrentContext` |
| Synchronous check on a worker thread | Crashes (dispatch assertion) | Crashes (runtime's own assertion, via delegated original) |
| Main-actor jobs | Run when the run loop spins | Run in `frame_func`, in FIFO order, at most one frame later |
| Main loop callbacks registered | Yes, drain is a no-op | Yes |

### Known limitation

The runtime's `Thread::onMainThread()` fast path cannot be replaced. On Android it answers true for the thread that loaded the Swift runtime, which is the Java UI thread. Swift code executing on that thread after startup would pass a main-actor check without reaching the executor. No SwiftGodot or Godot path runs extension code on the UI thread after `Main::setup`, so this is documented rather than mitigated. It is the same class of gap as any thread that libdispatch considers the main queue's owner.

### Error handling

- The SPI entry points are resolved at link time against the pinned toolchain, so a missing symbol is a build failure rather than a runtime condition.
- Missing `register_main_loop_callbacks` (engine older than 4.5): the interface field is `nil`, no callbacks are registered, and on Android a warning is printed through Godot's `print_warning` that main-actor jobs will not run. Synchronous checks still work because they depend only on the executor.
- `drainFrame()` called off the engine thread: precondition failure. It is only ever called from `frame_func` and `shutdown_func`.

## Testing

**Host unit tests** (`Tests/SwiftGodotUniversalTests`, run on macOS and in CI):

- `EngineThread`: `isCurrent` is false before adoption, true on the adopting thread, false on another thread, and follows re-adoption.
- `MainActorJobQueue`: FIFO order, jobs enqueued during a drain run on the next drain, drain is empty after running, enqueue from a background thread is visible to the next drain.

**Engine tests** (`Tests/SwiftGodotTestExtension`, run against the macOS test runner): a `@Godot` class starts a `Task` inside a callback, hops to a detached context and back to the main actor, and sets a flag. The test asserts the flag within a bounded number of frames. This proves main-actor jobs resume on the engine thread on Apple platforms, which the design relies on rather than changes.

**Android smoke test** (`Sources/AndroidTestExtension`, `Tests/AndroidTestProject`, `scripts/test-android-runtime`): `AndroidRuntimeProbe` gains three checks the GDScript scene reports on separate lines. Each corresponds to a crossing that fails today or is undrained today.

1. Construction: the probe is a `RefCounted` created from GDScript. This reaches `RefCounted.init(InitContext)`, the second crash site.
2. Generated API: the probe creates a `Node`, sets and reads its `name`, and frees it. This crosses declared isolation inside generated bindings.
3. Asynchronous hop: the probe starts a `Task` that hops off and back onto the main actor and records completion. The scene polls a property for up to sixty frames.

The CI script asserts all three lines. The existing `SWIFTGODOT_ANDROID_OK` line remains.

**Spike outcome.** The hook-based first attempt was carried through CI: `@convention(thin)` Swift hook functions do not compile on the 6.3.3 Android toolchain ("nontrivial thin function reference"), C trampolines with `__attribute__((swiftcall))` do, and with them construction and the generated API passed while the asynchronous hop never completed, which led to the routing finding above and the custom executor.

## Documentation

The Android guide gains a "Concurrency model" section stating: the engine thread is the main actor's thread; main-actor jobs run at frame boundaries; calling Swift Godot objects from a Godot worker thread or a `Thread.new()` script is a fatal error on every platform, as it is today on macOS.

## Out of scope

- Linux and Windows. The executor is written so enabling Linux is a platform-condition change, but it is neither built nor tested here.
- Removing the `@_spi(ExperimentalCustomExecutors)` dependency. Revisit when `ExecutorFactory` becomes public API.
- `cafecito-games/Foundry-Swift` carries the same model with 19 assumption sites. `EngineThread`, `MainActorJobQueue` and `ConcurrencyRuntimeHooks` depend only on the Swift runtime and the GDExtension main loop callbacks, so they port unchanged. That port is separate work.
- Hot reload of extensions on Android, which the engine does not support.
