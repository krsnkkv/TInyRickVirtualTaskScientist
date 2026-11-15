#!/bin/zsh
# Builds Rick.app — a desktop pet that keeps your priority list.
set -e
cd "$(dirname "$0")"

APP="Rick.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
  Sources/Pet.swift Sources/HotKeys.swift Sources/Personality.swift Sources/Sprite.swift Sources/DueDates.swift Sources/Matrix.swift Sources/main.swift \
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
</dict>
</plist>
PLIST

cp Personality.md "$APP/Contents/Resources/Personality.md"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP — run it with: open $APP"
