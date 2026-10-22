import AppKit
import Combine
import Foundation
import TetherIPC

/// Owns the list of directories the user has added and their `claude remote-control`
/// servers, and keeps the persisted directory list in sync with changes.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var directories: [ManagedDirectory] = []

    /// The directory shown in the main window.
    @Published var selection: UUID?

    init() {
        directories = DirectoryStore.load().map(ManagedDirectory.init(record:))
        for directory in directories {
            directory.onChange = { [weak self] in self?.persist() }
            directory.start()
        }
    }

    /// The directories ordered by name.
    var sortedDirectories: [ManagedDirectory] {
        directories.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Presents a directory picker and adds the chosen directory, if any and not already added.
    func addDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a directory to manage with Tether."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        add(url)
    }

    /// Adds and starts the directory at `url`. Returns `nil` if it's already in the list.
    @discardableResult
    private func add(_ url: URL, spawnMode: SpawnMode = .sameDir) -> ManagedDirectory? {
        let standardizedURL = url.standardizedFileURL
        guard directory(at: standardizedURL) == nil else { return nil }

        let directory = ManagedDirectory(path: standardizedURL, spawnMode: spawnMode)
        directory.onChange = { [weak self] in self?.persist() }
        directories.append(directory)
        persist()
        directory.start()
        selection = directory.id
        return directory
    }

    private func directory(at url: URL) -> ManagedDirectory? {
        directories.first { $0.path.standardizedFileURL == url }
    }

    /// Carries out a `tetherctl` request against the directory list.
    func handle(_ request: ControlRequest) -> ControlResponse {
        let url = URL(fileURLWithPath: request.path, isDirectory: true).standardizedFileURL
        let existing = directory(at: url)

        switch request.command {
        case .add:
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            else {
                return ControlResponse(ok: false, message: "\(url.path) is not a directory.")
            }
            guard add(url, spawnMode: request.spawnMode ?? .sameDir) != nil else {
                return ControlResponse(ok: true, message: "\(url.path) is already added.")
            }
            return ControlResponse(ok: true, message: "Added \(url.path).")
        case .remove:
            guard let existing else { return Self.notAdded(url) }
            remove(existing)
            return ControlResponse(ok: true, message: "Removed \(url.path).")
        case .start:
            guard let existing else { return Self.notAdded(url) }
            existing.start()
            return ControlResponse(ok: true, message: "Started \(url.path).")
        case .stop:
            guard let existing else { return Self.notAdded(url) }
            existing.stop()
            return ControlResponse(ok: true, message: "Stopped \(url.path).")
        }
    }

    private static func notAdded(_ url: URL) -> ControlResponse {
        ControlResponse(ok: false, message: "\(url.path) hasn't been added to Tether.")
    }

    /// Stops the directory's server, if running, and removes it from the list.
    func remove(_ directory: ManagedDirectory) {
        directory.stop()
        directories.removeAll { $0.id == directory.id }
        if selection == directory.id { selection = nil }
        persist()
    }

    /// Terminates every server ahead of the app quitting.
    func shutdown() async {
        await withTaskGroup(of: Void.self) { group in
            for directory in directories {
                group.addTask { await directory.terminateForQuit(timeout: 3) }
            }
        }
    }

    private func persist() {
        DirectoryStore.save(directories.map(\.record))
    }
}
