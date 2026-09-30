//
// Godot main loop callbacks used to keep the Swift main actor bound to the engine thread.
//

import GDExtensionC

/// Registers the GDExtension main loop callbacks once per process.
///
/// `startup_func` records the thread that owns the main loop as the engine thread,
/// `frame_func` drains main-actor jobs that were redirected to the engine thread, and
/// `shutdown_func` drains whatever is still pending so jobs do not vanish at exit.
enum EngineMainLoop {
    private static let registered = LockStorage<Bool>.create(value: false)

    static func registerCallbacksOnce(library: GDExtensionClassLibraryPtr) {
        let firstRegistration = registered.withLockedValue { alreadyRegistered -> Bool in
            defer { alreadyRegistered = true }
            return !alreadyRegistered
        }
        guard firstRegistration else { return }

        guard let register = gi.register_main_loop_callbacks else {
            #if os(Android) || os(Linux)
            GD.pushWarning("This Godot build has no register_main_loop_callbacks; main-actor jobs will not run on this platform")
            #endif
            return
        }

        var callbacks = GDExtensionMainLoopCallbacks(
            startup_func: { EngineThread.adopt() },
            shutdown_func: { MainActorJobQueue.drainFrame() },
            frame_func: { MainActorJobQueue.drainFrame() }
        )
        register(library, &callbacks)
    }
}
