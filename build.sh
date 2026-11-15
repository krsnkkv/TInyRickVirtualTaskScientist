#!/bin/zsh
# Builds Mochi.app — a desktop pet that chats with Claude.
set -e
cd "$(dirname "$0")"

APP="Mochi.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
  Sources/Pet.swift Sources/Claude.swift Sources/main.swift \
  -o "$APP/Contents/MacOS/Mochi"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Mochi</string>
  <key>CFBundleDisplayName</key><string>Mochi</string>
  <key>CFBundleIdentifier</key><string>local.mochi.desktoppet</string>
  <key>CFBundleExecutable</key><string>Mochi</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP — run it with: open $APP"
