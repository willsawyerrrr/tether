import XCTest

@testable import Tether

final class OutputParserTests: XCTestCase {
    func testStripANSIRemovesCursorAndColourSequences() {
        let text = "\u{1B}[2K\u{1B}[1A\u{1B}[32mReady\u{1B}[0m"
        XCTAssertEqual(OutputParser.stripANSI(text), "Ready")
    }

    func testStripANSILeavesPlainTextUntouched() {
        XCTAssertEqual(OutputParser.stripANSI("plain text"), "plain text")
    }

    func testJoinURLFindsEnvironmentURL() {
        let text = "Open https://claude.ai/code?environment=env_01-AbC_9 to join\nReady"
        XCTAssertEqual(
            OutputParser.joinURL(in: text), "https://claude.ai/code?environment=env_01-AbC_9")
    }

    func testJoinURLIsNilWithoutMatch() {
        XCTAssertNil(OutputParser.joinURL(in: "https://claude.ai/code and nothing else"))
    }

    func testWorkspaceNotTrustedLineReturnsMatchingLine() {
        let text = "noise\nError: Workspace not trusted. Run `claude` first.\nmore"
        XCTAssertEqual(
            OutputParser.workspaceNotTrustedLine(in: text),
            "Error: Workspace not trusted. Run `claude` first.")
    }

    func testWorkspaceNotTrustedLineFallsBack() {
        XCTAssertEqual(
            OutputParser.workspaceNotTrustedLine(in: "nothing"), "Workspace not trusted.")
    }

    func testRemovingShellNoiseDropsEvalDiagnostics() {
        let text = "(eval):1: can't change option: zle\nreal output\n(eval):22: other\n"
        XCTAssertEqual(OutputParser.removingShellNoise(from: text), "real output\n")
    }

    func testRemovingShellNoiseKeepsMidLineEval() {
        let text = "see (eval):1: inline\n"
        XCTAssertEqual(OutputParser.removingShellNoise(from: text), text)
    }
}
