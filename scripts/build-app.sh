#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product LaunchDock
APP="$PWD/dist/LaunchDock.app"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/LaunchDock" "$APP/Contents/MacOS/LaunchDock"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LaunchDock</string>
<key>CFBundleIdentifier</key><string>local.launchdock.app</string>
<key>CFBundleName</key><string>LaunchDock</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built: $APP"
