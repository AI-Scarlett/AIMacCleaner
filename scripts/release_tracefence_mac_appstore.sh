#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_NUMBER="${1:-74}"
VERSION="3.1.8"
ARCHIVE_PATH="build/TraceFence-AppStore-${VERSION}-${BUILD_NUMBER}.xcarchive"
EXPORT_PATH="build/TraceFence-AppStore-${VERSION}-${BUILD_NUMBER}"
DERIVED_DATA_PATH="build/.TraceFence-appstore-archive-${BUILD_NUMBER}"
EXPORT_OPTIONS="AppStoreExportOptions.plist"
ASC_KEY_ID="JHKYSFS5HM"
ASC_ISSUER_ID="69a6de85-f729-47e3-e053-5b8c7c11a4d1"
ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
PROVIDER_ENGINE_SOURCE="AIMacCleaner/Resources/codexbar"

fail() {
  printf 'release_tracefence_mac_appstore: %s\n' "$*" >&2
  exit 1
}

verify_engine_minos() {
  local binary="$1"
  local label="$2"
  local min_oses
  min_oses="$(xcrun vtool -show-build "$binary" | awk '/minos/{print $2}')"
  [[ "$(printf '%s\n' "$min_oses" | awk 'NF{count++} END{print count+0}')" == "2" ]] \
    && [[ -z "$(printf '%s\n' "$min_oses" | awk '$1 != "13.0"{print}')" ]] \
    || fail "$label slices must both target macOS 13.0, found: $min_oses"
}

[[ -f "$ASC_KEY_PATH" ]] || fail "missing App Store Connect API key"
[[ -x "$PROVIDER_ENGINE_SOURCE" ]] || fail "missing provider quota engine"
SOURCE_ENGINE_ARCHS="$(lipo -archs "$PROVIDER_ENGINE_SOURCE")"
[[ " $SOURCE_ENGINE_ARCHS " == *" arm64 "* && " $SOURCE_ENGINE_ARCHS " == *" x86_64 "* ]] \
  || fail "provider quota engine must contain arm64 and x86_64"
verify_engine_minos "$PROVIDER_ENGINE_SOURCE" "source provider quota engine"
QR_MODULE_CACHE="$ROOT/build/.tracefence-qr-module-cache"
mkdir -p "$QR_MODULE_CACHE"
CLANG_MODULE_CACHE_PATH="$QR_MODULE_CACHE" \
  SWIFT_MODULE_CACHE_PATH="$QR_MODULE_CACHE" \
  xcrun swift scripts/verify_tracefence_pairing_qr.swift
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
  TRACEFENCE_DODO_ENVIRONMENT= \
  TRACEFENCE_DODO_BUSINESS_ID= \
  TRACEFENCE_DODO_MONTHLY_PRODUCT_ID= \
  TRACEFENCE_DODO_ANNUAL_PRODUCT_ID= \
  TRACEFENCE_CHECKOUT_RETURN_URL= \
  TRACEFENCE_UPDATE_API_URL= \
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
APP_PATH="$(dirname "$(dirname "$APP_PLIST")")"
PROVIDER_ENGINE="$APP_PATH/Contents/MacOS/codexbar"
[[ -x "$PROVIDER_ENGINE" ]] || fail "exported package is missing its provider quota engine"
[[ ! -e "$APP_PATH/Contents/Resources/codexbar" ]] \
  || fail "provider quota engine is embedded in the Resources directory"
ENGINE_ARCHS="$(lipo -archs "$PROVIDER_ENGINE")"
[[ " $ENGINE_ARCHS " == *" arm64 "* && " $ENGINE_ARCHS " == *" x86_64 "* ]] \
  || fail "exported provider quota engine is not universal"
verify_engine_minos "$PROVIDER_ENGINE" "exported provider quota engine"
HELPER_ENTITLEMENTS="$VERIFY_DIR/provider-engine-entitlements.plist"
codesign -d --entitlements :- "$PROVIDER_ENGINE" >"$HELPER_ENTITLEMENTS" 2>/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$HELPER_ENTITLEMENTS")" == "true" ]] \
  || fail "provider quota engine is missing App Sandbox"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.inherit' "$HELPER_ENTITLEMENTS")" == "true" ]] \
  || fail "provider quota engine is missing sandbox inheritance"
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$HELPER_ENTITLEMENTS" >/dev/null 2>&1; then
  fail "provider quota engine contains get-task-allow"
fi
HELPER_SIGNATURE="$(codesign -dvv "$PROVIDER_ENGINE" 2>&1)"
[[ "$HELPER_SIGNATURE" == *"Identifier=com.aimaccleaner.app.codexbar"* ]] \
  || fail "provider quota engine has the wrong bundle identifier"
[[ "$HELPER_SIGNATURE" == *"TeamIdentifier=UQ87N2WZ76"* ]] \
  || fail "provider quota engine has the wrong signing team"
[[ "$HELPER_SIGNATURE" == *"runtime"* ]] \
  || fail "provider quota engine is missing hardened runtime"
[[ "$HELPER_SIGNATURE" != *"Signature=adhoc"* ]] \
  || fail "provider quota engine is ad-hoc signed"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :BuildMachineOSBuild' "$APP_PLIST")" == "25F70" ]] || fail "exported package contains unsupported host metadata"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PLIST")" == "$VERSION" ]] || fail "exported package has the wrong marketing version"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PLIST")" == "$BUILD_NUMBER" ]] || fail "exported package has the wrong build number"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :TraceFenceDistributionChannel' "$APP_PLIST")" == "appStore" ]] || fail "exported package has the wrong distribution channel"
MUSIC_PURPOSE="$(/usr/libexec/PlistBuddy -c 'Print :NSAppleMusicUsageDescription' "$APP_PLIST" 2>/dev/null || true)"
[[ -n "$MUSIC_PURPOSE" ]] || fail "exported package is missing NSAppleMusicUsageDescription"
for key in \
  TraceFenceDodoEnvironment \
  TraceFenceDodoBusinessID \
  TraceFenceDodoMonthlyProductID \
  TraceFenceDodoAnnualProductID \
  TraceFenceCheckoutReturnURL \
  TraceFenceUpdateAPIURL; do
  value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$APP_PLIST" 2>/dev/null || true)"
  [[ -z "$value" ]] || fail "exported package contains direct-only configuration: $key"
done
printf 'Verified macOS build %s with BuildMachineOSBuild=25F70\n' "$BUILD_NUMBER"

xcrun altool --validate-app --type macos -f "$PKG_PATH" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
xcrun altool --upload-app --wait --type macos -f "$PKG_PATH" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

if [[ "${TRACEFENCE_REPLACE_REVIEW_BUILD:-0}" == "1" ]]; then
  CONFIRMATION="REPLACE_MAC_${VERSION}_BUILD_${TRACEFENCE_MAC_OLD_BUILD:-73}_WITH_${BUILD_NUMBER}"
  TRACEFENCE_MAC_BUILD="$BUILD_NUMBER" \
    python3 scripts/appstoreconnect/replace_tracefence_mac_review_build.py \
      --execute \
      --confirm "$CONFIRMATION"
  printf 'TraceFence macOS %s build %s uploaded and submitted for review.\n' "$VERSION" "$BUILD_NUMBER"
else
  printf 'TraceFence macOS %s build %s uploaded. Review replacement was intentionally deferred.\n' "$VERSION" "$BUILD_NUMBER"
fi
