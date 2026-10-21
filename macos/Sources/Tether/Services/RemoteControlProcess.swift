import Darwin
import Foundation

/// One `claude remote-control` child process attached to a pseudo-terminal, so it renders its
/// interactive status panel and accepts keyboard input exactly as it would in a terminal.
/// All callbacks run on the main queue.
final class RemoteControlProcess {
    private let master: Int32
    private let pid: pid_t
    private let readSource: DispatchSourceRead
    private let exitSource: DispatchSourceProcess
    private let writeQueue = DispatchQueue(label: "dev.willsawyerrrr.tether.pty-write")
    private var closed = false

    /// Called with bytes the process wrote to its terminal.
    var onOutput: ((Data) -> Void)?

    /// Called once with the process's exit status (raw `waitpid` status).
    var onExit: ((Int32) -> Void)?

    enum LaunchError: Error, LocalizedError {
        case openpty(Int32)
        case spawn(Int32)

        var errorDescription: String? {
            switch self {
            case .openpty(let code): "openpty failed: \(String(cString: strerror(code)))"
            case .spawn(let code): "posix_spawn failed: \(String(cString: strerror(code)))"
            }
        }
    }

    /// Launches `claude remote-control` with `directoryURL` as its working directory, through the
    /// user's login shell so `claude` resolves on the `PATH` their shell configures — GUI apps
    /// inherit only a minimal one.
    init(directoryURL: URL, name: String, cols: Int, rows: Int) throws {
        var window = winsize(
            ws_row: UInt16(clamping: rows), ws_col: UInt16(clamping: cols), ws_xpixel: 0, ws_ypixel: 0)
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        guard openpty(&masterFD, &slaveFD, nil, nil, &window) == 0 else {
            throw LaunchError.openpty(errno)
        }
        defer { close(slaveFD) }

        var slaveName = [CChar](repeating: 0, count: 128)
        ttyname_r(slaveFD, &slaveName, slaveName.count)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        // Opening the terminal in the new session's leader makes it the controlling terminal.
        posix_spawn_file_actions_addopen(&actions, 0, slaveName, O_RDWR, 0)
        posix_spawn_file_actions_adddup2(&actions, 0, 1)
        posix_spawn_file_actions_adddup2(&actions, 0, 2)
        posix_spawn_file_actions_addchdir_np(&actions, directoryURL.path)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let arguments = [
            shell, "-l", "-i", "-c", "exec claude \"$@\"", "claude",
            "remote-control", "--name", name, "--no-create-session-in-dir",
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        let environmentStrings = environment.map { "\($0.key)=\($0.value)" }

        let argv = arguments.map { strdup($0) } + [nil]
        let envp = environmentStrings.map { strdup($0) } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var childPID: pid_t = 0
        let result = posix_spawn(&childPID, shell, &actions, &attributes, argv, envp)
        guard result == 0 else {
            close(masterFD)
            throw LaunchError.spawn(result)
        }

        master = masterFD
        pid = childPID
        _ = fcntl(masterFD, F_SETFL, fcntl(masterFD, F_GETFL) | O_NONBLOCK)
        _ = fcntl(masterFD, F_SETFD, FD_CLOEXEC)

        readSource = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: .main)
        exitSource = DispatchSource.makeProcessSource(identifier: childPID, eventMask: .exit, queue: .main)

        readSource.setEventHandler { [weak self] in self?.drain() }
        readSource.setCancelHandler { close(masterFD) }
        exitSource.setEventHandler { [weak self] in self?.reap() }
        readSource.resume()
        exitSource.resume()
    }

    /// Sends keyboard input to the process.
    func write(_ data: Data) {
        let fd = master
        writeQueue.async {
            data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let count = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                    if count > 0 {
                        offset += count
                    } else if count < 0, errno == EAGAIN || errno == EINTR {
                        usleep(1_000)
                    } else {
                        return
                    }
                }
            }
        }
    }

    /// Tells the process its terminal's new size.
    func resize(cols: Int, rows: Int) {
        guard !closed else { return }
        var window = winsize(
            ws_row: UInt16(clamping: rows), ws_col: UInt16(clamping: cols), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(master, TIOCSWINSZ, &window)
    }

    /// Sends `SIGTERM` to the process's group, then `SIGKILL` if it's still alive after `grace`.
    func terminate(grace: TimeInterval = 3) {
        guard !closed else { return }
        killpg(pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + grace) { [weak self] in
            guard let self, !self.closed else { return }
            killpg(self.pid, SIGKILL)
        }
    }

    /// Whether the process has exited and been reaped.
    var hasExited: Bool { closed }

    private func drain() {
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = read(master, &buffer, buffer.count)
            if count > 0 {
                onOutput?(Data(buffer[0..<count]))
            } else {
                return
            }
        }
    }

    private func reap() {
        guard !closed else { return }
        drain()
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        closed = true
        readSource.cancel()
        exitSource.cancel()
        let handler = onExit
        onOutput = nil
        onExit = nil
        handler?(status)
    }
}
