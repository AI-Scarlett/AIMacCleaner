#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="TraceFence"
VERSION="${TRACEFENCE_VERSION:-1.0.52}"
TAG="v${VERSION}"
SCHEME="AIMacCleaner"
CONFIGURATION="Release"
BUILD_ROOT="/tmp/TraceFence-release-build"
STAGING_DIR="/tmp/TraceFence-dmg-staging"
OUTPUT_DMG="/tmp/${APP_NAME}-${TAG}-arm64.dmg"
OUTPUT_ZIP="/tmp/${APP_NAME}-${TAG}-arm64.zip"
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
CODEXBAR_DIR="${CODEXBAR_DIR:-}"
CODEXBAR_BINARY="${CODEXBAR_BINARY:-$PROJECT_DIR/AIMacCleaner/Resources/codexbar}"

notarytool_submit() {
  local artifact="$1"
  if [ -n "$NOTARY_PROFILE" ]; then
    xcrun notarytool submit "$artifact" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait
  elif [ -n "$NOTARY_KEY" ] && [ -n "$NOTARY_KEY_ID" ]; then
    if [ -n "$NOTARY_ISSUER" ]; then
      xcrun notarytool submit "$artifact" \
        --key "$NOTARY_KEY" \
        --key-id "$NOTARY_KEY_ID" \
        --issuer "$NOTARY_ISSUER" \
        --wait
    else
      xcrun notarytool submit "$artifact" \
        --key "$NOTARY_KEY" \
        --key-id "$NOTARY_KEY_ID" \
        --wait
    fi
  else
    echo "Set TRACEFENCE_NOTARY_PROFILE or TRACEFENCE_NOTARY_KEY/TRACEFENCE_NOTARY_KEY_ID when TRACEFENCE_NOTARIZE=1" >&2
    exit 1
  fi
}

echo "========================================="
echo "  Building ${APP_NAME} ${TAG}"
echo "========================================="

rm -rf "$BUILD_ROOT" "$STAGING_DIR" "$OUTPUT_DMG" "$OUTPUT_ZIP"
mkdir -p "$BUILD_ROOT" "$STAGING_DIR"

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
  CODE_SIGNING_ALLOWED=NO

BUILT_APP="$BUILD_ROOT/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
if [ ! -d "$BUILT_APP" ]; then
  echo "Built app not found: $BUILT_APP" >&2
  exit 1
fi

mkdir -p "$BUILT_APP/Contents/Resources"
cp "$CODEXBAR_BINARY" "$BUILT_APP/Contents/Resources/codexbar"
chmod 755 "$BUILT_APP/Contents/Resources/codexbar"

codesign --force \
  --options runtime \
  --timestamp \
  --sign "$SIGN_IDENTITY" \
  "$BUILT_APP/Contents/Resources/codexbar"

codesign --force \
  --deep \
  --options runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGN_IDENTITY" \
  "$BUILT_APP"
codesign --verify --deep --strict --verbose=2 "$BUILT_APP"

if [ "$NOTARIZE" = "1" ]; then
  ditto -c -k --keepParent "$BUILT_APP" "$OUTPUT_ZIP"
  notarytool_submit "$OUTPUT_ZIP"
  xcrun stapler staple "$BUILT_APP"
  spctl --assess --type execute --verbose=2 "$BUILT_APP"
fi

cp -R "$BUILT_APP" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_DMG"

codesign --force \
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
echo "  App:  $BUILT_APP"
echo "  DMG:  $OUTPUT_DMG"
echo "  SHA:  ${OUTPUT_DMG}.sha256"
