import Foundation
import TetherIPC

/// The persisted representation of a directory the user has added.
struct DirectoryRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let path: String
    /// Overrides the default spawn mode; `nil` follows it.
    var spawnMode: SpawnMode?
}
