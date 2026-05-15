#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="AIMacCleaner"
VERSION="1.7.2"
BUILD_DIR="/tmp/AIMacCleaner_build"
DMG_NAME="AIMacCleaner-v${VERSION}-arm64"
STAGING_DIR="/tmp/AIMacCleaner_dmg_staging"

echo "========================================="
echo "  Building $APP_NAME v${VERSION}"
echo "========================================="

rm -rf "$BUILD_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$BUILD_DIR"

echo "[1/5] Compiling Swift files..."

SWIFT_FILES=(
    "AIMacCleanerApp.swift"
    "ContentView.swift"
    "Models.swift"
    "ScannerService.swift"
    "StorageAnalyzer.swift"
    "SettingsView.swift"
    "AIConfigView.swift"
    "Localizer.swift"
    "MenuBarMonitor.swift"
    "OperationMonitor.swift"
    "SensorMonitor.swift"
    "ScanRules.swift"
)

cd "$PROJECT_DIR/AIMacCleaner"

swiftc -O \
    -target arm64-apple-macos13.0 \
    -sdk $(xcrun --show-sdk-path) \
    -parse-as-library \
    -framework SwiftUI \
    -framework AppKit \
    -framework Foundation \
    -framework CoreServices \
    -framework DiskArbitration \
    -framework IOKit \
    -o "$BUILD_DIR/$APP_NAME" \
    "${SWIFT_FILES[@]}" \
    2>&1 | grep -E "error:" || true

if [ ! -f "$BUILD_DIR/$APP_NAME" ]; then
    echo "Error: Compilation failed"
    exit 1
fi

echo "  Compilation successful"

echo "[2/5] Creating app bundle..."

APP_PATH="$BUILD_DIR/$APP_NAME.app"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_PATH/Contents/MacOS/"
cp Info.plist "$APP_PATH/Contents/Info.plist"

if [ -d Assets.xcassets ]; then
    echo "  Processing app icon..."
    
    ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"
    
    if [ -f "Assets.xcassets/AppIcon.appiconset/icon_16.png" ]; then
        cp "Assets.xcassets/AppIcon.appiconset/icon_16.png" "$ICONSET_DIR/icon_16x16.png"
        cp "Assets.xcassets/AppIcon.appiconset/icon_16_2x.png" "$ICONSET_DIR/icon_16x16@2x.png"
        cp "Assets.xcassets/AppIcon.appiconset/icon_32.png" "$ICONSET_DIR/icon_32x32.png"
        cp "Assets.xcassets/AppIcon.appiconset/icon_32_2x.png" "$ICONSET_DIR/icon_32x32@2x.png"
        cp "Assets.xcassets/AppIcon.appiconset/icon_128.png" "$ICONSET_DIR/icon_128x128.png"
        cp "Assets.xcassets/AppIcon.appiconset/icon_128_2x.png" "$ICONSET_DIR/icon_128x128@2x.png"
        cp "Assets.xcassets/AppIcon.appiconset/icon_256.png" "$ICONSET_DIR/icon_256x256.png"
        cp "Assets.xcassets/AppIcon.appiconset/icon_256_2x.png" "$ICONSET_DIR/icon_256x256@2x.png"
        cp "Assets.xcassets/AppIcon.appiconset/icon_512.png" "$ICONSET_DIR/icon_512x512.png"
        cp "Assets.xcassets/AppIcon.appiconset/icon_512_2x.png" "$ICONSET_DIR/icon_512x512@2x.png"
        
        echo "  Creating ICNS file..."
        iconutil -c icns "$ICONSET_DIR" -o "$APP_PATH/Contents/Resources/AppIcon.icns" 2>&1 && \
            echo "  ✅ AppIcon.icns created successfully" || \
            echo "  ⚠️ ICNS creation failed, using fallback"
        
        rm -rf "$ICONSET_DIR"
    fi
    
    echo "  Copying Assets.xcassets for compatibility..."
    cp -R Assets.xcassets "$APP_PATH/Contents/Resources/"
fi

echo "[3/5] Code signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_PATH" 2>/dev/null || echo "  Code signing skipped (ad-hoc)"
echo "  Code signed successfully."

echo "[4/5] Verifying build..."
BUILT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "unknown")
echo "  Built version: $BUILT_VERSION"

if [ "$BUILT_VERSION" != "$VERSION" ]; then
    echo "  Version mismatch! Fixing to $VERSION..."
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist"
fi

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
    "/tmp/${DMG_NAME}.dmg" \
    2>&1 | tail -1

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

echo "=== Verification ==="
if [ -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]; then
    echo "✅ AppIcon.icns present"
else
    echo "⚠️ No AppIcon.icns (will use default icon)"
fi
