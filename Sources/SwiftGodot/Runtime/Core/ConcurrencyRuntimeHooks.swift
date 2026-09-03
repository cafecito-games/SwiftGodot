//
// Binding the Swift main actor to Godot's engine thread through the concurrency runtime hooks.
//

#if os(Android)
import Android

/// Installs the Swift concurrency runtime hooks that let the main actor live on Godot's engine thread.
///
/// On Android the engine's main loop runs on a renderer thread that is neither the process main
/// thread nor a thread libdispatch will ever recognise as owning its main queue. Left alone,
/// every main-actor isolation check outside a task aborts, and every job enqueued on the main
/// executor is placed on a queue nothing drains. The runtime exports hooks for exactly these
/// decisions, so they are pointed at `EngineThread` and `MainActorJobQueue`.
enum ConcurrencyRuntimeHooks {
    private typealias CheckIsolatedOriginal = @convention(thin) (UnownedSerialExecutor) -> Void
    private typealias CheckIsolatedHook = @convention(thin) (UnownedSerialExecutor, CheckIsolatedOriginal) -> Void
    private typealias IsIsolatingOriginal = @convention(thin) (UnownedSerialExecutor) -> Int8
    private typealias IsIsolatingHook = @convention(thin) (UnownedSerialExecutor, IsIsolatingOriginal) -> Int8
    private typealias EnqueueMainOriginal = @convention(thin) (UnownedJob) -> Void
    private typealias EnqueueMainHook = @convention(thin) (UnownedJob, EnqueueMainOriginal) -> Void

    private static let installed = LockStorage<Bool>.create(value: false)

    /// Identity word of the main actor's executor, captured once so hooks can recognise it.
    private nonisolated(unsafe) static var mainExecutorIdentity: UInt = 0

    /// Set once the first hook has fired, so the device log shows the hooks are live.
    private nonisolated(unsafe) static var reportedFirstHit = false

    static func installOnce() {
        let firstInstall = installed.withLockedValue { alreadyInstalled -> Bool in
            defer { alreadyInstalled = true }
            return !alreadyInstalled
        }
        guard firstInstall else { return }

        mainExecutorIdentity = identity(of: MainActor.sharedUnownedExecutor)

        guard let runtime = dlopen("libswift_Concurrency.so", RTLD_NOW | RTLD_NOLOAD) else {
            fatalError("SwiftGodot: libswift_Concurrency.so is not loaded; cannot bind the main actor to the engine thread")
        }

        slot(in: runtime, named: "swift_task_isIsolatingCurrentContext_hook", as: IsIsolatingHook?.self).pointee = { executor, original in
            if isMainExecutor(executor) && EngineThread.isCurrent {
                reportFirstHit("isIsolatingCurrentContext")
                return 1
            }
            return original(executor)
        }

        slot(in: runtime, named: "swift_task_checkIsolated_hook", as: CheckIsolatedHook?.self).pointee = { executor, original in
            if isMainExecutor(executor) && EngineThread.isCurrent {
                reportFirstHit("checkIsolated")
                return
            }
            original(executor)
        }

        slot(in: runtime, named: "swift_task_enqueueMainExecutor_hook", as: EnqueueMainHook?.self).pointee = { job, _ in
            MainActorJobQueue.enqueue(job)
        }
    }

    private static func slot<Hook>(in runtime: UnsafeMutableRawPointer, named name: String, as type: Hook.Type) -> UnsafeMutablePointer<Hook> {
        guard let address = dlsym(runtime, name) else {
            fatalError("SwiftGodot: libswift_Concurrency.so does not export \(name); cannot bind the main actor to the engine thread")
        }
        return address.assumingMemoryBound(to: Hook.self)
    }

    private static func identity(of executor: UnownedSerialExecutor) -> UInt {
        withUnsafeBytes(of: executor) { bytes in
            bytes.load(as: UInt.self)
        }
    }

    private static func isMainExecutor(_ executor: UnownedSerialExecutor) -> Bool {
        identity(of: executor) == mainExecutorIdentity
    }

    private static func reportFirstHit(_ hook: String) {
        guard !reportedFirstHit else { return }
        reportedFirstHit = true
        print("SwiftGodot: main actor bound to the engine thread (first hook hit: \(hook))")
    }
}
#else
enum ConcurrencyRuntimeHooks {
    /// The platform's main executor already recognises the engine thread; nothing to install.
    static func installOnce() {}
}
#endif
