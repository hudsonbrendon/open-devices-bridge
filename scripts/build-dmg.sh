#!/usr/bin/env bash
# Builds the .app then packages an unsigned .dmg via hdiutil (no extra deps).
set -euo pipefail
cd "$(dirname "$0")/.."

bash scripts/build-app.sh

APP="build/HA Battery Bridge.app"
DMG="build/HA-Battery-Bridge.dmg"
STAGE="build/dmg-stage"

echo "==> staging dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> hdiutil create"
hdiutil create -volname "HA Battery Bridge" -srcfolder "$STAGE" \
  -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "==> done: $DMG"
echo "Nota: .dmg NÃO assinado. Em outro Mac: clique-direito no app > Abrir,"
echo "ou rode: xattr -dr com.apple.quarantine '/Applications/HA Battery Bridge.app'"
