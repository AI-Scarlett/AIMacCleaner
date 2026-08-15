#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="TraceFence"
VERSION="${TRACEFENCE_VERSION:-1.2.6}"
BUILD_NUMBER="${TRACEFENCE_BUILD_NUMBER:-127}"
TAG="v${VERSION}"
SCHEME="AIMacCleaner"
CONFIGURATION="Release"
BUILD_ROOT="${TRACEFENCE_BUILD_ROOT:-$PROJECT_DIR/build/.TraceFence-release-build}"
STAGING_DIR="${TRACEFENCE_STAGING_DIR:-$PROJECT_DIR/build/.TraceFence-dmg-staging}"

python3 "$PROJECT_DIR/scripts/verify_scan_rules.py"
OUTPUT_DIR="${TRACEFENCE_OUTPUT_DIR:-$PROJECT_DIR/build/${APP_NAME}-${VERSION}}"
OUTPUT_APP="$OUTPUT_DIR/${APP_NAME}.app"
OUTPUT_DMG="$OUTPUT_DIR/${APP_NAME}-${TAG}-arm64.dmg"
OUTPUT_ZIP="$OUTPUT_DIR/${APP_NAME}-${TAG}-arm64.zip"
SWIFT_COMPILATION_MODE="${TRACEFENCE_SWIFT_COMPILATION_MODE:-singlefile}"
SIGN_IDENTITY="${TRACEFENCE_SIGN_IDENTITY:-Developer ID Application: xiaoming zhou (UQ87N2WZ76)}"
ENTITLEMENTS="$PROJECT_DIR/AIMacCleaner/AIMacCleaner.entitlements"
DEFAULT_NOTARY_KEY="$HOME/.appstoreconnect/private_keys/AuthKey_JHKYSFS5HM.p8"
if [ ! -f "$DEFAULT_NOTARY_KEY" ]; then
  DEFAULT_NOTARY_KEY=""
fi
NOTARY_PROFILE="${TRACEFENCE_NOTARY_PROFILE:-}"
NOTARY_KEY="${TRACEFENCE_NOTARY_KEY:-$DEFAULT_NOTARY_KEY}"
NOTARY_KEY_ID="${TRACEFENCE_NOTARY_KEY_ID:-JHKYSFS5HM}"
NOTARY_ISSUER="${TRACEFENCE_NOTARY_ISSUER:-69a6de85-f729-47e3-e053-5b8c7c11a4d1}"
NOTARIZE="${TRACEFENCE_NOTARIZE:-1}"
NOTARYTOOL_ARGS=()
if [ "${NOTARYTOOL_S3_ACCELERATION:-0}" != "1" ]; then
  NOTARYTOOL_ARGS+=(--no-s3-acceleration)
fi
CODEXBAR_DIR="${CODEXBAR_DIR:-}"
CODEXBAR_BINARY="${CODEXBAR_BINARY:-$PROJECT_DIR/AIMacCleaner/Resources/codexbar}"

notarytool_submit() {
  local artifact="$1"
  local auth_args=()
  if [ -n "$NOTARY_PROFILE" ]; then
    auth_args+=(--keychain-profile "$NOTARY_PROFILE")
  elif [ -n "$NOTARY_KEY" ] && [ -n "$NOTARY_KEY_ID" ]; then
    auth_args+=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID")
    if [ -n "$NOTARY_ISSUER" ]; then
      auth_args+=(--issuer "$NOTARY_ISSUER")
    fi
  else
    echo "Set TRACEFENCE_NOTARY_PROFILE or TRACEFENCE_NOTARY_KEY/TRACEFENCE_NOTARY_KEY_ID when TRACEFENCE_NOTARIZE=1" >&2
    exit 1
  fi

  if [ "${#NOTARYTOOL_ARGS[@]}" -gt 0 ]; then
    if xcrun notarytool submit "$artifact" "${auth_args[@]}" "${NOTARYTOOL_ARGS[@]}" --wait; then
      return 0
    fi
    echo "Notary upload failed without S3 acceleration; retrying with acceleration enabled..." >&2
  fi
  xcrun notarytool submit "$artifact" "${auth_args[@]}" --wait
}

codesign_with_retry() {
  local attempt
  for attempt in 1 2 3; do
    if codesign "$@"; then
      return 0
    fi
    if [ "$attempt" -lt 3 ]; then
      echo "codesign failed (attempt $attempt); retrying secure timestamp..." >&2
      sleep 2
    fi
  done
  return 1
}

echo "========================================="
echo "  Building ${APP_NAME} ${TAG}"
echo "========================================="

QR_MODULE_CACHE="$PROJECT_DIR/build/.tracefence-qr-module-cache"
mkdir -p "$QR_MODULE_CACHE"
CLANG_MODULE_CACHE_PATH="$QR_MODULE_CACHE" \
  SWIFT_MODULE_CACHE_PATH="$QR_MODULE_CACHE" \
  xcrun swift "$PROJECT_DIR/scripts/verify_tracefence_pairing_qr.swift"

rm -rf "$BUILD_ROOT" "$STAGING_DIR" "$OUTPUT_DIR"
mkdir -p "$BUILD_ROOT" "$STAGING_DIR" "$OUTPUT_DIR"

if [ ! -x "$CODEXBAR_BINARY" ]; then
  if [ -z "$CODEXBAR_DIR" ] || [ ! -d "$CODEXBAR_DIR" ]; then
    echo "Bundled CodexBar provider engine not found: $CODEXBAR_BINARY" >&2
    echo "Set CODEXBAR_BINARY to a built CodexBarCLI only for local recovery builds." >&2
    exit 1
  fi
  echo "Building CodexBar provider engine..."
  (cd "$CODEXBAR_DIR" && swift build -c release --product CodexBarCLI)
  CODEXBAR_BINARY="$CODEXBAR_DIR/.build/release/CodexBarCLI"
fi

xcodebuild \
  -project "$PROJECT_DIR/AIMacCleaner.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$BUILD_ROOT" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  ENABLE_DEBUG_DYLIB=NO \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  SWIFT_COMPILATION_MODE="$SWIFT_COMPILATION_MODE"

BUILT_APP="$BUILD_ROOT/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
if [ ! -d "$BUILT_APP" ]; then
  echo "Built app not found: $BUILT_APP" >&2
  exit 1
fi

BUILT_PLIST="$BUILT_APP/Contents/Info.plist"
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILT_PLIST")"
BUILT_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$BUILT_PLIST")"
BUILT_CHANNEL="$(/usr/libexec/PlistBuddy -c 'Print :TraceFenceDistributionChannel' "$BUILT_PLIST")"
BUILT_MUSIC_PURPOSE="$(/usr/libexec/PlistBuddy -c 'Print :NSAppleMusicUsageDescription' "$BUILT_PLIST" 2>/dev/null || true)"
[ "$BUILT_VERSION" = "$VERSION" ] || { echo "Wrong built marketing version: $BUILT_VERSION" >&2; exit 1; }
[ "$BUILT_NUMBER" = "$BUILD_NUMBER" ] || { echo "Wrong built build number: $BUILT_NUMBER" >&2; exit 1; }
[ "$BUILT_CHANNEL" = "direct" ] || { echo "Wrong built distribution channel: $BUILT_CHANNEL" >&2; exit 1; }
[ -n "$BUILT_MUSIC_PURPOSE" ] || { echo "Missing Apple Music purpose string" >&2; exit 1; }

PROVIDER_ENGINE="$BUILT_APP/Contents/MacOS/codexbar"
if [ ! -x "$PROVIDER_ENGINE" ]; then
  install -m 755 "$CODEXBAR_BINARY" "$PROVIDER_ENGINE"
fi

PLUGIN_FRAMEWORK="$BUILT_APP/Contents/Frameworks/MacToolsPluginKit.framework"
if [ ! -d "$PLUGIN_FRAMEWORK" ]; then
  echo "Bundled PluginKit compatibility framework not found: $PLUGIN_FRAMEWORK" >&2
  exit 1
fi

PLUGIN_FRAMEWORK_PLIST="$PLUGIN_FRAMEWORK/Versions/A/Resources/Info.plist"
PLUGIN_FRAMEWORK_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLUGIN_FRAMEWORK_PLIST")"
if [ "$PLUGIN_FRAMEWORK_IDENTIFIER" != "com.tracefence.plugin-kit" ]; then
  echo "Bundled PluginKit framework has invalid bundle identifier: $PLUGIN_FRAMEWORK_IDENTIFIER" >&2
  exit 1
fi

codesign_with_retry --force \
  --options runtime \
  --timestamp \
  --sign "$SIGN_IDENTITY" \
  "$PLUGIN_FRAMEWORK"

codesign_with_retry --force \
  --options runtime \
  --timestamp \
  --sign "$SIGN_IDENTITY" \
  "$PROVIDER_ENGINE"

codesign_with_retry --force \
  --options runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGN_IDENTITY" \
  "$BUILT_APP"
codesign --verify --deep --strict --verbose=2 "$BUILT_APP"

# The iOS Remote Pairing listener belongs to the main app only. Signing the
# outer bundle with --deep would re-sign codexbar using the main app's
# entitlements and incorrectly grant the helper network.server. Keep nested
# code explicitly signed above, then sign only the outer bundle here.
MAIN_ENTITLEMENTS_OUTPUT="$(codesign -d --entitlements - "$BUILT_APP" 2>&1 || true)"
HELPER_ENTITLEMENTS_OUTPUT="$(codesign -d --entitlements - "$PROVIDER_ENGINE" 2>&1 || true)"
[[ "$MAIN_ENTITLEMENTS_OUTPUT" == *"com.apple.security.network.server"* ]] || {
  echo "Main TraceFence app is missing com.apple.security.network.server" >&2
  exit 1
}
[[ "$HELPER_ENTITLEMENTS_OUTPUT" != *"com.apple.security.network.server"* ]] || {
  echo "Bundled codexbar helper must not receive com.apple.security.network.server" >&2
  exit 1
}

if [ "$NOTARIZE" = "1" ]; then
  ditto -c -k --norsrc --keepParent "$BUILT_APP" "$OUTPUT_ZIP"
  if unzip -Z1 "$OUTPUT_ZIP" | grep -Eq '(^|/)\._'; then
    echo "Release ZIP contains AppleDouble metadata" >&2
    exit 1
  fi
  notarytool_submit "$OUTPUT_ZIP"
  xcrun stapler staple "$BUILT_APP"
  spctl --assess --type execute --verbose=2 "$BUILT_APP"
fi

ditto "$BUILT_APP" "$OUTPUT_APP"
codesign --verify --deep --strict --verbose=2 "$OUTPUT_APP"

ditto "$OUTPUT_APP" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_DMG"

codesign_with_retry --force \
  --timestamp \
  --sign "$SIGN_IDENTITY" \
  "$OUTPUT_DMG"
codesign --verify --verbose=2 "$OUTPUT_DMG"

if [ "$NOTARIZE" = "1" ]; then
  notarytool_submit "$OUTPUT_DMG"
  xcrun stapler staple "$OUTPUT_DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$OUTPUT_DMG"
fi

shasum -a 256 "$OUTPUT_DMG" > "${OUTPUT_DMG}.sha256"

echo ""
echo "========================================="
echo "  Build Complete"
echo "========================================="
echo "  App:  $OUTPUT_APP"
echo "  DMG:  $OUTPUT_DMG"
echo "  SHA:  ${OUTPUT_DMG}.sha256"
