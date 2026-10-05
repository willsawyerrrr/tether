# Tether (Windows)

Native Windows system tray app for managing `claude remote-control` server
sessions, one per directory. Built with WinForms
(`System.Windows.Forms.NotifyIcon`) targeting `net8.0-windows`. There's no
main window — everything happens through the tray icon's context menu.

## Requirements

- Windows, with the .NET 8 SDK and the "Windows Desktop" (WinForms) workload.
- The `claude` CLI on `PATH`, logged in, with a Claude subscription.
- Each directory you manage must already have had its Claude Code workspace
  trust dialog accepted (run `claude` in it once, interactively, first).

## Build & run

From `windows/Tether/`:

```
dotnet run
```

or open the `windows/Tether/` folder directly in Visual Studio
(File → Open → Folder) and run/debug from there — no `.sln` is needed.

## Testing

From `windows/Tether.Tests/`:

```
dotnet test
```

The xUnit project covers the pure helpers (`AnsiStripper`, `WslPath`) and
runs in CI.

## Usage

- Left- or right-click the tray icon for the context menu.
- **Add Directory...** opens a folder picker; the directory is added to the
  list (stopped) and persisted.
- Each directory is a submenu showing its status (Stopped / Connecting /
  Ready / Error) with **Start**/**Stop**, **Copy Join URL** (once Ready), and
  **Remove**.
- **Quit** leaves running servers running.

The directory list persists across restarts at
`%APPDATA%\Tether\directories.json`, along with each running
server's process id and join URL. A server still running on the next launch
keeps its join URL and is not started again; if it hadn't reported one yet,
it's marked running and can only be stopped. Servers are never auto-started
on launch.
