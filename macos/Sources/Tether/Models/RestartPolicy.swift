import Foundation

/// Capped exponential backoff for restarting a server that exits unexpectedly.
struct RestartPolicy: Equatable {
    var baseDelay: TimeInterval = 2
    var maxDelay: TimeInterval = 60

    /// A run at least this long counts as healthy and resets the backoff.
    var healthyRunDuration: TimeInterval = 60

    static let `default` = RestartPolicy()

    /// The wait before the restart numbered `attempt` (1 for the first).
    func delay(forAttempt attempt: Int) -> TimeInterval {
        let exponent = min(max(attempt - 1, 0), 30)
        return min(baseDelay * pow(2, Double(exponent)), maxDelay)
    }

    /// What to do after a server process exits.
    enum Decision: Equatable {
        case stopped
        case error(message: String)
        case restart(attempt: Int, after: TimeInterval)
    }

    /// Decides what follows an exit. `consecutiveRestarts` is the number of restarts since the
    /// last healthy run.
    func decide(
        userRequestedStop: Bool,
        workspaceNotTrusted: String?,
        runDuration: TimeInterval,
        consecutiveRestarts: Int
    ) -> Decision {
        if userRequestedStop { return .stopped }
        if let workspaceNotTrusted { return .error(message: workspaceNotTrusted) }

        let priorRestarts = runDuration >= healthyRunDuration ? 0 : consecutiveRestarts
        let attempt = priorRestarts + 1
        return .restart(attempt: attempt, after: delay(forAttempt: attempt))
    }
}
