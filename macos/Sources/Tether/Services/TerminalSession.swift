import AppKit
import SwiftTerm

/// A directory's terminal emulator. It is fed the server's output for the server's whole life,
/// whether or not it is on screen, so its screen and scrollback persist across window closes
/// and directory switches.
@MainActor
final class TerminalSession: NSObject, TerminalViewDelegate {
    static let scrollbackLines = 10_000

    let view: TerminalView

    /// Called with keyboard input to forward to the server.
    var onInput: ((Data) -> Void)?

    /// Called when the view's size, in character cells, changes.
    var onResize: ((_ cols: Int, _ rows: Int) -> Void)?

    override init() {
        let options = TerminalOptions(cols: cols, rows: rows, scrollback: Self.scrollbackLines)
        view = TerminalView(frame: .zero, options: options)
        super.init()
        view.terminalDelegate = self
    }

    /// The terminal's size in character cells.
    private(set) var cols = 100
    private(set) var rows = 30

    func feed(_ data: Data) {
        view.feed(byteArray: ArraySlice(data))
    }

    func feed(text: String) {
        view.feed(text: text)
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        cols = newCols
        rows = newRows
        onResize?(newCols, newRows)
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        onInput?(Data(data))
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(content, forType: .string)
    }
}
