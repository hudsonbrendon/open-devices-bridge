#!/usr/bin/env bash
# Builds the Swift providers and stages a clean providers tree (binaries +
# manifests) under src-tauri/providers/ for Tauri to bundle as Resources.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> build ble-battery"
( cd providers/ble-battery && swift build -c release )
echo "==> build camera-mac"
( cd providers/camera-mac && swift build -c release )

STAGE="src-tauri/providers"
rm -rf "$STAGE"
mkdir -p "$STAGE/ble-battery" "$STAGE/camera-mac" "$STAGE/host-info"
cp providers/ble-battery/.build/release/ble-battery "$STAGE/ble-battery/ble-battery"
cp providers/ble-battery/provider.json "$STAGE/ble-battery/provider.json"
cp providers/camera-mac/.build/release/camera-mac "$STAGE/camera-mac/camera-mac"
cp providers/camera-mac/provider.json "$STAGE/camera-mac/provider.json"
cp providers/host-info/host_info.py "$STAGE/host-info/host_info.py"
cp providers/host-info/provider.json "$STAGE/host-info/provider.json"
echo "==> staged providers in $STAGE"
