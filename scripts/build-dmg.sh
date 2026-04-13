#!/usr/bin/env bash
set -euo pipefail

SCHEME="InstantSwitcher"
CONFIG="Release"
DERIVED="build"
DMG_DIR="build/dmg"
DMG_PATH="build/InstantSwitcher.dmg"

rm -rf "$DERIVED" "$DMG_DIR" "$DMG_PATH"
mkdir -p "$DMG_DIR"

if ! command -v xcodegen >/dev/null; then
    echo "xcodegen not installed. brew install xcodegen" >&2
    exit 1
fi

xcodegen generate
xcodebuild -scheme "$SCHEME" -configuration "$CONFIG" -derivedDataPath "$DERIVED" build

APP_PATH="$DERIVED/Build/Products/$CONFIG/$SCHEME.app"
cp -R "$APP_PATH" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

hdiutil create -volname "InstantSwitcher" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG_PATH"

echo "Built: $DMG_PATH"
