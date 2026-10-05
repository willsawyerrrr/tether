#!/bin/bash
# Builds `Tether.app` (containing the app and `tetherctl`) into the given output directory.
#
# Usage: scripts/build-app.sh [--install] [output-dir] [version]
#
# Signs with the Developer ID identity in `SIGNING_IDENTITY` (hardened runtime,
# secure timestamp) when set, ad hoc otherwise.
#
# `--install` also copies the app to /Applications and links `tether` into
# /usr/local/bin.
set -euo pipefail

install=false
if [[ "${1:-}" == "--install" ]]; then
    install=true
    shift
fi

cd "$(dirname "$0")/.."
out="${1:-.build/app}"
version="${2:-0.0.0}"
app="$out/Tether.app"

swift build -c release
bin="$(swift build -c release --show-bin-path)"

rm -r "$app" 2>/dev/null || true
mkdir -p "$app/Contents/MacOS"
cp "$bin/Tether" "$bin/tetherctl" "$app/Contents/MacOS/"
sed "s/__VERSION__/$version/g" Resources/Info.plist > "$app/Contents/Info.plist"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    for target in "$app/Contents/MacOS/tetherctl" "$app/Contents/MacOS/Tether" "$app"; do
        codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$target"
    done
else
    codesign --force --sign - --deep "$app"
fi
echo "Built $app"

if $install; then
    rm -r /Applications/Tether.app 2>/dev/null || true
    cp -R "$app" /Applications/
    mkdir -p /usr/local/bin
    ln -sf /Applications/Tether.app/Contents/MacOS/tetherctl /usr/local/bin/tether
    echo "Installed /Applications/Tether.app and /usr/local/bin/tether"
fi
