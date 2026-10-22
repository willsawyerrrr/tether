import AppKit
import SwiftUI
import TetherIPC

/// Identifies and opens the main window.
enum MainWindow {
    static let id = "main"

    @MainActor
    static func open(using openWindow: OpenWindowAction) {
        NSApplication.shared.setActivationPolicy(.regular)
        openWindow(id: id)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

/// The main window: directories in the sidebar, the selected directory's terminal in the detail
/// pane.
struct MainWindowView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(model.sortedDirectories, selection: $model.selection) { directory in
                SidebarRow(directory: directory)
                    .tag(directory.id)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            if let directory = model.directories.first(where: { $0.id == model.selection }) {
                DirectoryDetailView(directory: directory)
                    .id(directory.id)
            } else {
                Text(model.directories.isEmpty ? "Add a directory to get started." : "Select a directory.")
                    .foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    model.addDirectory()
                } label: {
                    Label("Add Directory", systemImage: "plus")
                }
                .help("Add a directory")
            }
        }
        .frame(minWidth: 720, minHeight: 420)
    }
}

private struct SidebarRow: View {
    @ObservedObject var directory: ManagedDirectory

    var body: some View {
        HStack {
            Text(directory.name)
                .lineLimit(1)
            Spacer()
            StatusIndicator(status: directory.status)
        }
        .help(directory.path.path)
    }
}

private struct DirectoryDetailView: View {
    @ObservedObject var directory: ManagedDirectory
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            TerminalContainerView(session: directory.terminal)
        }
        .navigationTitle(directory.name)
        .navigationSubtitle(directory.path.path)
        .toolbar {
            ToolbarItemGroup {
                Picker("Spawn Mode", selection: $directory.spawnMode) {
                    Text("Same Directory").tag(SpawnMode.sameDir)
                    Text("Worktree").tag(SpawnMode.worktree)
                }
                .help("Where sessions run; applies on the next restart")

                Button {
                    directory.start()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .disabled(directory.status.isActive)
                .help("Start")

                Button {
                    directory.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(!directory.status.isActive)
                .help("Stop")

                Button {
                    directory.restart()
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
                .help("Restart")

                Button {
                    if let joinURL = directory.status.joinURL {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(joinURL, forType: .string)
                    }
                } label: {
                    Label("Copy Join URL", systemImage: "link")
                }
                .disabled(directory.status.joinURL == nil)
                .help("Copy join URL")

                Button {
                    model.remove(directory)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .help("Remove")
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            StatusIndicator(status: directory.status)
            statusText
            Spacer()
            if directory.restartCount > 0 {
                Text("Restarts: \(directory.restartCount)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var statusText: some View {
        switch directory.status {
        case .stopped:
            Text("Stopped")
        case .connecting:
            Text("Connecting")
        case .ready(let joinURL):
            Text(joinURL).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
        case .error(let message):
            Text(message).foregroundStyle(.red).lineLimit(2).textSelection(.enabled)
        case .restarting(let attempt, let retryAt, let reason):
            (Text("claude \(reason). Restart \(attempt) in ") + Text(retryAt, style: .timer))
                .foregroundStyle(.orange)
        }
    }
}
