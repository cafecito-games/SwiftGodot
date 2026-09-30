//
// A main executor that lives on Godot's engine thread.
//

#if os(Android) || os(Linux)
@_spi(ExperimentalCustomExecutors) import _Concurrency
import GDExtensionC

/// The main actor's executor on platforms where Godot's main loop is not the process main thread.
///
/// On Android the engine's main loop runs on a renderer thread that is neither the process main
/// thread nor a thread libdispatch will ever recognise as owning its main queue. On Linux, Swift's
/// main dispatch queue is likewise not integrated with Godot's main loop. With the default executor,
/// main-actor jobs can be placed on a queue nothing drains. This executor answers isolation checks
/// from `EngineThread` and holds jobs in `MainActorJobQueue` until Godot's per-frame callback drains
/// them.
final class EngineThreadMainExecutor: MainExecutor, @unchecked Sendable {
    private nonisolated(unsafe) static var reportedFirstDecision = false
    private nonisolated(unsafe) static var reportedFirstEnqueue = false

    func enqueue(_ job: consuming ExecutorJob) {
        if !Self.reportedFirstEnqueue {
            Self.reportedFirstEnqueue = true
            swiftgodot_android_log_info("main actor job queued for the engine thread (first enqueue)")
        }
        MainActorJobQueue.enqueue(UnownedJob(job))
    }

    func isIsolatingCurrentContext() -> Bool? {
        let isolated = EngineThread.isCurrent
        if isolated {
            Self.reportFirstDecision("isIsolatingCurrentContext")
        }
        return isolated
    }

    func checkIsolated() {
        guard EngineThread.isCurrent else {
            fatalError("Incorrect actor executor assumption; expected the Godot engine thread")
        }
        Self.reportFirstDecision("checkIsolated")
    }

    /// Godot owns the main loop, so nothing ever asks this executor to run one.
    func run() throws {
        fatalError("EngineThreadMainExecutor cannot run a loop; Godot drives the engine thread")
    }

    func stop() {
        fatalError("EngineThreadMainExecutor cannot stop a loop; Godot drives the engine thread")
    }

    /// Logs the first isolation decision so the device log shows the executor is live.
    private static func reportFirstDecision(_ decision: String) {
        guard !reportedFirstDecision else { return }
        reportedFirstDecision = true
        swiftgodot_android_log_info("main actor bound to the engine thread (first decision: \(decision))")
    }
}

/// Supplies the engine-thread main executor while keeping the platform's global executor.
struct EngineThreadExecutorFactory: ExecutorFactory {
    static let mainExecutor: any MainExecutor = EngineThreadMainExecutor()
    static let defaultExecutor: any TaskExecutor = PlatformExecutorFactory.defaultExecutor
}

enum EngineThreadMainActorBinding {
    private static let installed = LockStorage<Bool>.create(value: false)

    /// Makes the engine-thread executor the main actor's executor. Safe to call from every
    /// extension entry point in the process; only the first call installs.
    static func installOnce() {
        let firstInstall = installed.withLockedValue { alreadyInstalled -> Bool in
            defer { alreadyInstalled = true }
            return !alreadyInstalled
        }
        guard firstInstall else { return }
        _createExecutors(factory: EngineThreadExecutorFactory.self)
    }
}
#else
enum EngineThreadMainActorBinding {
    /// The platform's main executor already recognises the engine thread; nothing to install.
    static func installOnce() {}
}
#endif
