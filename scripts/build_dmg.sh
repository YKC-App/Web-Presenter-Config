#!/usr/bin/env bash
# Build NDIMonitor as a Mac Catalyst app and package it as a signed DMG.
#
# Prerequisites:
#   brew install create-dmg xcodegen
#   Xcode 15+ with a valid Apple Developer certificate
#   NDI SDK for Apple installed (run scripts/setup_ndi.sh first)
#
# Usage:
#   ./scripts/build_dmg.sh [--skip-sign]
#
# Outputs:
#   dist/mac/NDIMonitor-<version>.dmg

set -euo pipefail

APP_NAME="NDIMonitor"
SCHEME="NDIMonitor"
BUNDLE_ID="com.webpresenter.ndimonitor"
VERSION=$(grep 'MARKETING_VERSION' project.yml | head -1 | awk '{print $2}' | tr -d '"')
BUILD_DIR="$(pwd)/build/mac"
ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DIST_DIR="$(pwd)/dist/mac"
SKIP_SIGN=false

for arg in "$@"; do
  [[ "$arg" == "--skip-sign" ]] && SKIP_SIGN=true
done

echo "=== NDIMonitor Mac Build v$VERSION ==="

# ---- 1. Regenerate Xcode project ----
echo "-> Generating Xcode project..."
xcodegen generate

# ---- 2. Archive (Mac Catalyst) ----
echo "-> Archiving for Mac Catalyst..."
mkdir -p "$BUILD_DIR"
xcodebuild archive \
  -scheme "$SCHEME" \
  -destination "platform=macOS,variant=Mac Catalyst" \
  -archivePath "$ARCHIVE" \
  -configuration Release \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=NO

# ---- 3. Export app ----
echo "-> Exporting app..."
mkdir -p "$EXPORT_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist scripts/ExportOptions.plist 2>/dev/null \
  || cp -R "$ARCHIVE/Products/Applications/$APP_NAME.app" "$EXPORT_DIR/"

APP_PATH="$EXPORT_DIR/$APP_NAME.app"

# ---- 4. Optional code signing ----
if [[ "$SKIP_SIGN" == false ]] && [[ -n "${DEVELOPER_ID_APP:-}" ]]; then
  echo "-> Signing with $DEVELOPER_ID_APP..."
  codesign --deep --force --options runtime \
    --entitlements "NDIMonitor/Resources/NDIMonitor.entitlements" \
    --sign "$DEVELOPER_ID_APP" "$APP_PATH"
else
  echo "-> Skipping code signing (pass DEVELOPER_ID_APP env var to sign)"
fi

# ---- 5. Create DMG ----
echo "-> Creating DMG..."
mkdir -p "$DIST_DIR"
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"

if command -v create-dmg &>/dev/null; then
  create-dmg \
    --volname "$APP_NAME $VERSION" \
    --volicon "icons/app_icon.svg" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 128 \
    --icon "$APP_NAME.app" 180 170 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 480 170 \
    "$DMG" \
    "$EXPORT_DIR"
else
  hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$EXPORT_DIR" \
    -ov -format UDZO \
    "$DMG"
fi

echo ""
echo "✓ DMG ready: $DMG"
