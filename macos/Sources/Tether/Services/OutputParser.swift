import Foundation

/// Pure helpers for interpreting the text `claude remote-control` writes.
enum OutputParser {
    // Matches ANSI CSI sequences: ESC '[' followed by parameter bytes (0x30-0x3F), intermediate
    // bytes (0x20-0x2F), and a final byte (0x40-0x7E).
    private static let ansiEscapePattern = try! NSRegularExpression(
        pattern: "\u{1B}\\[[0-?]*[ -/]*[@-~]"
    )
    private static let joinURLPattern = try! NSRegularExpression(
        pattern: "https://claude\\.ai/code\\?environment=[A-Za-z0-9_-]+"
    )
    // Matches diagnostics the login shell prints while sourcing the user's rc files, e.g.
    // `(eval):1: can't change option: zle`.
    private static let shellNoisePattern = try! NSRegularExpression(
        pattern: "^\\(eval\\):\\d+: .*$\\n?", options: .anchorsMatchLines
    )

    static let workspaceNotTrustedMarker = "Workspace not trusted"

    /// The first join URL in `strippedText`, if any.
    static func joinURL(in strippedText: String) -> String? {
        firstMatch(of: joinURLPattern, in: strippedText)
    }

    /// The line of `strippedText` containing the workspace-trust error, or a generic message.
    static func workspaceNotTrustedLine(in strippedText: String) -> String {
        strippedText
            .split(separator: "\n")
            .first(where: { $0.contains(workspaceNotTrustedMarker) })
            .map(String.init)
            ?? "Workspace not trusted."
    }

    static func removingShellNoise(from text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return shellNoisePattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    static func stripANSI(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return ansiEscapePattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private static func firstMatch(of regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
            let matchRange = Range(match.range, in: text)
        else {
            return nil
        }
        return String(text[matchRange])
    }
}
