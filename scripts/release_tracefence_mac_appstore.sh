#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_NUMBER="${1:-68}"
VERSION="3.1.8"
ARCHIVE_PATH="build/TraceFence-AppStore-${VERSION}-${BUILD_NUMBER}.xcarchive"
EXPORT_PATH="build/TraceFence-AppStore-${VERSION}-${BUILD_NUMBER}"
DERIVED_DATA_PATH="build/.TraceFence-appstore-archive-${BUILD_NUMBER}"
EXPORT_OPTIONS="AppStoreExportOptions.plist"
ASC_KEY_ID="JHKYSFS5HM"
ASC_ISSUER_ID="69a6de85-f729-47e3-e053-5b8c7c11a4d1"
ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"

fail() {
  printf 'release_tracefence_mac_appstore: %s\n' "$*" >&2
  exit 1
}

[[ -f "$ASC_KEY_PATH" ]] || fail "missing App Store Connect API key"
[[ ! -e "$ARCHIVE_PATH" ]] || fail "archive already exists: $ARCHIVE_PATH"
[[ ! -e "$EXPORT_PATH" ]] || fail "export already exists: $EXPORT_PATH"

xcodebuild archive \
  -project AIMacCleaner.xcodeproj \
  -scheme AIMacCleaner \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  PRODUCT_BUNDLE_IDENTIFIER=com.aimaccleaner.app \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_ENTITLEMENTS=AIMacCleaner/AIMacCleanerAppStore.entitlements \
  TRACEFENCE_DISTRIBUTION_CHANNEL=appStore \
  -allowProvisioningUpdates

scripts/normalize_appstore_archive_metadata.sh "$ARCHIVE_PATH"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

PKG_PATH="$EXPORT_PATH/TraceFence.pkg"
[[ -f "$PKG_PATH" ]] || fail "missing exported package: $PKG_PATH"
VERIFY_DIR="$(mktemp -d /tmp/tracefence-mac-pkg.XXXXXX)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
pkgutil --expand-full "$PKG_PATH" "$VERIFY_DIR/expanded"
APP_PLIST="$VERIFY_DIR/expanded/TraceFence.pkg/Payload/TraceFence.app/Contents/Info.plist"
if [[ ! -f "$APP_PLIST" ]]; then
  APP_PLIST="$(find "$VERIFY_DIR/expanded" -path '*/TraceFence.app/Contents/Info.plist' -print -quit)"
fi
[[ -f "$APP_PLIST" ]] || fail "could not find exported app Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :BuildMachineOSBuild' "$APP_PLIST")" == "25F70" ]] || fail "exported package contains unsupported host metadata"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PLIST")" == "$BUILD_NUMBER" ]] || fail "exported package has the wrong build number"
printf 'Verified macOS build %s with BuildMachineOSBuild=25F70\n' "$BUILD_NUMBER"

xcrun altool --validate-app --type macos -f "$PKG_PATH" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
xcrun altool --upload-app --wait --type macos -f "$PKG_PATH" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

TRACEFENCE_MAC_BUILD="$BUILD_NUMBER" python3 scripts/appstoreconnect/sync_tracefence_mac_submission.py
printf 'TraceFence macOS %s build %s uploaded and synchronized.\n' "$VERSION" "$BUILD_NUMBER"
