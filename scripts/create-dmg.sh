#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
APP_DIR="$ROOT_DIR/.build/AgentMon.app"
NOTARIZATION_ZIP="$ROOT_DIR/.build/AgentMon-notarization.zip"
STAGING_DIR="$ROOT_DIR/.build/dmg-root"
OUTPUT_DIR="$ROOT_DIR/dist"
DMG_PATH="$OUTPUT_DIR/AgentMon.dmg"
NOTARY_PROFILE=${NOTARY_PROFILE:-}

cd "$ROOT_DIR"
sh scripts/package-app.sh

if [ -n "$NOTARY_PROFILE" ]; then
  if [ "${CODESIGN_IDENTITY:--}" = "-" ]; then
    echo "NOTARY_PROFILE requires a Developer ID CODESIGN_IDENTITY." >&2
    exit 1
  fi

  rm -f "$NOTARIZATION_ZIP"
  ditto -c -k --keepParent "$APP_DIR" "$NOTARIZATION_ZIP"
  xcrun notarytool submit \
    "$NOTARIZATION_ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$APP_DIR"
  xcrun stapler validate "$APP_DIR"
fi

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$OUTPUT_DIR"
ditto "$APP_DIR" "$STAGING_DIR/AgentMon.app"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "AgentMon" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [ "${CODESIGN_IDENTITY:--}" != "-" ]; then
  codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
fi

if [ -n "$NOTARY_PROFILE" ]; then
  xcrun notarytool submit \
    "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

echo "Built $DMG_PATH"
