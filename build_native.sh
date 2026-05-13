#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="AIMacCleaner"
BUILD_DIR="/tmp/AIMacCleaner_build"
APP_BUNDLE="$BUILD_DIR/build/$APP_NAME.app"
SWIFT_SOURCES="$PROJECT_DIR/AIMacCleaner"

echo "========================================="
echo "  Building $APP_NAME (Native SwiftUI)"
echo "========================================="

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/build"

SDK_PATH=$(xcrun --show-sdk-path 2>/dev/null)
if [ -z "$SDK_PATH" ]; then
    echo "Error: Xcode Command Line Tools not found."
    echo "Please install: xcode-select --install"
    exit 1
fi

echo "[1/6] Checking Xcode..."
XCODEBUILD=$(which xcodebuild 2>/dev/null || true)
if [ -z "$XCODEBUILD" ]; then
    echo "Error: xcodebuild not found. Please install Xcode from App Store."
    exit 1
fi
echo "  SDK: $SDK_PATH"

echo "[2/6] Preparing Swift sources..."
echo "  Using swiftc direct compilation..."

echo "[3/6] Compiling Swift sources..."
mkdir -p "$BUILD_DIR/objects"

SWIFT_FILES=$(find "$SWIFT_SOURCES" -name "*.swift" -type f)

xcrun swiftc \
    -o "$BUILD_DIR/AIMacCleaner" \
    -target arm64-apple-macosx13.0 \
    -sdk "$SDK_PATH" \
    -F "$SDK_PATH/System/Library/Frameworks" \
    -framework SwiftUI \
    -framework Foundation \
    -framework Combine \
    -framework CoreServices \
    -parse-as-library \
    -O \
    $SWIFT_FILES

echo "  Compilation successful."

echo "[4/6] Creating .app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Resources/static"
mkdir -p "$APP_BUNDLE/Contents/Resources/AIMacCleaner.bundle"

cp "$BUILD_DIR/AIMacCleaner" "$APP_BUNDLE/Contents/MacOS/AIMacCleaner"
chmod +x "$APP_BUNDLE/Contents/MacOS/AIMacCleaner"

echo "[5/6] Copying resources..."

cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>AIMacCleaner</string>
    <key>CFBundleIdentifier</key>
    <string>com.aimaccleaner.app</string>
    <key>CFBundleName</key>
    <string>AIMacCleaner</string>
    <key>CFBundleDisplayName</key>
    <string>AIMacCleaner</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

if [ -f "$PROJECT_DIR/build/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/build/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
fi

echo "[6/6] Copying Assets..."
if [ -d "$SWIFT_SOURCES/Assets.xcassets" ]; then
    cp -R "$SWIFT_SOURCES/Assets.xcassets" "$APP_BUNDLE/Contents/Resources/Assets.xcassets"
fi

echo ""
echo "========================================="
echo "  Build Complete!"
echo "========================================="
echo ""
echo "  App: $APP_BUNDLE"
echo "  Size: $(du -sh "$APP_BUNDLE" | cut -f1)"
echo ""
echo "  Install:"
echo "    cp -r \"$APP_BUNDLE\" /Applications/"
echo ""
echo "  Run:"
echo "    open \"$APP_BUNDLE\""
echo ""
