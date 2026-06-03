#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-app.sh

APP="build/Open Devices Bridge.app"
DMG="build/Open-Devices-Bridge.dmg"
STAGE="build/dmg-stage"
rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Open Devices Bridge" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
echo "==> done: $DMG (unsigned; first run: right-click > Open, or xattr -dr com.apple.quarantine)"
