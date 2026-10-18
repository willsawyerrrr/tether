#!/bin/bash
# Generates the app icons from `assets/logo.png`: `assets/icon.png` (the logo
# cropped to its mark), `macos/Resources/Tether.icns`, and `windows/Tether/Tether.ico`.
#
# Usage: scripts/generate-icons.sh
#
# Requires ImageMagick and `iconutil`.
set -euo pipefail

cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT

magick assets/logo.png -crop 560x560+232+232 +repage -resize 1024x1024 assets/icon.png

set="$tmp/Tether.iconset"
mkdir "$set"
for size in 16 32 128 256 512; do
    magick assets/icon.png -resize "${size}x${size}" "$set/icon_${size}x${size}.png"
    magick assets/icon.png -resize "$((size * 2))x$((size * 2))" "$set/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$set" -o macos/Resources/Tether.icns

magick assets/icon.png -define icon:auto-resize=256,128,64,48,32,24,16 windows/Tether/Tether.ico
