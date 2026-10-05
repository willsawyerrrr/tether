# Tether for Claude Code

[![CI](https://github.com/willsawyerrrr/tether/actions/workflows/ci.yml/badge.svg)](https://github.com/willsawyerrrr/tether/actions/workflows/ci.yml)

Tether is a pair of native macOS menu bar and Windows system tray apps for starting, watching, and
stopping [`claude remote-control`](https://claude.ai/code) server sessions —
one per directory — without keeping a terminal open.

Pick a directory, start a server in it, get a join link (or QR code) for
[claude.ai/code](https://claude.ai/code) or the Claude mobile app, and stop it
when you're done. Each running server shows its status inline.

## Layout

- [`macos/`](macos/) — SwiftUI menu bar app.
- [`windows/`](windows/) — native .NET system tray app.

Each app is built and run from its own native toolchain (Xcode / Visual
Studio); see that directory's README for setup.

## Installing

The macOS app is available as a Homebrew cask:

```
brew install --cask willsawyerrrr/tap/tether
```

See [`macos/README.md`](macos/README.md#installing) for details.

## Requirements

- A directory must already have its Claude Code workspace trust dialog
  accepted (run `claude` in it once, interactively) before a server can be
  started there.
- A Claude subscription, logged in via the `claude` CLI.
