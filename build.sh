#!/bin/zsh
# Builds Rick.app — a desktop pet that keeps your priority list.
set -e
cd "$(dirname "$0")"

APP="Rick.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/Rick"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Rick</string>
  <key>CFBundleDisplayName</key><string>Rick</string>
  <key>CFBundleIdentifier</key><string>local.mochi.desktoppet</string>
  <key>CFBundleExecutable</key><string>Rick</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Shows today's events next to your list, gives you a heads-up before meetings, and lets tasks with a due date go into your calendar.</string>
  <key>NSCalendarsUsageDescription</key><string>Shows today's events next to your list, gives you a heads-up before meetings, and lets tasks with a due date go into your calendar.</string>
</dict>
</plist>
PLIST

cp -R Profiles "$APP/Contents/Resources/Profiles"     # built-in characters
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP — run it with: open $APP"
