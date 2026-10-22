import Darwin
import Foundation
import TetherIPC

let usage = """
    Usage: tether <add|remove|start|stop> [--spawn same-dir|worktree] [directory]

    Controls the running Tether app. `directory` defaults to the current directory.
    `--spawn` (add only) sets where the directory's sessions run; default `same-dir`.
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())

guard let name = arguments.first, let command = ControlCommand(rawValue: name) else { fail(usage) }
arguments.removeFirst()

var spawnMode: SpawnMode?
if let flag = arguments.firstIndex(of: "--spawn") {
    guard command == .add, flag + 1 < arguments.count,
        let mode = SpawnMode(rawValue: arguments[flag + 1])
    else { fail(usage) }
    spawnMode = mode
    arguments.removeSubrange(flag...flag + 1)
}
guard arguments.count <= 1 else { fail(usage) }

let directory = arguments.first ?? "."
let path = URL(
    fileURLWithPath: (directory as NSString).expandingTildeInPath,
    isDirectory: true
).standardizedFileURL.path

let fd: Int32
do {
    fd = try ControlSocket.makeSocket(path: ControlSocket.path, mode: .connect)
} catch {
    fail("Can't reach Tether (\(error)). Is the app running?")
}
signal(SIGPIPE, SIG_IGN)

let request = try JSONEncoder().encode(ControlRequest(command: command, path: path, spawnMode: spawnMode))
ControlSocket.writeLine(request, to: fd)

guard let line = ControlSocket.readLine(from: fd),
    let response = try? JSONDecoder().decode(ControlResponse.self, from: line)
else {
    fail("Tether sent no valid response.")
}
close(fd)

if response.ok {
    print(response.message)
} else {
    fail(response.message)
}
