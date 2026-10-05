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
- It runs fully headless: no TTY is required, stdin can be empty, and
  stdout/stderr can be redirected or piped. It still writes an
  ANSI-decorated live status panel to stdout (cursor-movement escape
  sequences) — strip ANSI codes before parsing lines.
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
- One child process per directory; there's no single daemon the apps need to
  share or multiplex themselves — `claude remote-control` handles that
  internally.

## Structure

- `macos/` (SwiftPM): `Tether` menu bar app; `TetherIPC` library holding the
  control protocol (newline-terminated JSON `ControlRequest`/`ControlResponse`
  for `add`/`remove`/`start`/`stop`) and the Unix socket helpers; `tetherctl`
  CLI client (symlinked as `tether`). The app listens on
  `~/Library/Application Support/Tether/tether.sock`; `tetherctl` connects to it.
- `windows/Tether/` (.NET 8): tray app; no CLI or control socket.
- Persistence: each app saves its added directories as `directories.json` —
  macOS in `~/Library/Application Support/Tether/`, Windows in
  `%APPDATA%\Tether\`.

## Testing

macOS: XCTest target `TetherTests` (`macos/Tests/TetherTests/`), run with
`swift test` from `macos/`. Parsing of `claude remote-control` output lives in
`OutputParser` so it can be tested without spawning a process.

## CI

`.github/workflows/ci.yml` runs on pushes and PRs to `main`. A path filter gates
the `macos` (`swift build` and `swift test`) and `windows`
(`dotnet build -c Release`) jobs on changes under `macos/**` and `windows/**` (always run on push). The `CI Status`
job aggregates them and is the single required check, so a PR touching one app
isn't blocked on the other's skipped job. Runs are grouped by workflow and ref;
a newer push cancels an in-progress PR run but never a `main` run. `release.yml` reuses the shared
workflow in `willsawyerrrr/platform` (see Releases).

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
