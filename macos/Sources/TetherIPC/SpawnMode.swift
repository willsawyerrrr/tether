import Foundation

/// Where `claude remote-control` runs the sessions it spawns.
public enum SpawnMode: String, Codable, CaseIterable, Sendable {
    /// Every session works in the directory itself.
    case sameDir = "same-dir"
    /// On-demand sessions each work in an isolated git worktree.
    case worktree

    /// The `UserDefaults` key holding the mode directories follow unless they override it.
    public static let defaultKey = "defaultSpawnMode"

    /// The mode directories follow unless they override it.
    public static var current: SpawnMode {
        UserDefaults.standard.string(forKey: defaultKey).flatMap(SpawnMode.init(rawValue:)) ?? .sameDir
    }
}
