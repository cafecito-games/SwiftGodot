import XCTest
@testable import SwiftGodot

final class EngineThreadTests: XCTestCase {
    override func tearDown() {
        EngineThread.reset()
    }

    func testIsCurrentIsFalseBeforeAdoption() {
        EngineThread.reset()
        XCTAssertFalse(EngineThread.isCurrent)
    }

    func testAdoptingThreadIsCurrent() {
        EngineThread.adopt()
        XCTAssertTrue(EngineThread.isCurrent)
    }

    func testOtherThreadIsNotCurrent() {
        EngineThread.adopt()
        let observed = LockStorage<Bool?>.create(value: nil)
        let thread = Thread {
            observed.withLockedValue { $0 = EngineThread.isCurrent }
        }
        thread.start()
        while observed.withLockedValue({ $0 }) == nil {
            Thread.sleep(forTimeInterval: 0.001)
        }
        XCTAssertEqual(observed.withLockedValue { $0 }, false)
    }

    func testReadoptionMovesTheRecord() {
        EngineThread.adopt()
        let finished = LockStorage<Bool>.create(value: false)
        let thread = Thread {
            EngineThread.adopt()
            finished.withLockedValue { $0 = true }
        }
        thread.start()
        while !finished.withLockedValue({ $0 }) {
            Thread.sleep(forTimeInterval: 0.001)
        }
        XCTAssertFalse(EngineThread.isCurrent)
        EngineThread.adopt()
        XCTAssertTrue(EngineThread.isCurrent)
    }
}
