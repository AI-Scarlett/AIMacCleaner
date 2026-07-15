#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_NUMBER="${1:-22}"
VERSION="1.0.0"
ARCHIVE_PATH="build/TraceFenceSentinel-iOS-${VERSION}-${BUILD_NUMBER}.xcarchive"
EXPORT_PATH="build/TraceFenceSentinel-iOS-${VERSION}-${BUILD_NUMBER}-AppStore"
DERIVED_DATA_PATH="build/.TraceFenceIOS-archive-build-${BUILD_NUMBER}"
EXPORT_OPTIONS="AppStoreExportOptions.plist"
ASC_KEY_ID="JHKYSFS5HM"
ASC_ISSUER_ID="69a6de85-f729-47e3-e053-5b8c7c11a4d1"
ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"

fail() {
  printf 'release_tracefence_sentinel_appstore: %s\n' "$*" >&2
  exit 1
}

[[ -f "$ASC_KEY_PATH" ]] || fail "missing App Store Connect API key"
QR_MODULE_CACHE="$ROOT/build/.tracefence-qr-module-cache"
mkdir -p "$QR_MODULE_CACHE"
CLANG_MODULE_CACHE_PATH="$QR_MODULE_CACHE" \
  SWIFT_MODULE_CACHE_PATH="$QR_MODULE_CACHE" \
  xcrun swift scripts/verify_tracefence_pairing_qr.swift
[[ ! -e "$ARCHIVE_PATH" ]] || fail "archive already exists: $ARCHIVE_PATH"
[[ ! -e "$EXPORT_PATH" ]] || fail "export already exists: $EXPORT_PATH"

xcodebuild archive \
  -project TraceFenceIOS/TraceFenceIOS.xcodeproj \
  -scheme TraceFenceIOS \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
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

IPA_PATH="$EXPORT_PATH/TraceFence Sentinel.ipa"
[[ -f "$IPA_PATH" ]] || fail "missing exported IPA: $IPA_PATH"
VERIFY_DIR="$(mktemp -d /tmp/tracefence-sentinel-ipa.XXXXXX)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
unzip -q "$IPA_PATH" -d "$VERIFY_DIR"
APP_PLIST="$VERIFY_DIR/Payload/TraceFence Sentinel.app/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :BuildMachineOSBuild' "$APP_PLIST")" == "25F70" ]] || fail "exported IPA contains unsupported host metadata"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PLIST")" == "$VERSION" ]] || fail "exported IPA has the wrong marketing version"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PLIST")" == "$BUILD_NUMBER" ]] || fail "exported IPA has the wrong build number"
printf 'Verified IPA build %s with BuildMachineOSBuild=25F70\n' "$BUILD_NUMBER"

xcrun altool --validate-app --type ios -f "$IPA_PATH" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
xcrun altool --upload-app --wait --type ios -f "$IPA_PATH" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

if [[ "${TRACEFENCE_REPLACE_SENTINEL_REVIEW_BUILD:-0}" == "1" ]]; then
  CONFIRMATION="REPLACE_IOS_${VERSION}_BUILD_${TRACEFENCE_SENTINEL_OLD_BUILD:-21}_WITH_${BUILD_NUMBER}"
  TRACEFENCE_SENTINEL_BUILD="$BUILD_NUMBER" \
    python3 scripts/appstoreconnect/replace_tracefence_sentinel_review_build.py \
      --execute \
      --confirm "$CONFIRMATION" \
      --wait-for-build 1200
  printf 'TraceFence Sentinel %s build %s uploaded, added to public TestFlight, and submitted for App Review.\n' "$VERSION" "$BUILD_NUMBER"
elif [[ "${TRACEFENCE_SYNC_SENTINEL_SUBMISSION:-0}" == "1" ]]; then
  TRACEFENCE_SENTINEL_BUILD="$BUILD_NUMBER" python3 scripts/appstoreconnect/sync_tracefence_sentinel_submission.py --skip-screenshots
  printf 'TraceFence Sentinel %s build %s uploaded and synchronized.\n' "$VERSION" "$BUILD_NUMBER"
else
  printf 'TraceFence Sentinel %s build %s uploaded. Submission synchronization was intentionally deferred.\n' "$VERSION" "$BUILD_NUMBER"
fi
