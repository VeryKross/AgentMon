#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CONFIGURATION=${CONFIGURATION:-release}
SIGNING_IDENTITY=${CODESIGN_IDENTITY:--}
APP_VERSION=${APP_VERSION:-0.2.0}
BUILD_NUMBER=${BUILD_NUMBER:-5}
APP_DIR="$ROOT_DIR/.build/AgentMon.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/$CONFIGURATION/AgentMon" "$MACOS_DIR/AgentMon"
cp "$ROOT_DIR/Assets/AgentMon.icns" "$RESOURCES_DIR/AgentMon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>AgentMon</string>
    <key>CFBundleExecutable</key>
    <string>AgentMon</string>
    <key>CFBundleIdentifier</key>
    <string>com.verykross.AgentMon</string>
    <key>CFBundleIconFile</key>
    <string>AgentMon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>AgentMon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>AgentMon connects to paired Copilot session relays on your private network.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_agentmon._tcp</string>
    </array>
</dict>
</plist>
PLIST

if [ "$SIGNING_IDENTITY" = "-" ]; then
  codesign --force --deep --sign - "$APP_DIR"
else
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$APP_DIR"
fi
echo "Built $APP_DIR"
