import Foundation

/// An action `tetherctl` asks the running Tether app to perform on a directory.
public enum ControlCommand: String, Codable, CaseIterable {
    case add, remove, start, stop
}

/// A single newline-terminated JSON request sent over the control socket.
public struct ControlRequest: Codable {
    public let command: ControlCommand
    /// The absolute path of the directory the command applies to.
    public let path: String
    /// The spawn mode for an `add`; `nil` follows the default.
    public let spawnMode: SpawnMode?

    public init(command: ControlCommand, path: String, spawnMode: SpawnMode? = nil) {
        self.command = command
        self.path = path
        self.spawnMode = spawnMode
    }
}

/// The newline-terminated JSON reply to a `ControlRequest`.
public struct ControlResponse: Codable {
    public let ok: Bool
    /// A human-readable result, or the reason the command failed.
    public let message: String

    public init(ok: Bool, message: String) {
        self.ok = ok
        self.message = message
    }
}
