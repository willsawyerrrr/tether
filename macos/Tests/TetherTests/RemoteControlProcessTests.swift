import XCTest

@testable import Tether

@MainActor
final class RemoteControlProcessTests: XCTestCase {
    func testUntrustedWorkspaceIsAnErrorWhenTheMainThreadIsBusy() throws {
        let folder = try makeFolder()
        let directory = ManagedDirectory(path: folder)
        directory.shell = try makeStandIn(
            in: folder, script: "echo 'Error: Workspace not trusted.'; : > written; exit 1")
        directory.start()
        defer { directory.stop() }

        // Nothing reads the terminal while the main thread is held.
        XCTAssertTrue(poll { FileManager.default.fileExists(atPath: folder.appendingPathComponent("written").path) })
        Thread.sleep(forTimeInterval: 2)

        XCTAssertTrue(runMainLoop { !directory.status.isRunning })
        guard case .error = directory.status else { return XCTFail("\(directory.status)") }
        XCTAssertEqual(directory.restartCount, 0)
    }

    func testReleasedProcessIsReadAndReaped() throws {
        let folder = try makeFolder()
        let shell = try makeStandIn(
            in: folder, script: "trap 'echo bye; exit 0' TERM; echo $$ > pid; sleep 30 & wait")
        var process: RemoteControlProcess? = try RemoteControlProcess(
            shell: shell, directoryURL: folder, name: "released", spawnMode: .sameDir, cols: 80, rows: 24)
        var pid: pid_t?
        XCTAssertTrue(
            runMainLoop {
                let text = try? String(contentsOf: folder.appendingPathComponent("pid"), encoding: .utf8)
                pid = text.flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                return pid != nil
            })

        process?.terminate()
        process = nil

        let child = try XCTUnwrap(pid)
        XCTAssertTrue(runMainLoop { kill(child, 0) != 0 })
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        return folder
    }

    /// Writes an executable that stands in for the login shell, returning its path.
    private func makeStandIn(in folder: URL, script: String) throws -> String {
        let path = folder.appendingPathComponent("shell").path
        try "#!/bin/sh\n\(script)\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    /// Waits for `condition` while holding the main thread.
    private func poll(_ condition: () -> Bool) -> Bool {
        wait(until: condition) { Thread.sleep(forTimeInterval: 0.01) }
    }

    /// Waits for `condition` while servicing the main queue.
    private func runMainLoop(_ condition: () -> Bool) -> Bool {
        wait(until: condition) { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    private func wait(until condition: () -> Bool, step: () -> Void) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        while !condition() {
            guard Date() < deadline else { return false }
            step()
        }
        return true
    }
}
