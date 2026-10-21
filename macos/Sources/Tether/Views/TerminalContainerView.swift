import AppKit
import SwiftUI

/// Hosts a directory's long-lived terminal view. The view belongs to the directory's model, so
/// closing the window or switching directories only detaches it.
struct TerminalContainerView: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        attach(to: container)
    }

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    final class Coordinator {
        let session: TerminalSession
        init(session: TerminalSession) { self.session = session }
    }

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        let view = coordinator.session.view
        if view.superview === container { view.removeFromSuperview() }
    }

    private func attach(to container: NSView) {
        let view = session.view
        guard view.superview !== container else { return }
        view.removeFromSuperview()
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
    }
}
