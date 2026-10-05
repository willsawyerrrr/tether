# Tether (macOS)

A menu bar app for starting, watching, and stopping `claude remote-control`
server sessions — one per directory — without keeping a terminal open. No
Dock icon, no main window: the menu bar icon and its popover are the entire
UI.

Targets macOS 13+.

## Installing

```
brew install willsawyerrrr/tap/tether
```

This builds the app from source (Xcode required) and puts the `tether`
command on your `PATH`. Turn on "Launch at Login" in the menu bar popover to
start the app at every login.

## Structure

This is a Swift Package Manager package, not an `.xcodeproj`:

- `Package.swift` — package manifest.
- `Resources/Info.plist` and `scripts/build-app.sh` — assemble `Tether.app`.
- `Sources/TetherIPC/` — the control-socket protocol and POSIX helpers shared
  by the app and the CLI.
- `Sources/TetherCLI/` — the `tether` command-line client (built as `tetherctl`,
  so it can sit beside the app executable in the bundle).
- `Sources/Tether/` — app source.
  - `TetherApp.swift` — `MenuBarExtra` scene and app delegate
    (accessory activation policy).
  - `Models/` — `SessionStatus`, `DirectoryRecord`, `ManagedDirectory`.
  - `Services/` — `RemoteControlProcess` (spawns and parses
    `claude remote-control`), `DirectoryStore` (persistence), `AppModel`
    (app-wide state), `ControlServer` (the control socket `tether` talks to).
  - `Views/` — `MenuBarContentView`, `DirectoryRowView`.

## Opening and running

- In Xcode: `open Package.swift`, then run the `Tether` scheme.
- From the command line: `swift run` (from this directory).

## Building the app bundle

`scripts/build-app.sh [--install] [output-dir] [version]` builds `Tether.app`
(ad-hoc signed, with `tetherctl` alongside the app in `Contents/MacOS/`) into
`output-dir` (default `.build/app`). `--install` also copies it to
`/Applications` and links it into `/usr/local/bin` as `tether`.

## Command line

`tether` controls the running app over a Unix domain socket at
`~/Library/Application Support/Tether/tether.sock` (owner-only):

```
tether add [directory]        # add a directory and start its server
tether remove [directory]     # stop its server and remove it
tether start [directory]
tether stop [directory]
```

`directory` defaults to the current directory. `brew install` or
`scripts/build-app.sh --install` puts it on your `PATH`; the app must be
running.

## Notes

- "Launch at Login" registers the app with `SMAppService.mainApp`, so it only
  takes effect for the installed `Tether.app` bundle (not `swift run`).
- The directory list persists across launches at
  `~/Library/Application Support/Tether/directories.json`.
  Quitting the app leaves any running servers running, so they keep fronting
  sessions someone might be connected to. Every launch starts a server for
  each directory in that list, or, for one detected as still running from
  before this app last quit, reuses the join URL it reported (persisted with
  the directory) rather than starting a competing duplicate. If it hadn't
  reported one yet, it's marked running and can only be stopped.
- A directory must already have its Claude Code workspace trust dialog
  accepted (`claude` run there once, interactively) before its server can
  start; otherwise the directory's status surfaces the trust error verbatim.
