import SwiftUI

/// A small icon reflecting a server's `SessionStatus`.
struct StatusIndicator: View {
    let status: SessionStatus

    var body: some View {
        switch status {
        case .stopped:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .help("Stopped")
        case .connecting:
            ProgressView()
                .controlSize(.small)
                .help("Connecting")
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Ready")
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .help("Error")
        case .restarting:
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .foregroundStyle(.orange)
                .help("Exited unexpectedly; restarting")
        }
    }
}
