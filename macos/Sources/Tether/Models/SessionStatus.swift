import Foundation

/// The lifecycle state of a directory's `claude remote-control` server.
enum SessionStatus: Equatable {
    case stopped
    case connecting
    case ready(joinURL: String)
    case error(message: String)

    /// The server exited unexpectedly and is waiting to be started again.
    case restarting(attempt: Int, retryAt: Date, reason: String)

    /// The join URL, once the server has reported one.
    var joinURL: String? {
        if case .ready(let joinURL) = self { return joinURL }
        return nil
    }

    /// Whether a child process is currently expected to be alive for this status.
    var isRunning: Bool {
        switch self {
        case .connecting, .ready:
            return true
        case .stopped, .error, .restarting:
            return false
        }
    }

    /// Whether the server is running or scheduled to run again without user action.
    var isActive: Bool {
        if case .restarting = self { return true }
        return isRunning
    }
}
