import Foundation
import TetherIPC

/// Persists the list of added directories to
/// `~/Library/Application Support/Tether/directories.json`.
enum DirectoryStore {
    private static var fileURL: URL {
        ControlSocket.supportDirectory.appendingPathComponent("directories.json", isDirectory: false)
    }

    /// Loads the saved directory list, or an empty list if none has been saved yet
    /// or the file can't be read.
    static func load() -> [DirectoryRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([DirectoryRecord].self, from: data)) ?? []
    }

    /// Overwrites the saved directory list, creating the containing directory if needed.
    static func save(_ records: [DirectoryRecord]) {
        do {
            try FileManager.default.createDirectory(
                at: ControlSocket.supportDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Tether: failed to save directory list: \(error.localizedDescription)")
        }
    }
}
