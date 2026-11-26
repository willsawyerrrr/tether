import Foundation

/// Pure helpers for interpreting the text `claude remote-control` writes.
enum OutputParser {
    // Matches ANSI CSI sequences: ESC '[' followed by parameter bytes (0x30-0x3F), intermediate
    // bytes (0x20-0x2F), and a final byte (0x40-0x7E).
    private static let ansiEscapePattern = try! NSRegularExpression(
        pattern: "\u{1B}\\[[0-?]*[ -/]*[@-~]"
    )
    // A URL counts once something follows it, as output may stop partway through one.
    private static let joinURLPattern = try! NSRegularExpression(
        pattern: "https://claude\\.ai/code\\?environment=[A-Za-z0-9_-]+(?=[^A-Za-z0-9_-])"
    )

    static let workspaceNotTrustedMarker = "Workspace not trusted"

    /// The first complete join URL in `strippedText`, if any.
    static func joinURL(in strippedText: String) -> String? {
        firstMatch(of: joinURLPattern, in: strippedText)
    }

    /// The line of `strippedText` containing the workspace-trust error, or a generic message.
    static func workspaceNotTrustedLine(in strippedText: String) -> String {
        strippedText
            .split(whereSeparator: \.isNewline)
            .first(where: { $0.contains(workspaceNotTrustedMarker) })
            .map(String.init)
            ?? "Workspace not trusted."
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
