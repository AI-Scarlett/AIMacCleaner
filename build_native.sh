#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="AIMacCleaner"
VERSION="1.6.3"
BUILD_DIR="/tmp/AIMacCleaner_build"
DMG_NAME="AIMacCleaner-v${VERSION}-arm64"
STAGING_DIR="/tmp/AIMacCleaner_dmg_staging"

echo "========================================="
echo "  Building $APP_NAME v${VERSION}"
echo "========================================="

rm -rf "$BUILD_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$BUILD_DIR"

echo "[1/5] Building with xcodebuild..."
xcodebuild \
    -project "$PROJECT_DIR/AIMacCleaner.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -arch arm64 \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    MARKETING_VERSION="$VERSION" \
    CFBundleShortVersionString="$VERSION" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    ENABLE_HARDENED_RUNTIME=NO \
    clean build \
    2>&1 | tail -5

APP_PATH="$BUILD_DIR/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: Build failed - $APP_PATH not found"
    exit 1
fi

echo "  Build successful: $APP_PATH"

BUILT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "unknown")
echo "  Built version: $BUILT_VERSION"

echo "[2/5] Verifying Info.plist version..."
if [ "$BUILT_VERSION" != "$VERSION" ]; then
    echo "  Version mismatch! Fixing to $VERSION..."
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist"
fi

echo "[3/5] Code signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_PATH"
echo "  Code signed successfully."

echo "[4/5] Verifying signature..."
codesign --verify --deep --strict "$APP_PATH" 2>&1 && echo "  Signature valid ✓" || echo "  WARNING: Signature verification failed!"

echo "[5/5] Creating DMG..."
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "/tmp/${DMG_NAME}.dmg"

rm -rf "$STAGING_DIR"

DMG_PATH="/tmp/${DMG_NAME}.dmg"
DMG_SIZE=$(du -sh "$DMG_PATH" | cut -f1)

echo ""
echo "========================================="
echo "  Build Complete!"
echo "========================================="
echo ""
echo "  App:  $APP_PATH"
echo "  DMG:  $DMG_PATH"
echo "  Size: $DMG_SIZE"
echo "  Version: $VERSION"
echo ""
