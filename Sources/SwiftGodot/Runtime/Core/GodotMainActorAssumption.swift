//
// Assuming main-actor isolation on the thread Godot calls extensions from.
//

/// Runs `body` as though it were isolated to the main actor.
///
/// Godot always calls into an extension from the thread that runs the engine,
/// so the assumption holds on every platform. Whether it can be *verified*
/// differs.
///
/// On Apple platforms the engine runs on the process main thread, which is also
/// libdispatch's main queue, so `MainActor.assumeIsolated` confirms it cheaply.
///
/// On Android the engine runs on its own thread — `GLThread` — while
/// libdispatch's main queue has no owning thread at all, because nothing calls
/// `dispatch_main()`. `MainActor.assumeIsolated` resolves to
/// `dispatch_assert_queue`, which aborts the process with SIGILL rather than
/// answering the question. Every call would take the whole engine down, so
/// there the assumption is taken without asking.
/// Public because `@Godot` expands to a call to it inside a consumer's module.
///
/// Deliberately not `@inline(__always)`: forcing the cast below to inline into a
/// `rethrows` generic across a resilience boundary crashes Swift 6.3.3 with
/// signal 11 while emitting IR for `Object.fromFastVariantOrThrow` at `-O`.
public func _assumeGodotMainActor<T: Sendable>(_ body: @MainActor () throws -> T) rethrows -> T {
#if os(Android)
    return try withoutActuallyEscaping(body) { escaping in
        try unsafeBitCast(escaping, to: (() throws -> T).self)()
    }
#else
    return try MainActor.assumeIsolated(body)
#endif
}
