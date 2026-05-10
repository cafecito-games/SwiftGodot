# Swift 6 Concurrency Audit — Design Spec

**Date:** 2026-05-09  
**Goal:** Annotate every public type and function with explicit isolation and compile the entire SwiftGodot package clean under `.swiftLanguageMode(.v6)`.

---

## Isolation Model

`Wrapped` is annotated `@MainActor`. All generated Godot class bindings (`Object`, `Node`, `RefCounted`, and every subclass) inherit this isolation automatically — no per-subclass annotation is needed. Godot's single-threaded main loop is the enforcement mechanism; Swift's type system makes it a compile-time guarantee.

Three categories of declarations:

| Category | Annotation | Rationale |
|---|---|---|
| `Wrapped` class body | `@MainActor` | All Godot object interaction happens on the main thread |
| C callback entry points (`createFunc`, `recreateFunc`, `freeFunc`, `validatePropertyFunc`, `invokeWrappedCallable`, `getVirtual`, generated `_proxy` functions) | `nonisolated` + `MainActor.assumeIsolated` | Called by Godot from its C stack; Godot guarantees main-thread delivery, so `assumeIsolated` is correct and crashes in debug if violated |
| Class-level registration hooks (`godotClassName`, `classInitializer`, `getVirtualDispatcher`) | `nonisolated` | Called during engine init, not the main loop; pure metadata lookups with no Godot object mutation |

Value types (`struct`, `enum`) and protocols carrying no Godot object state get explicit `Sendable` conformance. Types that wrap raw C pointers get `@unchecked Sendable` with the threading invariant documented at the declaration site.

### Hard Constraints

- **No `@preconcurrency` anywhere** — not on imports, not on declarations. Every concurrency assertion must be explicit and scoped.
- **No `-suppress-warnings`** — both `unsafeFlags` blocks are removed from `Package.swift` as part of this work.
- **No `@preconcurrency import`** — `NIOLock.swift` replaces `@preconcurrency import Glibc/Musl/Bionic/WASILibc` with `nonisolated(unsafe)` on the C primitive declaration site.

---

## Generator Changes

The Generator (`ClassGen.swift`, `MethodGen.swift`) produces hundreds of class files. Correct output here means every generated class is automatically conformant.

### `ClassGen.swift` — three changes

**1. `_proxy` functions** — virtual method dispatch callbacks registered with Godot by C function pointer:

```swift
// Before
func _ClassName_proxyMethodName(instance: UnsafeMutableRawPointer?, args: ..., retPtr: ...) {
    // body
}

// After
nonisolated func _ClassName_proxyMethodName(instance: UnsafeMutableRawPointer?, args: ..., retPtr: ...) {
    MainActor.assumeIsolated {
        // body
    }
}
```

**2. `getVirtualDispatcher`** — class-level virtual lookup hook:

```swift
// Before
@_spi(SwiftGodotRuntimePrivate) open override class func getVirtualDispatcher(name: StringName) -> GDExtensionClassCallVirtual?

// After
@_spi(SwiftGodotRuntimePrivate) nonisolated open override class func getVirtualDispatcher(name: StringName) -> GDExtensionClassCallVirtual?
```

**3. `godotClassName` static var** — called during class registration:

```swift
// Before
override open class var godotClassName: StringName { ... }

// After
nonisolated override open class var godotClassName: StringName { ... }
```

The `shared` singleton accessor stays `@MainActor` (inherited) — it calls `gi.global_get_singleton` which requires the main thread.

---

## `Wrapped.swift` Boundary Fixes

Six free functions are called by Godot from its C stack. All become `nonisolated` with `MainActor.assumeIsolated` wrapping their bodies:

| Function | Line | Purpose |
|---|---|---|
| `createFunc` | ~1022 | Godot creates a new Swift-registered instance |
| `recreateFunc` | ~1057 | Godot recreates an instance after scene reload |
| `freeFunc` | ~1094 | Godot frees a Swift-registered instance |
| `validatePropertyFunc` | ~1117 | Godot validates an exported property |
| `invokeWrappedCallable` | ~1376 | Godot invokes a Swift `Callable` |
| `getVirtual` (instance method) | ~529 | Godot looks up a virtual method pointer |

`GDExtensionInstanceBindingCallbacks` static vars (`bindingCallback`, `userTypeBindingCallback`, `frameworkTypeBindingCallback`) contain closures assigned to C structs — these closures become `nonisolated`.

`WrappedReference` (the internal ref-counting wrapper) gets `nonisolated` on methods used inside the C callback boundary functions.

---

## `NIOLock.swift` Fix

Replace:
```swift
@preconcurrency import Glibc  // (and Musl, Bionic, WASILibc)
```

With plain imports and `nonisolated(unsafe)` on the C primitive where Sendable is required:
```swift
import Glibc
```

The `LockStorage` and `NIOLock` types are already `@unchecked Sendable` — the `@preconcurrency import` was only suppressing warnings from the undecorated C type crossing the Sendable boundary.

---

## Target Migration Order

Each target must produce zero errors and zero warnings before the next begins.

1. **`GDExtension`** — C bridging headers, expected to be clean immediately
2. **`ExtensionApi` + `ExtensionApiJson`** — data model structs; add `Sendable` to public types crossing module boundaries
3. **`SwiftGodotMacroLibrary` + `SwiftGodotTestMacrosLibrary`** — compile-time macros on the host; add `Sendable` on AST node types as needed
4. **`Generator` + `EntryPointGenerator`** — standalone executables; self-contained fixes including the ClassGen changes above
5. **`SwiftGodotRuntime`** — `@MainActor` on `Wrapped`, `nonisolated` + `assumeIsolated` on the six boundary functions, `nonisolated(unsafe)` on `NIOLock`'s C primitive, remove `-suppress-warnings`
6. **`SwiftGodot`** — inherits `@MainActor` through `Wrapped`; remove `-suppress-warnings`; fix hand-written extensions
7. **`SimpleExtension`, `ManualExtension`, `SwiftGodotTestMacros`, `SwiftGodotTestExtension`, test targets** — consume the annotated API; fix call sites

`Package.swift`: remove `-suppress-warnings` `unsafeFlags` blocks and replace each `.swiftLanguageMode(.v5)` with `.swiftLanguageMode(.v6)` as each target is confirmed clean.

---

## Verification

**Per-target gate:**
```bash
swift build --target <TargetName>
```
Zero errors, zero warnings before proceeding.

**Final gate:**
```bash
swift test
```
`SwiftGodotUniversalTests` and `SwiftGodotMacrosTests` cover the broadest surface without a live Godot process.

No new tests are required — this is an annotation pass, not a behavior change. Clean compilation under `.v6` is the success criterion.
