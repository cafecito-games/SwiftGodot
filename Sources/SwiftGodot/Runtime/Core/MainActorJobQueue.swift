//
// Main-actor jobs that must run on Godot's engine thread.
//

/// A FIFO drained once per frame, where a drain only runs the elements present when it starts.
///
/// Elements added while a drain is in progress wait for the next drain, so an element that
/// re-adds itself cannot starve the frame that is draining.
struct FrameQueue<Element>: Sendable {
    private let storage = LockStorage<[Element]>.create(value: [])

    func enqueue(_ element: Element) {
        storage.withLockedValue { $0.append(element) }
    }

    /// Removes and returns the elements present at the time of the call, in insertion order.
    func takeAll() -> [Element] {
        storage.withLockedValue { elements in
            let taken = elements
            elements.removeAll(keepingCapacity: true)
            return taken
        }
    }

    var isEmpty: Bool {
        storage.withLockedValue { $0.isEmpty }
    }
}

/// Holds jobs enqueued on the Swift main executor until Godot's engine thread drains them.
///
/// On platforms where the Swift runtime routes main-executor jobs to a queue nothing drains,
/// the runtime hooks redirect them here and the extension drains this queue from Godot's
/// per-frame main loop callback. Draining runs each job with the main executor installed as
/// the current executor, so isolation checks inside the job pass without reaching the hooks.
enum MainActorJobQueue {
    private static let jobs = FrameQueue<UnownedJob>()

    /// Accepts a job from any thread.
    static func enqueue(_ job: UnownedJob) {
        jobs.enqueue(job)
    }

    /// Runs the jobs present when called. Must be called on the engine thread.
    static func drainFrame() {
        drainFrame { job in
            job.runSynchronously(on: MainActor.sharedUnownedExecutor)
        }
    }

    /// Runs the jobs present when called using `run`, so tests can observe the order.
    static func drainFrame(run: (UnownedJob) -> Void) {
        for job in jobs.takeAll() {
            run(job)
        }
    }

    static var isEmpty: Bool {
        jobs.isEmpty
    }
}
