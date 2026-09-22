#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
APP_DIR="$ROOT_DIR/.build/AgentMon.app"
STAGING_DIR="$ROOT_DIR/.build/dmg-root"
OUTPUT_DIR="$ROOT_DIR/dist"
DMG_PATH="$OUTPUT_DIR/AgentMon.dmg"

cd "$ROOT_DIR"
sh scripts/package-app.sh

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

echo "Built $DMG_PATH"
