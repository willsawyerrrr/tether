import AppKit
import SwiftUI

/// One directory's row in the menu bar list: name, status, and its controls.
struct DirectoryRowView: View {
    @ObservedObject var directory: ManagedDirectory
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(directory.name)
                        .font(.body)
                        .lineLimit(1)
                    Text(directory.path.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                StatusIndicator(status: directory.status)

                Button {
                    toggleRunning()
                } label: {
                    Image(systemName: directory.status.isRunning ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.plain)
                .help(directory.status.isRunning ? "Stop" : "Start")

                Button {
                    model.remove(directory)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Remove")
            }

            if case .ready(let joinURL) = directory.status {
                HStack {
                    Text(joinURL)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Spacer()

                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(joinURL, forType: .string)
                    }
                    .controlSize(.small)
                }
            }

            if case .restarting(let attempt, let retryAt, let reason) = directory.status {
                (Text("claude \(reason). Restart \(attempt) in ") + Text(retryAt, style: .timer))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }

            if case .error(let message) = directory.status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
    }

    private func toggleRunning() {
        if directory.status.isRunning {
            directory.stop()
        } else {
            directory.start()
        }
    }
}
