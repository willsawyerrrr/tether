import Foundation
import TetherIPC

/// The persisted representation of a directory the user has added.
struct DirectoryRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let path: String
    var spawnMode: SpawnMode

    init(id: UUID, path: String, spawnMode: SpawnMode = .sameDir) {
        self.id = id
        self.path = path
        self.spawnMode = spawnMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        spawnMode = try container.decodeIfPresent(SpawnMode.self, forKey: .spawnMode) ?? .sameDir
    }
}
