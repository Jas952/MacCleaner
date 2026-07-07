#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DERIVED_DATA="$ROOT_DIR/DerivedDataLocal"
RELEASE_DIR="$ROOT_DIR/release"
APP_PATH="$BUILD_DIR/Release/MacCleaner.app"
DMG_STAGING="$BUILD_DIR/dmg_content"
DMG_PATH="$RELEASE_DIR/MacCleaner.dmg"

cd "$ROOT_DIR"

echo "Building MacCleaner in Release mode..."
rm -rf "$BUILD_DIR" "$DERIVED_DATA" "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

xcodebuild \
  -project MacCleaner.xcodeproj \
  -scheme MacCleaner \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR/Release" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

echo "Applying ad-hoc signature for local installation..."
codesign --force --deep --sign - "$APP_PATH"

echo "Preparing DMG content..."
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

echo "Creating DMG..."
hdiutil create \
  -volname "MacCleaner" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Cleaning temporary packaging files..."
rm -rf "$BUILD_DIR" "$DERIVED_DATA"

echo "Done: $DMG_PATH"
