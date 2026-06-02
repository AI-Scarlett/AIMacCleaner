#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="AgentGuard"
VERSION="2.0.0"
BUILD_NUMBER="11"
BUILD_DIR="/tmp/AgentGuard_build"
DMG_NAME="AgentGuard-v${VERSION}-arm64"
STAGING_DIR="/tmp/AgentGuard_dmg_staging"
BUILD_MODE="${1:-dmg}"
SIGNING_IDENTITY="3rd Party Mac Developer Application"
PROVISIONING_PROFILE=""

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
    "Theme.swift"
    "MenuBarMonitor.swift"
    "OperationMonitor.swift"
    "AgentSessionScanner.swift"
    "IntelMigrationScanner.swift"
    "IntelMigrationTab.swift"
    "SensorMonitor.swift"
    "ScanRules.swift"
    "AgentGuardFeature.swift"
    "AgentGuardTab.swift"
    "SandboxPaths.swift"
    "Models/AgentEvent.swift"
    "Models/AgentSession.swift"
    "Models/AgentAdapterProtocol.swift"
    "Models/AgentProfile.swift"
    "Models/RemoteSession.swift"
    "Engine/HookServer.swift"
    "Engine/SessionStore.swift"
    "Engine/DisplayController.swift"
    "Engine/BridgeCLI.swift"
    "Adapters/HookInstaller.swift"
    "Adapters/AgentRegistry.swift"
    "Adapters/ClaudeCodeAdapter.swift"
    "Adapters/CodexGeminiCursorAdapter.swift"
    "Adapters/TraeQoderCodeBuddyAdapter.swift"
    "Adapters/RemainingAdapters.swift"
    "ViewModels/IslandViewModel.swift"
    "ViewModels/SessionsViewModel.swift"
    "Views/Island/IslandView.swift"
    "Views/Island/IslandWindow.swift"
    "Views/Island/PermissionSheet.swift"
    "Views/Island/QuestionSheet.swift"
    "Views/Island/PlanApprovalSheet.swift"
    "Views/Island/SessionDetailView.swift"
    "Views/Settings/SettingsViews.swift"
    "Views/AgentCenter/AgentCenterView.swift"
    "Services/SoundEngine.swift"
    "Services/WebhookNotifier.swift"
    "Services/RemoteManager.swift"
    "Services/GlobalShortcutService.swift"
    "Services/NetworkMonitor.swift"
    "Services/ConversationWatcher.swift"
    "TokenScopeLabView.swift"
)

cd "$PROJECT_DIR/AIMacCleaner"

swiftc -O \
    -target arm64-apple-macos13.0 \
    -sdk $(xcrun --show-sdk-path) \
    -parse-as-library \
    -framework SwiftUI \
    -framework AppKit \
    -framework Foundation \
    -framework Combine \
    -framework CoreServices \
    -framework DiskArbitration \
    -framework IOKit \
    -framework Network \
    -framework AVFoundation \
    -framework Carbon \
    -framework CoreVideo \
    -framework UserNotifications \
    -framework UniformTypeIdentifiers \
    -framework Charts \
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
cp "$PROJECT_DIR/AIMacCleaner/AIMacCleaner.entitlements" "$APP_PATH/Contents/"

if [ -f "$PROJECT_DIR/AIMacCleaner/PrivacyInfo.xcprivacy" ]; then
    cp "$PROJECT_DIR/AIMacCleaner/PrivacyInfo.xcprivacy" "$APP_PATH/Contents/Resources/"
    echo "  PrivacyInfo.xcprivacy copied"
fi

if [ -d Assets.xcassets ]; then
    echo "  Processing app icon..."
    
    ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"
    
    if [ -f "Assets.xcassets/AppIcon.appiconset/icon_16x16.png" ]; then
        cp "Assets.xcassets/AppIcon.appiconset/icon_16x16.png" "$ICONSET_DIR/icon_16x16.png"
        cp "Assets.xcassets/AppIcon.appiconset/icon_16x16@2x.png" "$ICONSET_DIR/icon_16x16@2x.png"
        cp "Assets.xcassets/AppIcon.appiconset/icon_32x32.png" "$ICONSET_DIR/icon_32x32.png"
        cp "Assets.xcassets/AppIcon.appiconset/icon_32x32@2x.png" "$ICONSET_DIR/icon_32x32@2x.png"
        cp "Assets.xcassets/AppIcon.appiconset/icon_128x128.png" "$ICONSET_DIR/icon_128x128.png"
        cp "Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" "$ICONSET_DIR/icon_128x128@2x.png"
        cp "Assets.xcassets/AppIcon.appiconset/icon_256x256.png" "$ICONSET_DIR/icon_256x256.png"
        cp "Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" "$ICONSET_DIR/icon_256x256@2x.png"
        cp "Assets.xcassets/AppIcon.appiconset/icon_512x512.png" "$ICONSET_DIR/icon_512x512.png"
        cp "Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" "$ICONSET_DIR/icon_512x512@2x.png"
        
        echo "  Creating ICNS file..."
        iconutil -c icns "$ICONSET_DIR" -o "$APP_PATH/Contents/Resources/AppIcon.icns" 2>&1 && \
            echo "  ✅ AppIcon.icns created successfully" || \
            echo "  ⚠️ ICNS creation failed, using fallback"
        
        rm -rf "$ICONSET_DIR"
    fi
    
    echo "  Copying Assets.xcassets for compatibility..."
    cp -R Assets.xcassets "$APP_PATH/Contents/Resources/"
fi

echo "[3/5] Updating version in Info.plist..."
if [ -f "$APP_PATH/Contents/Info.plist" ]; then
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
echo "  Version set to $VERSION"
fi

if [ -n "$PROVISIONING_PROFILE" ]; then
    echo "[4/5] Code signing (App Store)..."
    codesign --force --deep --sign "$SIGNING_IDENTITY" --entitlements "$PROJECT_DIR/AIMacCleaner/AIMacCleaner.entitlements" "$APP_PATH"
else
    echo "[4/5] Code signing (ad-hoc for testing)..."
    codesign --force --deep --sign - "$APP_PATH"
fi

echo "[5/5] Verifying build..."
codesign --verify --deep --strict "$APP_PATH" 2>&1 && echo "  Signature valid ✓" || echo "  WARNING: Signature verification failed!"

echo "[6/6] Creating DMG..."
if [ "$BUILD_MODE" = "dmg" ]; then
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "AgentGuard" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "/tmp/${DMG_NAME}.dmg" \
    2>&1 | tail -1

rm -rf "$STAGING_DIR"

DMG_PATH="/tmp/${DMG_NAME}.dmg"
DMG_SIZE=$(du -sh "$DMG_PATH" | cut -f1)
fi

echo ""
echo "========================================="
echo "  Build Complete!"
echo "========================================="
echo ""
echo "  App:  $APP_PATH"
if [ "$BUILD_MODE" = "dmg" ]; then
echo "  DMG:  $DMG_PATH"
echo "  Size: $DMG_SIZE"
fi
echo "  Version: $VERSION"
echo ""

echo "=== Verification ==="
if [ -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]; then
    echo "✅ AppIcon.icns present"
else
    echo "⚠️ No AppIcon.icns (will use default icon)"
fi

echo ""
echo "=== App Store Package ==="
echo "To create an App Store package, use Xcode Organizer or:"
echo "  productbuild --component \"$APP_PATH\" /Applications --sign \"3rd Party Mac Developer Installer\" /tmp/AgentGuard.pkg"
