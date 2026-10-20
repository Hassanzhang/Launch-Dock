#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product LaunchDock
APP="$PWD/dist/LaunchDock.app"
APP_VERSION="$(cat VERSION)"
ICONSET="$PWD/.build/AppIcon.iconset"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" "$ICONSET"
# Replace atomically so rebuilding never truncates a running executable.
cp "$(swift build -c release --show-bin-path)/LaunchDock" "$APP/Contents/MacOS/LaunchDock.next"
mv -f "$APP/Contents/MacOS/LaunchDock.next" "$APP/Contents/MacOS/LaunchDock"
# Remove the retired updater when reusing an existing output bundle.
rm -f "$APP/Contents/Helpers/LaunchDockUpdateHelper"
if [[ -d "$APP/Contents/Helpers" ]]; then rmdir "$APP/Contents/Helpers" 2>/dev/null || true; fi
rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
ditto "$(swift build -c release --show-bin-path)/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" Assets/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp ThirdParty/Sparkle-LICENSE.txt "$APP/Contents/Resources/Sparkle-LICENSE.txt"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LaunchDock</string>
<key>CFBundleIdentifier</key><string>local.launchdock.app</string>
<key>CFBundleName</key><string>LaunchDock</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleVersion</key><string>4</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
plutil -insert CFBundleShortVersionString -string "$APP_VERSION" "$APP/Contents/Info.plist"
python3 - "$APP/Contents/Info.plist" <<'PYTHON'
import plistlib, sys
from pathlib import Path
path = Path(sys.argv[1])
info = plistlib.loads(path.read_bytes())
info.update(plistlib.loads(Path("Updates/Sparkle.plist").read_bytes()))
path.write_bytes(plistlib.dumps(info))
PYTHON
codesign --force --sign - "$APP"
echo "Built: $APP"
