#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Open Devices Bridge.app"
RES="$APP/Contents/Resources"

echo "==> build Go host"
go build -o build/odb ./cmd/odb

echo "==> build Swift ble-battery provider"
( cd providers/ble-battery && swift build -c release )

echo "==> assemble bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$RES/providers/ble-battery" "$RES/providers/host-info"
cp build/odb "$APP/Contents/MacOS/odb"
cp packaging/Info.plist "$APP/Contents/Info.plist"

cp providers/ble-battery/.build/release/ble-battery "$RES/providers/ble-battery/ble-battery"
cp providers/ble-battery/provider.json "$RES/providers/ble-battery/provider.json"

cp providers/host-info/host_info.py "$RES/providers/host-info/host_info.py"
cp providers/host-info/provider.json "$RES/providers/host-info/provider.json"

echo "==> ad-hoc codesign"
codesign --force --deep --sign - --options runtime \
  --identifier online.99lab.opendevicesbridge "$APP"
echo "==> done: $APP"
