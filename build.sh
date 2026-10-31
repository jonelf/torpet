#!/usr/bin/env bash
# Bygger Torpet.app. "./build.sh install" lägger den i ~/Applications och startar den.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/Torpet.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Torpet "$APP/Contents/MacOS/Torpet"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>se.torpet.menubar</string>
  <key>CFBundleName</key><string>Torpet</string>
  <key>CFBundleDisplayName</key><string>Torpet</string>
  <key>CFBundleExecutable</key><string>Torpet</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>sv</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Byggde $APP"

if [ "${1:-}" = "install" ]; then
  mkdir -p "$HOME/Applications"
  pkill -x Torpet 2>/dev/null || true
  rm -rf "$HOME/Applications/Torpet.app"
  cp -R "$APP" "$HOME/Applications/"
  open "$HOME/Applications/Torpet.app"
  echo "Installerad i ~/Applications och startad"
fi
