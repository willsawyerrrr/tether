import XCTest

@testable import TetherIPC

final class ControlProtocolTests: XCTestCase {
    func testRequestRoundTrips() throws {
        for command in ControlCommand.allCases {
            let data = try JSONEncoder().encode(ControlRequest(command: command, path: "/tmp/x"))
            let decoded = try JSONDecoder().decode(ControlRequest.self, from: data)
            XCTAssertEqual(decoded.command, command)
            XCTAssertEqual(decoded.path, "/tmp/x")
        }
    }

    func testRequestDecodesFromRawJSON() throws {
        let json = Data(#"{"command":"start","path":"/a"}"#.utf8)
        let decoded = try JSONDecoder().decode(ControlRequest.self, from: json)
        XCTAssertEqual(decoded.command, .start)
        XCTAssertEqual(decoded.path, "/a")
    }

    func testRequestRejectsUnknownCommand() {
        let json = Data(#"{"command":"nope","path":"/a"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ControlRequest.self, from: json))
    }

    func testResponseRoundTrips() throws {
        let data = try JSONEncoder().encode(ControlResponse(ok: false, message: "bad"))
        let decoded = try JSONDecoder().decode(ControlResponse.self, from: data)
        XCTAssertFalse(decoded.ok)
        XCTAssertEqual(decoded.message, "bad")
    }
}
