import XCTest
@testable import SwiftGodot

final class FrameQueueTests: XCTestCase {
    func testTakeAllPreservesInsertionOrder() {
        let queue = FrameQueue<Int>()
        queue.enqueue(1)
        queue.enqueue(2)
        queue.enqueue(3)
        XCTAssertEqual(queue.takeAll(), [1, 2, 3])
    }

    func testQueueIsEmptyAfterTakeAll() {
        let queue = FrameQueue<Int>()
        queue.enqueue(1)
        _ = queue.takeAll()
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.takeAll(), [])
    }

    func testElementsAddedDuringADrainWaitForTheNextDrain() {
        let queue = FrameQueue<Int>()
        queue.enqueue(1)
        var firstDrain: [Int] = []
        for element in queue.takeAll() {
            firstDrain.append(element)
            queue.enqueue(element + 10)
        }
        XCTAssertEqual(firstDrain, [1])
        XCTAssertEqual(queue.takeAll(), [11])
    }

    func testEnqueueFromAnotherThreadIsVisibleToTheNextDrain() {
        let queue = FrameQueue<Int>()
        let finished = LockStorage<Bool>.create(value: false)
        let thread = Thread {
            queue.enqueue(7)
            finished.withLockedValue { $0 = true }
        }
        thread.start()
        while !finished.withLockedValue({ $0 }) {
            Thread.sleep(forTimeInterval: 0.001)
        }
        XCTAssertEqual(queue.takeAll(), [7])
    }
}

/// Routes an actor's jobs through `MainActorJobQueue` so a test can drain them by hand.
private final class QueueBackedExecutor: SerialExecutor {
    func enqueue(_ job: UnownedJob) {
        MainActorJobQueue.enqueue(job)
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}

private actor QueueBackedActor {
    private let executor: QueueBackedExecutor
    private(set) var runCount = 0

    init(executor: QueueBackedExecutor) {
        self.executor = executor
    }

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }

    func touch() {
        runCount += 1
    }
}

final class MainActorJobQueueTests: XCTestCase {
    func testDrainRunsAnEnqueuedJobOnTheDrainingThread() {
        let executor = QueueBackedExecutor()
        let actor = QueueBackedActor(executor: executor)
        let ran = LockStorage<Bool>.create(value: false)

        Task.detached {
            await actor.touch()
            ran.withLockedValue { $0 = true }
        }

        let deadline = Date().addingTimeInterval(5)
        while MainActorJobQueue.isEmpty && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.001)
        }
        XCTAssertFalse(MainActorJobQueue.isEmpty, "the actor hop should have enqueued a job")

        var drained = 0
        MainActorJobQueue.drainFrame { job in
            drained += 1
            job.runSynchronously(on: executor.asUnownedSerialExecutor())
        }
        XCTAssertEqual(drained, 1)

        let completion = Date().addingTimeInterval(5)
        while !ran.withLockedValue({ $0 }) && Date() < completion {
            Thread.sleep(forTimeInterval: 0.001)
        }
        XCTAssertTrue(ran.withLockedValue { $0 })
        XCTAssertTrue(MainActorJobQueue.isEmpty)
    }
}
