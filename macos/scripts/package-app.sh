#!/bin/bash
# Builds `Tether.app` and zips it to `Tether.zip` at the repository root.
#
# Usage: macos/scripts/package-app.sh [version]
#
# When `NOTARY_KEY_PATH`, `NOTARY_KEY_ID`, and `NOTARY_ISSUER_ID` are set, also
# notarises the zip and staples the ticket to the app before re-zipping. Pair
# with `SIGNING_IDENTITY` (see `build-app.sh`); notarisation rejects ad-hoc builds.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
version="${1:-0.0.0}"
app="$root/macos/.build/app/Tether.app"
zip="$root/Tether.zip"

"$root/macos/scripts/build-app.sh" .build/app "$version"
rm "$zip" 2>/dev/null || true
ditto -c -k --keepParent "$app" "$zip"

if [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
    result="$(xcrun notarytool submit "$zip" \
        --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
        --wait --output-format json)"
    echo "$result"
    status="$(plutil -extract status raw -o - - <<<"$result")"
    if [[ "$status" != "Accepted" ]]; then
        id="$(plutil -extract id raw -o - - <<<"$result")"
        xcrun notarytool log "$id" \
            --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" >&2
        echo "Notarisation failed: $status" >&2
        exit 1
    fi
    xcrun stapler staple "$app"
    rm "$zip"
    ditto -c -k --keepParent "$app" "$zip"
fi
echo "Packaged $zip"
