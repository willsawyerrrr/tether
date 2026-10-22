# CLAUDE.md

## Repo purpose

Two independent native apps, `macos/` (SwiftUI) and `windows/` (.NET), that
each drive `claude remote-control` as a background child process per
directory the user adds. Neither app uses Electron, Tauri, or any other
cross-platform shell — each is built with its platform's own native UI
toolkit.

## How `claude remote-control` behaves

- It is a real CLI subcommand, run with the target directory as its working
  directory (not a positional argument): spawn it with `cwd` set to the
  directory the user picked.
- It can run headless (no TTY, piped output), but it writes an
  ANSI-decorated live status panel (cursor-movement escape sequences) and
  accepts keyboard input, so the macOS app runs it on a pseudo-terminal.
  Strip ANSI codes before parsing lines.
- A directory must already have its workspace trust dialog accepted (`claude`
  run there once, interactively) or the process exits immediately with
  `Error: Workspace not trusted. Please run \`claude\` in <dir> first...`
  (exit code 1). Surface this error as-is rather than trying to work around
  it — trust acceptance is a security boundary, not this app's to bypass.
- Once ready, it prints a line containing a `https://claude.ai/code?environment=env_...`
  URL — that's the join link/QR code target to show the user — and a `Ready`
  status line.
- Shuts down cleanly on a normal terminate signal (`SIGTERM` on macOS; on
  Windows, `Process.Kill()` is the only reliable option since it has no
  console to send a Ctrl+C event to when run detached).
- `--spawn <same-dir|worktree>` picks where sessions run: in the directory
  itself, or (worktree) each on-demand session in an isolated git worktree.
- One child process per directory; there's no single daemon the apps need to
  share or multiplex themselves — `claude remote-control` handles that
  internally.

## Structure

- `macos/` (SwiftPM): `Tether` window and menu bar app. The main window
  (`NavigationSplitView`) lists directories and shows the selected one's live
  terminal, rendered by SwiftTerm. Each server runs on a pseudo-terminal Tether
  owns for its whole life (`RemoteControlProcess`); output feeds a per-directory
  `TerminalSession` that outlives the window. Closing the window leaves Tether
  in the menu bar (Dock icon only while a window is open) with servers running;
  quitting terminates them (`SIGTERM`, then `SIGKILL`). A server that exits
  unexpectedly is restarted with capped exponential backoff (`RestartPolicy`);
  an untrusted workspace is surfaced as an error without restarting.
  The `TetherIPC` library holds the
  control protocol (newline-terminated JSON `ControlRequest`/`ControlResponse`
  for `add`/`remove`/`start`/`stop`; `add` takes an optional `SpawnMode`) and the Unix socket helpers; `tetherctl`
  CLI client (symlinked as `tether`). The app listens on
  `~/Library/Application Support/Tether/tether.sock`; `tetherctl` connects to it.
- `windows/Tether/` (.NET 10): tray app; no CLI or control socket.
- `assets/logo.png`: app logo (1024x1024), generated with the platform repo's
  `scripts/generate-logo`. `scripts/generate-icons.sh` crops it to
  `assets/icon.png` and derives `macos/Resources/Tether.icns` (bundled as the
  app icon by `build-app.sh`) and `windows/Tether/Tether.ico` (the exe's
  `ApplicationIcon` and the tray icon).
- Persistence: each app saves its added directories (macOS: with each one's
  spawn-mode override, if any; the default lives in `UserDefaults` and is set in Settings) as `directories.json` —
  macOS in `~/Library/Application Support/Tether/`, Windows in
  `%APPDATA%\Tether\`.

## Testing

macOS: XCTest target `TetherTests` (`macos/Tests/TetherTests/`), run with
`swift test` from `macos/`. Parsing of `claude remote-control` output lives in
`OutputParser`, and restart/backoff decisions in `RestartPolicy`, so both can be
tested without spawning a process.

## CI

`.github/workflows/ci.yml` runs on pushes and PRs to `main`. A path filter gates
the `macos` (`swift build` and `swift test`) and `windows`
(`dotnet build -c Release`) jobs on changes under `macos/**` and `windows/**` (always run on push). The `CI Status`
job aggregates them and is the single required check, so a PR touching one app
isn't blocked on the other's skipped job. Runs are grouped by workflow and ref;
a newer push cancels an in-progress PR run but never a `main` run. `release.yml` reuses the shared
workflow in `willsawyerrrr/platform` (see Releases).

## Runtime parity

The macOS app builds with Xcode 26.6 in CI, local development and release: `ci.yml` pins `macos-26` and `maxim-lobanov/setup-xcode` to `26.6`, and `.xcode-version` records it. Bump all of them together.

The Windows app runs on .NET 10 in CI and local development (it has no production release, so the newest LTS sets the version): `TargetFramework` in both csprojs, `windows/global.json`, `actions/setup-dotnet` in `ci.yml` and the pinned `windows-2025` runner all use it. Bump them together.

## Conventions

Standard [willsawyerrrr.dev conventions](../../CLAUDE.md) apply: branch per
feature, one PR per feature, auto-merge once open, Claude owns the git/PR
lifecycle end to end.

## Releases

Every merge to `main` publishes a GitHub release (`.github/workflows/release.yml`):
a `feat` commit bumps the minor version, anything else the patch version. The
release builds `Tether.app` with `macos/scripts/package-app.sh`, which signs it
with the Developer ID identity (hardened runtime), notarises and staples it, and
zips it to `Tether.zip`; that asset is uploaded to the release. Signing and
notarisation use the repository secrets `DEVELOPER_ID_P12`,
`DEVELOPER_ID_P12_PASSWORD`, `NOTARY_KEY` (App Store Connect `.p8`),
`NOTARY_KEY_ID`, and `NOTARY_ISSUER_ID`, which the shared workflow exposes to the
build as `SIGNING_IDENTITY` and `NOTARY_KEY_PATH`/`NOTARY_KEY_ID`/`NOTARY_ISSUER_ID`;
without them the build is ad-hoc signed and not notarised. The shared
workflow then commits the new version and sha256 to `Casks/tether.rb` in
`willsawyerrrr/homebrew-tap`, so `brew upgrade --cask tether` picks it up
immediately. Releases created by hand (`gh release create`) trigger the same
update.
