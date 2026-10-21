import XCTest

@testable import Tether

final class RestartPolicyTests: XCTestCase {
    private let policy = RestartPolicy(baseDelay: 2, maxDelay: 60, healthyRunDuration: 60)

    func testDelayDoublesThenCaps() {
        XCTAssertEqual(policy.delay(forAttempt: 1), 2)
        XCTAssertEqual(policy.delay(forAttempt: 2), 4)
        XCTAssertEqual(policy.delay(forAttempt: 5), 32)
        XCTAssertEqual(policy.delay(forAttempt: 6), 60)
        XCTAssertEqual(policy.delay(forAttempt: 1_000), 60)
    }

    func testUserRequestedStopDoesNotRestart() {
        XCTAssertEqual(
            policy.decide(userRequestedStop: true, workspaceNotTrusted: nil, runDuration: 1, consecutiveRestarts: 0),
            .stopped)
    }

    func testUntrustedWorkspaceIsAnErrorWithoutRestart() {
        XCTAssertEqual(
            policy.decide(
                userRequestedStop: false, workspaceNotTrusted: "Workspace not trusted.", runDuration: 1,
                consecutiveRestarts: 0),
            .error(message: "Workspace not trusted."))
    }

    func testUnexpectedExitRestartsWithGrowingAttempts() {
        XCTAssertEqual(
            policy.decide(userRequestedStop: false, workspaceNotTrusted: nil, runDuration: 5, consecutiveRestarts: 0),
            .restart(attempt: 1, after: 2))
        XCTAssertEqual(
            policy.decide(userRequestedStop: false, workspaceNotTrusted: nil, runDuration: 5, consecutiveRestarts: 3),
            .restart(attempt: 4, after: 16))
    }

    func testHealthyRunResetsBackoff() {
        XCTAssertEqual(
            policy.decide(userRequestedStop: false, workspaceNotTrusted: nil, runDuration: 120, consecutiveRestarts: 6),
            .restart(attempt: 1, after: 2))
    }
}
