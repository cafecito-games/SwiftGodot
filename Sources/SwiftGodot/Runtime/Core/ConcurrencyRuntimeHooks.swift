//
// Binding the Swift main actor to Godot's engine thread through the concurrency runtime hooks.
//

#if os(Android)
import GDExtensionC

/// Installs the Swift concurrency runtime hooks that let the main actor live on Godot's engine thread.
///
/// On Android the engine's main loop runs on a renderer thread that is neither the process main
/// thread nor a thread libdispatch will ever recognise as owning its main queue. Left alone,
/// every main-actor isolation check outside a task aborts, and every job enqueued on the main
/// executor is placed on a queue nothing drains. The runtime exports hooks for exactly these
/// decisions; the C trampolines in `SwiftGodotConcurrencyHooks.c` install them and call back
/// into the functions below.
enum ConcurrencyRuntimeHooks {
    private static let installed = LockStorage<Bool>.create(value: false)

    /// Identity word of the main actor's executor, captured once so hooks can recognise it.
    fileprivate nonisolated(unsafe) static var mainExecutorIdentity: UnsafeMutableRawPointer?

    /// Set once the first hook has fired, so the device log shows the hooks are live.
    fileprivate nonisolated(unsafe) static var reportedFirstHit = false

    static func installOnce() {
        let firstInstall = installed.withLockedValue { alreadyInstalled -> Bool in
            defer { alreadyInstalled = true }
            return !alreadyInstalled
        }
        guard firstInstall else { return }

        mainExecutorIdentity = identity(of: MainActor.sharedUnownedExecutor)

        if let missing = swiftgodot_install_concurrency_hooks() {
            fatalError("SwiftGodot: cannot bind the main actor to the engine thread, \(String(cString: missing)) was not found")
        }
    }

    private static func identity(of executor: UnownedSerialExecutor) -> UnsafeMutableRawPointer? {
        withUnsafeBytes(of: executor) { bytes in
            bytes.load(as: UnsafeMutableRawPointer?.self)
        }
    }
}

@_cdecl("swiftgodot_main_actor_owns_current_thread")
func swiftgodot_main_actor_owns_current_thread(_ identity: UnsafeMutableRawPointer?) -> Bool {
    identity == ConcurrencyRuntimeHooks.mainExecutorIdentity && EngineThread.isCurrent
}

@_cdecl("swiftgodot_enqueue_main_actor_job")
func swiftgodot_enqueue_main_actor_job(_ job: UnsafeMutableRawPointer) {
    MainActorJobQueue.enqueue(unsafeBitCast(job, to: UnownedJob.self))
}

@_cdecl("swiftgodot_report_first_hook_hit")
func swiftgodot_report_first_hook_hit(_ hook: UnsafePointer<CChar>) {
    guard !ConcurrencyRuntimeHooks.reportedFirstHit else { return }
    ConcurrencyRuntimeHooks.reportedFirstHit = true
    print("SwiftGodot: main actor bound to the engine thread (first hook hit: \(String(cString: hook)))")
}
#else
enum ConcurrencyRuntimeHooks {
    /// The platform's main executor already recognises the engine thread; nothing to install.
    static func installOnce() {}
}
#endif
