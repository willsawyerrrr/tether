import AppKit
import ServiceManagement
import SwiftUI

/// The popover content shown when the menu bar icon is clicked: the directory list,
/// an add button, a launch-at-login toggle, and quit.
struct MenuBarContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            Group {
                if model.directories.isEmpty {
                    Text("No directories added yet.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .padding(12)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(sortedDirectories) { directory in
                                DirectoryRowView(directory: directory)
                                Divider()
                            }
                        }
                    }
                }
            }
            // Fixed, not maxHeight, and constant across both branches above: MenuBarExtra's
            // `.window` style doesn't reliably re-measure the popover as this content's
            // height changes while it's open.
            .frame(height: 480)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Launch at Login", isOn: launchAtLoginBinding)
                    .toggleStyle(.checkbox)

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button("Quit Tether") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
        }
        .frame(width: 340)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchesAtLogin },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    launchAtLoginError = nil
                } catch {
                    launchAtLoginError = error.localizedDescription
                }
                launchesAtLogin = SMAppService.mainApp.status == .enabled
            }
        )
    }

    private var sortedDirectories: [ManagedDirectory] {
        model.directories.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var header: some View {
        HStack {
            Text("Tether")
                .font(.headline)

            Spacer()

            Button {
                model.addDirectory()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help("Add a directory")
        }
        .padding([.horizontal, .top], 12)
        .padding(.bottom, 8)
    }
}
