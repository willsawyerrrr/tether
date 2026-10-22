import Combine
import Foundation
import TetherIPC

/// A directory the user has added, and the `claude remote-control` server Tether runs for it
/// and keeps alive.
@MainActor
final class ManagedDirectory: ObservableObject, Identifiable {
    let id: UUID
    let path: URL

    /// Overrides the default spawn mode for this directory; `nil` follows the default. Takes
    /// effect the next time the server launches.
    @Published var spawnMode: SpawnMode? {
        didSet { if spawnMode != oldValue { onChange?() } }
    }

    /// Called when a persisted property changes.
    var onChange: (() -> Void)?

    /// The current lifecycle state of this directory's server.
    @Published private(set) var status: SessionStatus = .stopped

    /// How many times the server has been restarted after exiting unexpectedly.
    @Published private(set) var restartCount = 0

    /// The terminal showing this directory's server output; retained for the app's lifetime.
    let terminal = TerminalSession()

    var policy = RestartPolicy.default

    private var process: RemoteControlProcess?
    private var launchedAt = Date()
    private var consecutiveRestarts = 0
    private var userRequestedStop = false
    private var restartRequested = false
    private var restartTask: Task<Void, Never>?
    private var outputTail = ""

    /// Output retained for parsing is capped to this many characters.
    private static let maxParsedCharacters = 20_000

    var name: String { path.lastPathComponent }

    init(id: UUID = UUID(), path: URL, spawnMode: SpawnMode? = nil) {
        self.id = id
        self.path = path
        self.spawnMode = spawnMode
        terminal.onInput = { [weak self] data in self?.process?.write(data) }
        terminal.onResize = { [weak self] cols, rows in self?.process?.resize(cols: cols, rows: rows) }
    }

    convenience init(record: DirectoryRecord) {
        self.init(
            id: record.id, path: URL(fileURLWithPath: record.path, isDirectory: true),
            spawnMode: record.spawnMode)
    }

    /// The persistable form of this directory.
    var record: DirectoryRecord {
        DirectoryRecord(id: id, path: path.path, spawnMode: spawnMode)
    }

    /// Starts the server, unless it's already running or waiting to be restarted.
    func start() {
        guard !status.isActive else { return }
        consecutiveRestarts = 0
        launch()
    }

    /// Stops the server and any pending restart. The process gets `SIGTERM`, then `SIGKILL`
    /// if it lingers.
    func stop() {
        restartTask?.cancel()
        restartTask = nil
        restartRequested = false

        if let process, !process.hasExited {
            userRequestedStop = true
            process.terminate()
        } else if status != .stopped {
            status = .stopped
        }
    }

    /// Stops the server if running, then starts it afresh.
    func restart() {
        restartTask?.cancel()
        restartTask = nil
        if let process, !process.hasExited {
            restartRequested = true
            userRequestedStop = true
            process.terminate()
        } else {
            consecutiveRestarts = 0
            launch()
        }
    }

    /// Asks the server to terminate ahead of the app quitting. Returns once it has exited or
    /// `timeout` has passed, then kills it.
    func terminateForQuit(timeout: TimeInterval) async {
        restartTask?.cancel()
        restartTask = nil
        restartRequested = false
        guard let process, !process.hasExited else { return }
        userRequestedStop = true
        process.terminate(grace: timeout)
        let deadline = Date().addingTimeInterval(timeout + 0.5)
        while !process.hasExited, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func launch() {
        restartTask = nil
        userRequestedStop = false
        restartRequested = false
        outputTail = ""
        launchedAt = Date()
        status = .connecting

        do {
            let process = try RemoteControlProcess(
                directoryURL: path, name: name, spawnMode: spawnMode ?? .current, cols: terminal.cols, rows: terminal.rows)
            process.onOutput = { [weak self] data in self?.receive(data) }
            process.onExit = { [weak self, weak process] status in
                guard let self, let process, self.process === process else { return }
                self.handleExit(status: status)
            }
            self.process = process
        } catch {
            status = .error(message: "Failed to launch claude: \(error.localizedDescription)")
            note("Failed to launch claude: \(error.localizedDescription)")
        }
    }

    private func receive(_ data: Data) {
        terminal.feed(data)
        if let chunk = String(data: data, encoding: .utf8) {
            outputTail += chunk
            if outputTail.count > Self.maxParsedCharacters {
                outputTail = String(outputTail.suffix(Self.maxParsedCharacters))
            }
        }

        guard case .connecting = status else { return }
        let stripped = OutputParser.stripANSI(outputTail)
        if let joinURL = OutputParser.joinURL(in: stripped) {
            status = .ready(joinURL: joinURL)
        }
    }

    private func handleExit(status exitStatus: Int32) {
        process = nil
        let stripped = OutputParser.stripANSI(outputTail)
        let untrusted =
            stripped.contains(OutputParser.workspaceNotTrustedMarker)
            ? OutputParser.workspaceNotTrustedLine(in: stripped) : nil
        let description = Self.describe(exitStatus: exitStatus)

        if restartRequested {
            consecutiveRestarts = 0
            launch()
            return
        }

        let decision = policy.decide(
            userRequestedStop: userRequestedStop,
            workspaceNotTrusted: untrusted,
            runDuration: Date().timeIntervalSince(launchedAt),
            consecutiveRestarts: consecutiveRestarts)

        switch decision {
        case .stopped:
            status = .stopped
            note("Stopped.")
        case .error(let message):
            status = .error(message: message)
            note(message)
        case .restart(let attempt, let delay):
            consecutiveRestarts = attempt
            restartCount += 1
            let retryAt = Date().addingTimeInterval(delay)
            status = .restarting(attempt: attempt, retryAt: retryAt, reason: description)
            note("claude \(description). Restarting in \(Int(delay.rounded(.up)))s (attempt \(attempt)).")
            restartTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.launch()
            }
        }
    }

    /// Writes a Tether-originated line into the terminal.
    private func note(_ message: String) {
        terminal.feed(text: "\r\n\u{1B}[2m[Tether] \(message)\u{1B}[0m\r\n")
    }

    private static func describe(exitStatus: Int32) -> String {
        let signal = exitStatus & 0x7f
        if signal == 0 { return "exited with code \((exitStatus >> 8) & 0xff)" }
        return "was killed by signal \(signal)"
    }
}
