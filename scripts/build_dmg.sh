#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DERIVED_DATA="$ROOT_DIR/DerivedDataLocal"
RELEASE_DIR="$ROOT_DIR/release"
APP_PATH="$BUILD_DIR/Release/MacCleaner.app"
DMG_STAGING="$BUILD_DIR/dmg_content"
DMG_PATH="$RELEASE_DIR/MacCleaner.dmg"
SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"

if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "Set DEVELOPER_ID_APPLICATION to a Developer ID Application identity." >&2
  exit 2
fi

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Set NOTARY_KEYCHAIN_PROFILE to an xcrun notarytool keychain profile." >&2
  exit 2
fi

cd "$ROOT_DIR"

echo "Building MacCleaner in Release mode..."
rm -rf "$BUILD_DIR" "$DERIVED_DATA" "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

xcodebuild \
  -project MacCleaner.xcodeproj \
  -scheme MacCleaner \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR/Release" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

echo "Signing app with hardened runtime and secure timestamp..."
codesign --force --options runtime --timestamp --entitlements "$ROOT_DIR/MacCleaner/MacCleaner.entitlements" --sign "$SIGN_IDENTITY" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

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

echo "Signing and notarizing DMG..."
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"

echo "Cleaning temporary packaging files..."
rm -rf "$BUILD_DIR" "$DERIVED_DATA"

echo "Done: $DMG_PATH"
