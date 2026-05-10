# Swift 6 Concurrency Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Annotate every public type and function with explicit isolation and compile the entire SwiftGodot package clean under `.swiftLanguageMode(.v6)` with no `@preconcurrency` and no `-suppress-warnings`.

**Architecture:** `Wrapped` becomes `@MainActor`, cascading that isolation to all generated Godot class bindings. C callback entry points (called by Godot from its own C stack) become `nonisolated` with `MainActor.assumeIsolated` wrapping their bodies. Targets are migrated one at a time in dependency order so each compiles clean before the next begins.

**Tech Stack:** Swift 6.3, SwiftPM `.swiftLanguageMode(.v6)`, GDExtension C bridging layer

**Worktree:** `.worktrees/swift6-concurrency` on branch `feature/swift6-concurrency`

---

### Task 1: Flip `GDExtension` to Swift 6

**Goal:** Compile the `GDExtension` target clean under `.swiftLanguageMode(.v6)`.

**Files:**
- Modify: `Package.swift` (one line)

**Acceptance Criteria:**
- [ ] `GDExtension` target builds with zero errors and zero warnings under `.v6`

**Verify:** `swift build --target GDExtension 2>&1 | grep -E "error:|warning:|complete"` → `Build of target: 'GDExtension' complete!`

**Steps:**

- [ ] **Step 1: Flip the language mode in `Package.swift`**

Find the `GDExtension` target (around line 160 in Package.swift):
```swift
// Before
.target(
    name: "GDExtension",
    swiftSettings: [.swiftLanguageMode(.v5)]
),

// After
.target(
    name: "GDExtension",
    swiftSettings: [.swiftLanguageMode(.v6)]
),
```

- [ ] **Step 2: Build and fix**

```bash
swift build --target GDExtension 2>&1 | grep -E "error:|warning:"
```

GDExtension is pure C bridging headers with minimal Swift — expect zero or trivial issues. Fix any `Sendable` warnings on public types the compiler surfaces.

- [ ] **Step 3: Commit**

```bash
git add Package.swift
git commit -m "Migrate GDExtension target to Swift 6"
```

---

### Task 2: Flip `ExtensionApi` and `ExtensionApiJson` to Swift 6

**Goal:** Compile both `ExtensionApi` and `ExtensionApiJson` targets clean under `.swiftLanguageMode(.v6)`.

**Files:**
- Modify: `Package.swift` (two targets)
- Modify: `Sources/ExtensionApi/ApiJsonModel.swift` (add `Sendable` conformances)
- Modify: `Sources/ExtensionApi/ApiJsonModel+Extra.swift` (if needed)

**Acceptance Criteria:**
- [ ] `ExtensionApi` builds clean under `.v6`
- [ ] `ExtensionApiJson` builds clean under `.v6`
- [ ] No `@preconcurrency` added

**Verify:** `swift build --target ExtensionApi 2>&1 | grep -E "error:|warning:|complete"` → `Build of target: 'ExtensionApi' complete!`

**Steps:**

- [ ] **Step 1: Flip both targets in `Package.swift`**

```swift
// ExtensionApi target
swiftSettings: [.swiftLanguageMode(.v6)]

// ExtensionApiJson target  
swiftSettings: [.swiftLanguageMode(.v6)]
```

- [ ] **Step 2: Build and collect errors**

```bash
swift build --target ExtensionApi 2>&1 | grep "error:"
```

The types in `ApiJsonModel.swift` are all `Codable` structs. Swift 6 requires `Sendable` for types crossing concurrency boundaries. The fix is retroactive conformance — add at the bottom of `ApiJsonModel.swift`:

```swift
extension JGodotExtensionAPI: Sendable {}
extension JGodotHeader: Sendable {}
extension JGodotBuiltinClassSize: Sendable {}
extension JGodotBuiltinClassMemberOffset: Sendable {}
extension JGodotBuiltinClassMemberOffsetClass: Sendable {}
extension JGodotMember: Sendable {}
// ... add for every public struct the compiler flags
```

Apply the same pattern for every type the compiler flags. Only add conformances for types that are actually flagged — do not pre-emptively annotate every type.

- [ ] **Step 3: Commit**

```bash
git add Package.swift Sources/ExtensionApi/
git commit -m "Migrate ExtensionApi targets to Swift 6"
```

---

### Task 3: Flip `SwiftGodotMacroLibrary` and `SwiftGodotTestMacrosLibrary` to Swift 6

**Goal:** Compile both macro targets clean under `.swiftLanguageMode(.v6)`.

**Files:**
- Modify: `Package.swift` (two targets)
- Modify: `Sources/SwiftGodotMacroLibrary/*.swift` (fix any compiler-surfaced issues)

**Acceptance Criteria:**
- [ ] `SwiftGodotMacroLibrary` builds clean under `.v6`
- [ ] `SwiftGodotTestMacrosLibrary` builds clean under `.v6`
- [ ] No `@preconcurrency` added

**Verify:** `swift build --target SwiftGodotMacroLibrary 2>&1 | grep -E "error:|warning:|complete"` → `Build of target: 'SwiftGodotMacroLibrary' complete!`

**Steps:**

- [ ] **Step 1: Flip both targets in `Package.swift`**

```swift
// SwiftGodotMacroLibrary macro target
swiftSettings: [.swiftLanguageMode(.v6)]

// SwiftGodotTestMacrosLibrary macro target
swiftSettings: [.swiftLanguageMode(.v6)]
```

- [ ] **Step 2: Build macro library and fix issues**

```bash
swift build --target SwiftGodotMacroLibrary 2>&1 | grep "error:"
```

Macro implementations run at compile time on the host and don't interact with Godot's threading model. Issues will be isolated to `Sendable` conformances on closure types or captured values in expansion functions. Fix each one the compiler reports — typically by adding `@Sendable` to closure parameters or `Sendable` conformance to types used in closures.

- [ ] **Step 3: Build test macro library and fix issues**

```bash
swift build --target SwiftGodotTestMacrosLibrary 2>&1 | grep "error:"
```

Apply the same pattern as Step 2.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources/SwiftGodotMacroLibrary/
git commit -m "Migrate macro targets to Swift 6"
```

---

### Task 4: Update `ClassGen.swift` to emit Swift 6 compliant code, flip `Generator` and `EntryPointGenerator` to Swift 6

**Goal:** The Generator emits `nonisolated` on the three generated declaration kinds that cross isolation boundaries, and both Generator executables compile clean under `.v6`.

**Files:**
- Modify: `Generator/Generator/ClassGen.swift` (three changes)
- Modify: `Package.swift` (two targets)

**Acceptance Criteria:**
- [ ] Generated `_proxy` functions have `nonisolated` and `MainActor.assumeIsolated` wrapper
- [ ] Generated `getVirtualDispatcher` has `nonisolated`
- [ ] Generated `godotClassName` vars have `nonisolated`
- [ ] `Generator` and `EntryPointGenerator` build clean under `.v6`

**Verify:** `swift build --target Generator 2>&1 | grep -E "error:|warning:|complete"` → `Build of target: 'Generator' complete!`

**Steps:**

- [ ] **Step 1: Add `nonisolated` to `_proxy` function emission in `ClassGen.swift`**

In `Generator/Generator/ClassGen.swift` around line 91, the proxy function emission uses the `Printer`'s `callAsFunction(_:block:)` which calls `b()` internally and indents the block. Change:

```swift
// Before (line 91)
p ("func _\(cdef.name)_proxy\(method.name) (instance: UnsafeMutableRawPointer?, args: UnsafePointer<UnsafeRawPointer?>?, retPtr: UnsafeMutableRawPointer?)") {
    p ("guard let instance else { return }")
    // ... rest of body
}

// After
p ("nonisolated func _\(cdef.name)_proxy\(method.name) (instance: UnsafeMutableRawPointer?, args: UnsafePointer<UnsafeRawPointer?>?, retPtr: UnsafeMutableRawPointer?)") {
    p ("MainActor.assumeIsolated") {
        p ("guard let instance else { return }")
        // ... rest of body unchanged
    }
}
```

The `Printer.callAsFunction(_:block:)` method (defined in `Printer.swift`) calls `b()` which appends ` {`, indents, runs the block, de-indents, and appends `}`. Wrapping the inner content in another `p("MainActor.assumeIsolated") { ... }` adds one more level of indentation around the full existing body.

- [ ] **Step 2: Add `nonisolated` to `getVirtualDispatcher` emission**

Around line 307 in `ClassGen.swift`:

```swift
// Before
p ("@_spi(SwiftGodotRuntimePrivate) open override class func getVirtualDispatcher(name: StringName) -> GDExtensionClassCallVirtual?") {

// After
p ("@_spi(SwiftGodotRuntimePrivate) nonisolated open override class func getVirtualDispatcher(name: StringName) -> GDExtensionClassCallVirtual?") {
```

- [ ] **Step 3: Add `nonisolated` to `godotClassName` emission**

Around lines 628 and 631 in `ClassGen.swift`:

```swift
// Before (line 628)
p ("override open class var godotClassName: StringName { \"\(cdef.name)\" }")

// After
p ("nonisolated override open class var godotClassName: StringName { \"\(cdef.name)\" }")

// Before (line 631)
p ("override open class var godotClassName: StringName { className }")

// After
p ("nonisolated override open class var godotClassName: StringName { className }")
```

- [ ] **Step 4: Flip both executable targets in `Package.swift`**

```swift
// EntryPointGenerator target
swiftSettings: [.swiftLanguageMode(.v6)]

// Generator target
swiftSettings: [
    .swiftLanguageMode(.v6)
    // Keep any existing defines
]
```

- [ ] **Step 5: Build and fix remaining issues**

```bash
swift build --target Generator 2>&1 | grep "error:"
swift build --target EntryPointGenerator 2>&1 | grep "error:"
```

Fix any remaining issues the compiler surfaces in the generator code itself.

- [ ] **Step 6: Commit**

```bash
git add Generator/Generator/ClassGen.swift Package.swift
git commit -m "Update ClassGen to emit Swift 6 nonisolated annotations, migrate Generator targets to Swift 6"
```

---

### Task 5: Fix `NIOLock.swift` — remove `@preconcurrency import`

**Goal:** Remove all `@preconcurrency import` statements from `NIOLock.swift` and compile clean.

**Files:**
- Modify: `Sources/SwiftGodotRuntime/Core/NIOLock.swift`

**Acceptance Criteria:**
- [ ] Zero `@preconcurrency` occurrences in `NIOLock.swift`
- [ ] File compiles (will be verified as part of Task 7 when the target flips to `.v6`)

**Verify:** `grep "@preconcurrency" Sources/SwiftGodotRuntime/Core/NIOLock.swift` → no output

**Steps:**

- [ ] **Step 1: Remove `@preconcurrency` from the platform imports**

In `Sources/SwiftGodotRuntime/Core/NIOLock.swift`, lines 20–27 currently read:

```swift
#elseif canImport(Glibc)
@preconcurrency import Glibc
#elseif canImport(Musl)
@preconcurrency import Musl
#elseif canImport(Bionic)
@preconcurrency import Bionic
#elseif canImport(WASILibc)
@preconcurrency import WASILibc
```

Change to plain imports:

```swift
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Bionic)
import Bionic
#elseif canImport(WASILibc)
import WASILibc
```

- [ ] **Step 2: Note on `LockPrimitive` (`pthread_mutex_t`)**

`LockStorage` (the internal wrapper around `pthread_mutex_t`) is already `extension LockStorage: Sendable {}` and `NIOLock` is already `@unchecked Sendable`. The `@preconcurrency import` was suppressing the implicit warning that `pthread_mutex_t` itself is not `Sendable`. With plain imports, if Swift 6 flags the `pthread_mutex_t` stored inside `LockStorage`, the fix is to mark the stored property `nonisolated(unsafe)`:

```swift
// In LockStorage, if flagged:
final class LockStorage<Value>: ManagedBuffer<Value, LockPrimitive> {
    // If the compiler flags LockPrimitive, add:
    nonisolated(unsafe) var lockPrimitive: LockPrimitive { ... }
}
```

Only apply `nonisolated(unsafe)` if the compiler actually flags it — do not pre-emptively add it.

- [ ] **Step 3: Commit**

```bash
git add Sources/SwiftGodotRuntime/Core/NIOLock.swift
git commit -m "Remove @preconcurrency imports from NIOLock"
```

---

### Task 6: Apply `@MainActor` to `Wrapped` and annotate C callback boundaries

**Goal:** `Wrapped` is `@MainActor`. The six C callback boundary functions are `nonisolated` with `MainActor.assumeIsolated`. Class-level registration hooks in `Wrapped` are `nonisolated`.

**Files:**
- Modify: `Sources/SwiftGodotRuntime/Core/Wrapped.swift`

**Acceptance Criteria:**
- [ ] `open class Wrapped` declaration has `@MainActor`
- [ ] `createFunc`, `recreateFunc`, `freeFunc`, `validatePropertyFunc`, `invokeWrappedCallable`, and `getVirtual` are all `nonisolated` with `MainActor.assumeIsolated` bodies
- [ ] `godotClassName`, `classInitializer`, `classInitializationLevel`, `implementedOverrides()`, `getVirtualDispatcher()`, `initClass()` are all `nonisolated` on `Wrapped`
- [ ] `GDExtensionInstanceBindingCallbacks` static vars use `nonisolated` closures
- [ ] No `@preconcurrency` added

**Verify:** Will be verified in Task 7 when the target compiles under `.v6`

**Steps:**

- [ ] **Step 1: Add `@MainActor` to `Wrapped` class declaration**

Around line 150 in `Sources/SwiftGodotRuntime/Core/Wrapped.swift`:

```swift
// Before
open class Wrapped: Equatable, Identifiable, Hashable {

// After
@MainActor
open class Wrapped: Equatable, Identifiable, Hashable {
```

- [ ] **Step 2: Mark class-level registration hooks `nonisolated` on `Wrapped`**

These are called during engine initialization, not from the main run loop:

```swift
// implementedOverrides (~line 193)
nonisolated open class func implementedOverrides() -> [StringName] { return [] }

// getVirtualDispatcher (~line 201)
@_spi(SwiftGodotRuntimePrivate) nonisolated open class func getVirtualDispatcher(name: StringName) -> GDExtensionClassCallVirtual? {
    pd ("SWARN: getVirtualDispatcher (\"\(name)\") reached Wrapped on class \(self)")
    return nil
}

// initClass (~line 208)
nonisolated public class func initClass() {}

// godotClassName (~line 394)
nonisolated open class var godotClassName: StringName { "" }

// classInitializer (~line 398)
nonisolated open class var classInitializer: Void { () }

// classInitializationLevel (~line 401)
nonisolated open class var classInitializationLevel: ExtensionInitializationLevel { .scene }
```

- [ ] **Step 3: Make `createFunc` `nonisolated` with `assumeIsolated`**

Around line 1022:

```swift
// Before
func createFunc(_ userData: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    // ... body
}

// After
nonisolated func createFunc(_ userData: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    MainActor.assumeIsolated {
        // ... body unchanged
    }
}
```

- [ ] **Step 4: Make `recreateFunc` `nonisolated` with `assumeIsolated`**

Around line 1057:

```swift
// Before
func recreateFunc(_ userData: UnsafeMutableRawPointer?, godotObjectHandle: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    // ... body
}

// After
nonisolated func recreateFunc(_ userData: UnsafeMutableRawPointer?, godotObjectHandle: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    MainActor.assumeIsolated {
        // ... body unchanged
    }
}
```

- [ ] **Step 5: Make `freeFunc` `nonisolated` with `assumeIsolated`**

Around line 1094:

```swift
// Before
func freeFunc (_ userData: UnsafeMutableRawPointer?, _ objectHandle: UnsafeMutableRawPointer?) {
    // ... body
}

// After
nonisolated func freeFunc (_ userData: UnsafeMutableRawPointer?, _ objectHandle: UnsafeMutableRawPointer?) {
    MainActor.assumeIsolated {
        // ... body unchanged
    }
}
```

- [ ] **Step 6: Make `validatePropertyFunc` `nonisolated` with `assumeIsolated`**

Around line 1117:

```swift
// Before
func validatePropertyFunc(ptr: UnsafeMutableRawPointer?, _info: UnsafeMutablePointer<GDExtensionPropertyInfo>?) -> UInt8 {
    // ... body
}

// After
nonisolated func validatePropertyFunc(ptr: UnsafeMutableRawPointer?, _info: UnsafeMutablePointer<GDExtensionPropertyInfo>?) -> UInt8 {
    MainActor.assumeIsolated {
        // ... body unchanged
    }
}
```

- [ ] **Step 7: Make `invokeWrappedCallable` `nonisolated` with `assumeIsolated`**

Around line 1376:

```swift
// Before
func invokeWrappedCallable(wrapperPtr: UnsafeMutableRawPointer?, pargs: UnsafePointer<UnsafeRawPointer?>?, argc: Int64, retPtr: UnsafeMutableRawPointer?, err: UnsafeMutablePointer<GDExtensionCallError>?) {
    // ... body
}

// After
nonisolated func invokeWrappedCallable(wrapperPtr: UnsafeMutableRawPointer?, pargs: UnsafePointer<UnsafeRawPointer?>?, argc: Int64, retPtr: UnsafeMutableRawPointer?, err: UnsafeMutablePointer<GDExtensionCallError>?) {
    MainActor.assumeIsolated {
        // ... body unchanged
    }
}
```

- [ ] **Step 8: Make `getVirtual` instance method `nonisolated` with `assumeIsolated`**

Around line 529 (this is an instance method on an internal struct used in class registration):

```swift
// Before
func getVirtual(_ userData: UnsafeMutableRawPointer?, _ name: GDExtensionConstStringNamePtr?) -> GDExtensionClassCallVirtual? {
    // ... body
}

// After
nonisolated func getVirtual(_ userData: UnsafeMutableRawPointer?, _ name: GDExtensionConstStringNamePtr?) -> GDExtensionClassCallVirtual? {
    MainActor.assumeIsolated {
        // ... body unchanged
    }
}
```

- [ ] **Step 9: Commit**

```bash
git add Sources/SwiftGodotRuntime/Core/Wrapped.swift
git commit -m "Apply @MainActor to Wrapped, annotate C callback boundaries as nonisolated"
```

---

### Task 7: Flip `SwiftGodotRuntime` to Swift 6, remove `-suppress-warnings`

**Goal:** `SwiftGodotRuntime` compiles clean under `.swiftLanguageMode(.v6)` with zero warnings and without `-suppress-warnings`.

**Files:**
- Modify: `Package.swift` (remove `unsafeFlags`, flip language mode)
- Modify: `Sources/SwiftGodotRuntime/Core/*.swift` (fix remaining compiler issues)

**Acceptance Criteria:**
- [ ] `-suppress-warnings` removed from `SwiftGodotRuntime` target
- [ ] `SwiftGodotRuntime` builds with zero errors and zero warnings under `.v6`
- [ ] No `@preconcurrency` added

**Verify:** `swift build --target SwiftGodotRuntime 2>&1 | grep -E "error:|warning:|complete"` → `Build of target: 'SwiftGodotRuntime' complete!`

**Steps:**

- [ ] **Step 1: Update `SwiftGodotRuntime` target in `Package.swift`**

Find the `SwiftGodotRuntime` target (around line 196). Change:

```swift
// Before
.target(
    name: "SwiftGodotRuntime",
    dependencies: ["GDExtension"],
    swiftSettings: [
        .define("CUSTOM_BUILTIN_IMPLEMENTATIONS"),
        .define("SWIFTGODOT_WITH_MULTI_PROCESS", .when(traits: [withMultiProcessTrait])),
        .unsafeFlags(
            [
                "-suppress-warnings",
                "-Xfrontend", "-conditional-runtime-records",
                "-Xfrontend", "-internalize-at-link",
                "-Xfrontend", "-lto=llvm-full",
            ]
        ),
        .swiftLanguageMode(.v5),
    ],
    plugins: ["CodeGeneratorPlugin", "SwiftGodotMacroLibrary"]
),

// After
.target(
    name: "SwiftGodotRuntime",
    dependencies: ["GDExtension"],
    swiftSettings: [
        .define("CUSTOM_BUILTIN_IMPLEMENTATIONS"),
        .define("SWIFTGODOT_WITH_MULTI_PROCESS", .when(traits: [withMultiProcessTrait])),
        .unsafeFlags(
            [
                "-Xfrontend", "-conditional-runtime-records",
                "-Xfrontend", "-internalize-at-link",
                "-Xfrontend", "-lto=llvm-full",
            ]
        ),
        .swiftLanguageMode(.v6),
    ],
    plugins: ["CodeGeneratorPlugin", "SwiftGodotMacroLibrary"]
),
```

- [ ] **Step 2: Build and collect all errors**

```bash
swift build --target SwiftGodotRuntime 2>&1 | grep "error:"
```

Expected categories of errors with their fixes:

**a) `Sendable` on value types used across boundaries** — add retroactive `Sendable` conformances:
```swift
extension PropInfo: Sendable {}
extension IncorrectInitializationOrderError: Sendable {}
extension ArgumentAccessError: Sendable {}
// etc. for any flagged type
```

**b) `@MainActor`-isolated stored property accessed from `nonisolated` context** — if any stored property on `Wrapped` is accessed in a `nonisolated` boundary function, either move it to the `assumeIsolated` closure body (already done in Task 6) or mark it `nonisolated(unsafe)` if it's a static that must be accessible before actor isolation is established.

**c) Closures in C struct literal fields** — `GDExtensionInstanceBindingCallbacks` closures need `nonisolated` keyword if the compiler flags them:
```swift
// If flagged, add nonisolated to the closure bodies inside GDExtensionInstanceBindingCallbacks(...)
```

**d) `ClassInfo<T>` methods** — `ClassInfo` is a class parameterized over `Object`. With `Object` being `@MainActor`, `ClassInfo<T>` methods that take closures may need `@MainActor` on those closures:
```swift
// If registerMethod closure parameter is flagged:
public func registerMethod(name: StringName, flags: MethodFlags, returnValue: PropInfo?, arguments: [PropInfo], function: @escaping @MainActor (T) -> (borrowing Arguments) -> Variant?) {
```

Fix each error the compiler reports following these patterns. Do not guess ahead — let the compiler guide what needs changing.

- [ ] **Step 3: Verify zero warnings**

```bash
swift build --target SwiftGodotRuntime 2>&1 | grep "warning:"
```

Must produce no output.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources/SwiftGodotRuntime/
git commit -m "Migrate SwiftGodotRuntime to Swift 6, remove -suppress-warnings"
```

---

### Task 8: Flip `SwiftGodot` to Swift 6, remove `-suppress-warnings`

**Goal:** `SwiftGodot` compiles clean under `.swiftLanguageMode(.v6)` with zero warnings and without `-suppress-warnings`.

**Files:**
- Modify: `Package.swift` (remove `unsafeFlags`, flip language mode)
- Modify: `Sources/SwiftGodot/*.swift` (hand-written files)
- Modify: `Sources/SwiftGodot/Extensions/*.swift`

**Acceptance Criteria:**
- [ ] `-suppress-warnings` removed from `SwiftGodot` target
- [ ] `SwiftGodot` builds with zero errors and zero warnings under `.v6`
- [ ] No `@preconcurrency` added

**Verify:** `swift build --target SwiftGodot 2>&1 | grep -E "error:|warning:|complete"` → `Build of target: 'SwiftGodot' complete!`

**Steps:**

- [ ] **Step 1: Update `SwiftGodot` target in `Package.swift`**

Find the `SwiftGodot` target (around line 219). Change:

```swift
// Before
.target(
    name: "SwiftGodot",
    dependencies: ["GDExtension", "SwiftGodotRuntime"],
    swiftSettings: [
        .swiftLanguageMode(.v5),
        .define("CUSTOM_BUILTIN_IMPLEMENTATIONS"),
        .define("SWIFTGODOT_WITH_MULTI_PROCESS", .when(traits: [withMultiProcessTrait])),
        .unsafeFlags(["-suppress-warnings"])
    ],
    plugins: ["CodeGeneratorPlugin"]
),

// After
.target(
    name: "SwiftGodot",
    dependencies: ["GDExtension", "SwiftGodotRuntime"],
    swiftSettings: [
        .swiftLanguageMode(.v6),
        .define("CUSTOM_BUILTIN_IMPLEMENTATIONS"),
        .define("SWIFTGODOT_WITH_MULTI_PROCESS", .when(traits: [withMultiProcessTrait])),
    ],
    plugins: ["CodeGeneratorPlugin"]
),
```

- [ ] **Step 2: Build and fix hand-written extension files**

```bash
swift build --target SwiftGodot 2>&1 | grep "error:"
```

The hand-written files to audit are:
- `Sources/SwiftGodot/Extensions/NodeExtensions.swift` — `BindNode<Value: Node>` struct; if `Value` is `@MainActor` this struct may need isolation annotation
- `Sources/SwiftGodot/Extensions/Various.swift`
- `Sources/SwiftGodot/VariantConvertibeNode.swift`
- `Sources/SwiftGodot/GodotInterface.swift`

For `BindNode`, if flagged:
```swift
// BindNode wraps a Node (which is @MainActor) — mark the struct @MainActor
@MainActor
public struct BindNode<Value: Node> { ... }
```

Fix each error the compiler reports. The generated code inherits `@MainActor` from `Wrapped` automatically — issues will be in the small number of hand-written files.

- [ ] **Step 3: Verify zero warnings**

```bash
swift build --target SwiftGodot 2>&1 | grep "warning:"
```

Must produce no output.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources/SwiftGodot/
git commit -m "Migrate SwiftGodot to Swift 6, remove -suppress-warnings"
```

---

### Task 9: Flip remaining targets to Swift 6

**Goal:** All remaining targets — `SimpleExtension`, `ManualExtension`, `SwiftGodotTestMacros`, `SwiftGodotTestExtension`, `SwiftGodotUniversalTests`, `SwiftGodotMacrosTests`, `SwiftGodotTestRunner` — compile clean under `.v6`.

**Files:**
- Modify: `Package.swift` (all remaining `.swiftLanguageMode(.v5)` entries)
- Modify: `Tests/SwiftGodotTestExtension/*.swift` (fix call sites if needed)
- Modify: `Sources/SimpleExtension/*.swift` (fix call sites if needed)
- Modify: `Sources/ManualExtension/*.swift` (fix call sites if needed)

**Acceptance Criteria:**
- [ ] Zero remaining `.swiftLanguageMode(.v5)` in `Package.swift`
- [ ] All targets build clean under `.v6`
- [ ] No `@preconcurrency` added anywhere

**Verify:** `grep "swiftLanguageMode(.v5)" Package.swift` → no output

**Steps:**

- [ ] **Step 1: Flip all remaining targets in `Package.swift`**

Replace every remaining `.swiftLanguageMode(.v5)` with `.swiftLanguageMode(.v6)`. As of writing this plan, the remaining targets are: `EntryPointGenerator`, `ExtensionApi`, `ExtensionApiJson`, `SwiftGodotTestMacros`, `SimpleExtension`, `ManualExtension`, `SwiftGodotUniversalTests`, `SwiftGodotTestRunner`, `SwiftGodotTestExtension`, `SwiftGodotMacrosTests` (the ones not already flipped in Tasks 1–8).

```bash
# Verify which are still on v5
grep -n "swiftLanguageMode(.v5)" Package.swift
```

Change each remaining occurrence from `.v5` to `.v6`.

- [ ] **Step 2: Build each remaining target and fix issues**

```bash
swift build --target SimpleExtension 2>&1 | grep "error:"
swift build --target ManualExtension 2>&1 | grep "error:"
swift build --target SwiftGodotTestMacros 2>&1 | grep "error:"
swift build --target SwiftGodotTestExtension 2>&1 | grep "error:"
swift build --target SwiftGodotTestRunner 2>&1 | grep "error:"
```

These targets consume the now-annotated SwiftGodot API. The most common issue will be calls to `@MainActor`-isolated Godot APIs from non-isolated contexts. The fix is to add `@MainActor` to the call site function or class, or wrap the call in `MainActor.assumeIsolated { }` where the call is inside a known-main-thread callback.

For extension entry points (e.g. `SimpleExtension`), the `#initSwiftExtension` macro already runs on the main thread — verify the expanded code is compatible.

- [ ] **Step 3: Commit**

```bash
git add Package.swift Tests/ Sources/SimpleExtension/ Sources/ManualExtension/ Sources/SwiftGodotTestMacros/
git commit -m "Migrate all remaining targets to Swift 6"
```

---

### Task 10: Final verification and PR

**Goal:** The entire package builds and tests pass with zero errors, zero warnings, and no `@preconcurrency` anywhere.

**Files:** No new changes — verification only, then PR creation.

**Acceptance Criteria:**
- [ ] `swift build` completes clean
- [ ] `swift test` passes
- [ ] Zero `@preconcurrency` occurrences anywhere in `Sources/`
- [ ] Zero `-suppress-warnings` in `Package.swift`
- [ ] Zero `.swiftLanguageMode(.v5)` in `Package.swift`

**Verify:** `swift test 2>&1 | tail -5` → test suite passes

**Steps:**

- [ ] **Step 1: Full build clean check**

```bash
swift build 2>&1 | grep -E "error:|warning:"
```

Must produce no output.

- [ ] **Step 2: Run the test suite**

```bash
swift test 2>&1 | tail -20
```

`SwiftGodotUniversalTests` and `SwiftGodotMacrosTests` run without a live Godot process. All tests must pass.

- [ ] **Step 3: Audit for forbidden patterns**

```bash
grep -r "@preconcurrency" Sources/ Generator/ Tests/
grep "suppress-warnings" Package.swift
grep "swiftLanguageMode(.v5)" Package.swift
```

All three commands must produce no output.

- [ ] **Step 4: Create PR**

```bash
gh pr create \
  --title "Swift 6 concurrency audit: @MainActor on Wrapped, explicit isolation on all public API" \
  --body "$(cat <<'EOF'
## Summary

- Applies `@MainActor` to `Wrapped`, cascading to all generated Godot class bindings
- Annotates the six C callback boundary functions (`createFunc`, `recreateFunc`, `freeFunc`, `validatePropertyFunc`, `invokeWrappedCallable`, `getVirtual`) as `nonisolated` with `MainActor.assumeIsolated`
- Updates `ClassGen.swift` to emit `nonisolated` on generated `_proxy` functions, `getVirtualDispatcher`, and `godotClassName`
- Removes `@preconcurrency import` from `NIOLock.swift`
- Removes `-suppress-warnings` from `SwiftGodotRuntime` and `SwiftGodot`
- Flips all targets from `.swiftLanguageMode(.v5)` to `.swiftLanguageMode(.v6)`

## Test plan
- [ ] `swift build` — zero errors, zero warnings
- [ ] `swift test` — all tests pass
- [ ] `grep -r "@preconcurrency" Sources/ Generator/ Tests/` — no output
- [ ] `grep "suppress-warnings" Package.swift` — no output
- [ ] `grep "swiftLanguageMode(.v5)" Package.swift` — no output
EOF
)"
```
