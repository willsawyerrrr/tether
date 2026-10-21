import Foundation

/// The persisted representation of a directory the user has added.
struct DirectoryRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let path: String
}
