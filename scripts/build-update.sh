#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
TOOLS="$PWD/.build/artifacts/sparkle/Sparkle/bin"
ACCOUNT="local.launchdock.app"
PUBLIC_KEY="$("$TOOLS/generate_keys" --account "$ACCOUNT" -p)"
EXPECTED_KEY="$(plutil -extract SUPublicEDKey raw Updates/Sparkle.plist)"
[[ "$PUBLIC_KEY" == "$EXPECTED_KEY" ]] || { echo "Signing key does not match Updates/Sparkle.plist" >&2; exit 1; }
APP="$PWD/dist/LaunchDock.app"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")"
ARCH="$(lipo -archs "$APP/Contents/MacOS/LaunchDock" | tr ' ' '-')"
NAME="LaunchDock-${VERSION}-${BUILD}-${ARCH}"
WORK="$(mktemp -d "$PWD/.build/update-release.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p dist/updates
ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/$NAME.zip"
cp Updates/release-notes.html "$WORK/$NAME.html"
"$TOOLS/generate_appcast" --account "$ACCOUNT" \
    --download-url-prefix "https://github.com/Hassanzhang/Launch-Dock/releases/download/v${VERSION}/" \
    --link "https://github.com/Hassanzhang/Launch-Dock" \
    --maximum-versions 1 --maximum-deltas 0 --embed-release-notes "$WORK"
# Validate the generated signature using only the public key embedded in the app.
swift scripts/check-update.swift "$WORK/appcast.xml" "$WORK/$NAME.zip" Updates/Sparkle.plist
cp "$WORK/$NAME.zip" "dist/updates/$NAME.zip"
cp "$WORK/appcast.xml" dist/updates/appcast.xml
echo "Prepared: dist/updates/$NAME.zip and dist/updates/appcast.xml"
echo "Not published. Upload these two files to GitHub Release v$VERSION only after validation."
