#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
APP="$PWD/dist/LaunchDock.app"
APP_VERSION="$(cat VERSION)"
ARCH="$(lipo -archs "$APP/Contents/MacOS/LaunchDock" | tr ' ' '-')"
OUTPUT="$PWD/dist/LaunchDock-${APP_VERSION}-${ARCH}.dmg"
WORK="$(mktemp -d "$PWD/.build/dmg.XXXXXX")"
MOUNT="$WORK/mount"
MOUNTED=0
cleanup() {
    if [[ "$MOUNTED" == 1 ]]; then
        if ! hdiutil detach "$MOUNT"; then
            echo "Could not unmount $MOUNT; temporary files retained at $WORK" >&2
            return 1
        fi
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$WORK/staging" "$MOUNT"
ditto "$APP" "$WORK/staging/LaunchDock.app"
ln -s /Applications "$WORK/staging/Applications"
hdiutil create -volname "LaunchDock $APP_VERSION" -srcfolder "$WORK/staging" \
    -format UDZO "$WORK/LaunchDock.dmg"
hdiutil verify "$WORK/LaunchDock.dmg"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$WORK/LaunchDock.dmg" >/dev/null
MOUNTED=1

# Validate the image's actual contents before replacing any existing deliverable.
[[ -d "$MOUNT/LaunchDock.app" ]]
[[ -L "$MOUNT/Applications" && "$(readlink "$MOUNT/Applications")" == /Applications ]]
PLIST="$MOUNT/LaunchDock.app/Contents/Info.plist"
[[ "$(plutil -extract CFBundleShortVersionString raw "$PLIST")" == "$APP_VERSION" ]]
[[ "$(plutil -extract CFBundleVersion raw "$PLIST")" == "$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")" ]]
[[ "$(plutil -extract CFBundleIconFile raw "$PLIST")" == AppIcon ]]
[[ "$(lipo -archs "$MOUNT/LaunchDock.app/Contents/MacOS/LaunchDock" | tr ' ' '-')" == "$ARCH" ]]
cmp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/LaunchDock.app/Contents/Resources/AppIcon.icns"
[[ -d "$MOUNT/LaunchDock.app/Contents/Frameworks/Sparkle.framework" ]]
[[ ! -e "$MOUNT/LaunchDock.app/Contents/Helpers/LaunchDockUpdateHelper" ]]
codesign --verify --deep --strict "$MOUNT/LaunchDock.app"
hdiutil detach "$MOUNT" >/dev/null
MOUNTED=0
mv -f "$WORK/LaunchDock.dmg" "$OUTPUT"
echo "Built and verified: $OUTPUT"
