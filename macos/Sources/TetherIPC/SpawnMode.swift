import Foundation

/// Where `claude remote-control` runs the sessions it spawns.
public enum SpawnMode: String, Codable, CaseIterable, Sendable {
    /// Every session works in the directory itself.
    case sameDir = "same-dir"
    /// On-demand sessions each work in an isolated git worktree.
    case worktree
}
