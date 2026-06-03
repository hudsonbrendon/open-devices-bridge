#!/usr/bin/env bash
# Builds HABatteryBridge.app (release) and ad-hoc signs it.
# Ad-hoc signing is required so macOS attributes the Bluetooth permission prompt.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/HA Battery Bridge.app"
BIN_NAME="HABatteryBridge"

echo "==> swift build -c release"
swift build -c release --product "$BIN_NAME"
BIN_PATH="$(swift build -c release --product "$BIN_NAME" --show-bin-path)/$BIN_NAME"

echo "==> assembling bundle: $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"
cp packaging/Info.plist "$APP/Contents/Info.plist"
[ -f packaging/AppIcon.icns ] && cp packaging/AppIcon.icns "$APP/Contents/Resources/"

echo "==> ad-hoc codesign"
codesign --force --deep --sign - --options runtime \
  --identifier online.99lab.habatterybridge "$APP"

echo "==> done: $APP"
codesign -dv "$APP" 2>&1 | sed 's/^/    /' || true
