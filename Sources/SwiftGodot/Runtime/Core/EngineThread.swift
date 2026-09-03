//
// Identity of the thread that runs Godot's main loop.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#endif

/// Records which thread runs Godot's main loop and answers whether the caller is on it.
///
/// Godot calls extensions from a single engine thread, but that thread is not always
/// the process main thread. On Android the engine loads the extension on the Java UI
/// thread and later hands the main loop to the renderer thread. The record is refreshed
/// at each of those hand-offs so the answer tracks what Godot considers its main thread.
enum EngineThread {
    private static let storage = LockStorage<pthread_t?>.create(value: nil)

    /// Records the calling thread as the engine thread.
    static func adopt() {
        let current = pthread_self()
        storage.withLockedValue { $0 = current }
    }

    /// Whether the calling thread is the recorded engine thread. False before any adoption.
    static var isCurrent: Bool {
        guard let recorded = storage.withLockedValue({ $0 }) else {
            return false
        }
        return pthread_equal(recorded, pthread_self()) != 0
    }

    /// Forgets the recorded thread. Used by tests and at extension shutdown.
    static func reset() {
        storage.withLockedValue { $0 = nil }
    }
}
