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
        XCTAssertFalse(SessionStatus.stopped.isRunning)
        XCTAssertFalse(SessionStatus.error(message: "m").isRunning)
        XCTAssertFalse(restarting.isRunning)
    }

    func testIsActiveIncludesPendingRestart() {
        XCTAssertTrue(restarting.isActive)
        XCTAssertTrue(SessionStatus.connecting.isActive)
        XCTAssertFalse(SessionStatus.stopped.isActive)
        XCTAssertFalse(SessionStatus.error(message: "m").isActive)
    }

    private var restarting: SessionStatus {
        .restarting(attempt: 1, retryAt: Date(), reason: "exited with code 1")
    }
}
