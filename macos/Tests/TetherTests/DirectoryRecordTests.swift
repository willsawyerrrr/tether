import TetherIPC
import XCTest

@testable import Tether

final class DirectoryRecordTests: XCTestCase {
    func testDecodesLegacyRecordWithPidAndJoinURL() throws {
        let json = """
            [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","path":"/tmp/project","pid":123,
              "joinURL":"https://claude.ai/code?environment=env_x"}]
            """
        let records = try JSONDecoder().decode([DirectoryRecord].self, from: Data(json.utf8))
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].path, "/tmp/project")
        XCTAssertEqual(records[0].spawnMode, .sameDir)
    }

    func testRoundTripOmitsLegacyFields() throws {
        let record = DirectoryRecord(id: UUID(), path: "/tmp/project", spawnMode: .worktree)
        let data = try JSONEncoder().encode(record)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["id", "path", "spawnMode"])
        XCTAssertEqual(try JSONDecoder().decode(DirectoryRecord.self, from: data), record)
    }
}
