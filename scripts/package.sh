#!/bin/bash
set -euo pipefail

# Package Lowbeer.app into a DMG for distribution
# Usage: ./scripts/package.sh [--release|--debug]

CONFIG="${1:---release}"
case "$CONFIG" in
    --release) BUILD_CONFIG="Release" ;;
    --debug)   BUILD_CONFIG="Debug" ;;
    *)         echo "Usage: $0 [--release|--debug]"; exit 1 ;;
esac

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
APP_NAME="Lowbeer"
DMG_NAME="Lowbeer"

# Extract version from project.pbxproj
VERSION=$(grep -m1 'MARKETING_VERSION' "$PROJECT_ROOT/Lowbeer.xcodeproj/project.pbxproj" \
    | head -1 | sed 's/.*= *"\{0,1\}\([^";]*\)"\{0,1\};/\1/')
VERSION="${VERSION:-0.1.0}"

echo "==> Building $APP_NAME v$VERSION ($BUILD_CONFIG)"

# Clean and build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild \
    -project "$PROJECT_ROOT/Lowbeer.xcodeproj" \
    -scheme Lowbeer \
    -configuration "$BUILD_CONFIG" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR/app" \
    clean build 2>&1 | tail -5

APP_PATH="$BUILD_DIR/app/$APP_NAME.app"

if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: Build failed — $APP_PATH not found"
    exit 1
fi

echo "==> Build succeeded: $APP_PATH"

# Verify code signing
echo "==> Verifying code signature..."
codesign --verify --deep --strict "$APP_PATH" 2>&1 || true
codesign -dvv "$APP_PATH" 2>&1 | grep -E 'Authority|TeamIdentifier|Signature' || true

# Create DMG
DMG_STAGING="$BUILD_DIR/dmg-staging"
DMG_PATH="$BUILD_DIR/${DMG_NAME}-${VERSION}.dmg"

echo "==> Creating DMG..."
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# Copy app
cp -R "$APP_PATH" "$DMG_STAGING/"

# Create Applications symlink for drag-to-install
ln -s /Applications "$DMG_STAGING/Applications"

# Create DMG
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" 2>&1 | tail -3

rm -rf "$DMG_STAGING"

echo ""
echo "==> Done!"
echo "    App:     $APP_PATH"
echo "    DMG:     $DMG_PATH"
echo "    Version: $VERSION"
echo ""
echo "    To install: Open the DMG and drag Lowbeer to Applications."
echo "    First launch: Right-click → Open (ad-hoc signed, no Developer ID)."
