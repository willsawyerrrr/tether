import XCTest

@testable import Tether

final class SessionStatusTests: XCTestCase {
    func testJoinURLOnlyForReady() {
        XCTAssertEqual(SessionStatus.ready(joinURL: "u").joinURL, "u")
        XCTAssertNil(SessionStatus.connecting.joinURL)
        XCTAssertNil(SessionStatus.error(message: "m").joinURL)
    }

    func testIsRunning() {
        XCTAssertTrue(SessionStatus.connecting.isRunning)
        XCTAssertTrue(SessionStatus.ready(joinURL: "u").isRunning)
        XCTAssertTrue(SessionStatus.runningUntracked.isRunning)
        XCTAssertFalse(SessionStatus.stopped.isRunning)
        XCTAssertFalse(SessionStatus.error(message: "m").isRunning)
    }
}
