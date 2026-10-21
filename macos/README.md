# Tether (macOS)

A window and menu bar app for running `claude remote-control` server sessions —
one per directory — without keeping a terminal open: Tether is the terminal.
The main window lists your directories and shows the selected one's live
terminal (keyboard input included), with toolbar controls to start, stop,
restart, copy the join URL, remove, and add directories. The menu bar item
offers the same list in a popover plus an "Open Tether" action.

Closing the window leaves Tether running in the menu bar with every server
alive; the Dock icon appears only while a window is open. Quitting Tether
terminates the servers.

Targets macOS 13+.

## Installing

```
brew install --cask willsawyerrrr/tap/tether
```

This installs `Tether.app` into `/Applications` and puts the `tether` command
on your `PATH`.

## Structure

This is a Swift Package Manager package, not an `.xcodeproj`:

- `Package.swift` — package manifest.
- `Resources/Info.plist` and `scripts/build-app.sh` — assemble `Tether.app`.
- `Sources/TetherIPC/` — the control-socket protocol and POSIX helpers shared
  by the app and the CLI.
- `Sources/TetherCLI/` — the `tether` command-line client (built as `tetherctl`,
  so it can sit beside the app executable in the bundle).
- `Tests/TetherTests/` — XCTest suite for the output parser, `SessionStatus`,
  `RestartPolicy`, directory record decoding, and the control protocol coding.
- `Sources/Tether/` — app source.
  - `TetherApp.swift` — main window and `MenuBarExtra` scenes, and the app
    delegate (activation policy, quit handling).
  - `Models/` — `SessionStatus`, `RestartPolicy`, `DirectoryRecord`,
    `ManagedDirectory` (supervises one server).
  - `Services/` — `RemoteControlProcess` (runs `claude remote-control` on a
    pseudo-terminal), `TerminalSession` (the directory's
    [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) terminal),
    `OutputParser` (parses its output), `DirectoryStore` (persistence),
    `AppModel` (app-wide state), `ControlServer` (the control socket `tether`
    talks to).
  - `Views/` — `MainWindowView`, `TerminalContainerView`, `StatusIndicator`,
    `MenuBarContentView`, `DirectoryRowView`.

## Opening and running

- In Xcode: `open Package.swift`, then run the `Tether` scheme.
- From the command line: `swift run` (from this directory).

## Testing

`swift test` (from this directory).

## Building the app bundle

`scripts/build-app.sh [--install] [output-dir] [version]` builds `Tether.app`
(with `tetherctl` alongside the app in `Contents/MacOS/`) into `output-dir`
(default `.build/app`). It is ad-hoc signed unless `SIGNING_IDENTITY` names a
Developer ID Application identity, in which case each executable and the
bundle are signed with the hardened runtime and a secure timestamp. The app
needs no entitlements. `--install` also copies it to
`/Applications` and links it into `/usr/local/bin` as `tether`.

`scripts/package-app.sh [version]` builds the app and zips it to `Tether.zip`
at the repository root. When `NOTARY_KEY_PATH`, `NOTARY_KEY_ID`, and
`NOTARY_ISSUER_ID` are set, it also notarises the zip with `notarytool`
(failing, with the log, unless Accepted), staples the ticket to the app, and
re-zips.

## Command line

`tether` controls the running app over a Unix domain socket at
`~/Library/Application Support/Tether/tether.sock` (owner-only):

```
tether add [directory]        # add a directory and start its server
tether remove [directory]     # stop its server and remove it
tether start [directory]
tether stop [directory]
```

`directory` defaults to the current directory. `brew install --cask` or
`scripts/build-app.sh --install` puts it on your `PATH`; the app must be
running.

## Notes

- The directory list persists across launches at
  `~/Library/Application Support/Tether/directories.json`; every launch starts
  a server for each directory in it.
- Each server runs on a pseudo-terminal Tether owns, resized with the terminal
  view. Output is kept per directory (10,000 lines of scrollback), so it
  persists across directory switches and window closes.
- A server that exits unexpectedly is restarted after 2s, doubling up to 60s;
  a run of at least 60s resets the backoff. The status shows the exit reason,
  a countdown to the next attempt, and the restart count, and the terminal
  keeps the output. Stopping or restarting from Tether never triggers this.
- Quitting sends `SIGTERM` to each server, waits up to 3s, then `SIGKILL`s.
- A directory must already have its Claude Code workspace trust dialog
  accepted (`claude` run there once, interactively) before its server can
  start; otherwise the directory's status surfaces the trust error verbatim.
