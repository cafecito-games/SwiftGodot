//
//  MainActorHopTests.swift
//  SwiftGodotTestExtension
//
//  Verifies that main-actor jobs started inside a Godot callback resume on the engine thread.
//

@testable import SwiftGodot

/// State shared between the runner, which starts the hop before running tests,
/// and the suite that asserts on the outcome.
enum MainActorHopProbe {
    /// Frames the runner waits for the hop before running tests anyway.
    static let frameBudget = 60

    nonisolated(unsafe) static var hopCompleted = false
    nonisolated(unsafe) static var framesWaited = 0

    /// Leaves the main actor and returns to it twice, once from a detached task and once
    /// from a timer. Each resumption is enqueued on the main executor, so completion proves
    /// the executor is drained while Godot owns the thread.
    @MainActor
    static func start() {
        Task {
            await Task.detached {}.value
            try? await Task.sleep(for: .milliseconds(1))
            hopCompleted = true
        }
    }
}

@SwiftGodotTestSuite
final class MainActorHopTests {
    @SwiftGodotTest
    public func testMainActorJobsResumeOnTheEngineThread() {
        XCTAssertTrue(
            MainActorHopProbe.hopCompleted,
            "a Task that hops off and back onto the main actor did not complete within \(MainActorHopProbe.frameBudget) frames"
        )
    }

    @SwiftGodotTest
    public func testEngineThreadIsTheCallingThread() {
        XCTAssertTrue(EngineThread.isCurrent, "Godot callbacks must run on the recorded engine thread")
    }
}
