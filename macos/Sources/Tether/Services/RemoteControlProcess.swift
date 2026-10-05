import Foundation

/// Spawns and supervises one `claude remote-control` child process for a single directory,
/// parsing its stdout/stderr to derive a `SessionStatus`.
final class RemoteControlProcess {
    typealias StatusHandler = (SessionStatus) -> Void

    /// Diagnostic output is capped to this many characters to bound memory use.
    private static let maxBufferedCharacters = 20_000

    private let directoryURL: URL
    private let name: String
    private let onStatusChange: StatusHandler

    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stdinPipe = Pipe()

    private var outputBuffer = ""
    private var didReportReady = false
    private var userRequestedStop = false
    private(set) var isRunning = false

    /// The launched process's id, once `start()` has succeeded.
    var pid: pid_t? {
        isRunning ? process.processIdentifier : nil
    }

    init(directoryURL: URL, name: String, onStatusChange: @escaping StatusHandler) {
        self.directoryURL = directoryURL
        self.name = name
        self.onStatusChange = onStatusChange
    }

    /// Launches `claude remote-control` with `directoryURL` as its working directory, through the
    /// user's login shell so `claude` resolves on the `PATH` their shell configures — GUI apps
    /// inherit only a minimal one.
    func start() {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = [
            "-l", "-i", "-c", "exec claude \"$@\"", "claude",
            "remote-control", "--name", name, "--no-create-session-in-dir",
        ]
        process.currentDirectoryURL = directoryURL

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.handleOutput(handle.availableData)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.handleOutput(handle.availableData)
        }

        process.terminationHandler = { [weak self] finishedProcess in
            self?.handleTermination(finishedProcess)
        }

        do {
            try process.run()
            isRunning = true
            // stdin is never written to; closing our end immediately makes it behave like /dev/null.
            stdinPipe.fileHandleForWriting.closeFile()
        } catch {
            let message = "Failed to launch claude: \(error.localizedDescription)"
            DispatchQueue.main.async { [onStatusChange] in
                onStatusChange(.error(message: message))
            }
        }
    }

    /// Sends `SIGTERM` and lets the process exit on its own.
    func stop() {
        guard isRunning else { return }
        userRequestedStop = true
        process.terminate()
    }

    private func handleOutput(_ data: Data) {
        guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.appendAndParse(chunk)
        }
    }

    private func appendAndParse(_ chunk: String) {
        outputBuffer += chunk
        if outputBuffer.count > Self.maxBufferedCharacters {
            outputBuffer = String(outputBuffer.suffix(Self.maxBufferedCharacters))
        }

        guard !didReportReady else { return }

        let stripped = OutputParser.stripANSI(outputBuffer)

        if let joinURL = OutputParser.joinURL(in: stripped) {
            didReportReady = true
            onStatusChange(.ready(joinURL: joinURL))
            return
        }

        if stripped.contains(OutputParser.workspaceNotTrustedMarker) {
            onStatusChange(.error(message: OutputParser.workspaceNotTrustedLine(in: stripped)))
        }
    }

    private func handleTermination(_ finishedProcess: Process) {
        isRunning = false
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if self.userRequestedStop {
                self.onStatusChange(.stopped)
                return
            }

            let stripped = OutputParser.stripANSI(self.outputBuffer)

            if stripped.contains(OutputParser.workspaceNotTrustedMarker) {
                self.onStatusChange(.error(message: OutputParser.workspaceNotTrustedLine(in: stripped)))
            } else if finishedProcess.terminationStatus != 0 {
                let tail = OutputParser.removingShellNoise(from: stripped).suffix(500)
                self.onStatusChange(
                    .error(
                        message: "claude remote-control exited unexpectedly "
                            + "(code \(finishedProcess.terminationStatus)): \(tail)"
                    )
                )
            } else {
                self.onStatusChange(.stopped)
            }
        }
    }
}
