#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_NUMBER="${1:-73}"
VERSION="3.1.8"
DERIVED_DATA_PATH="build/.TraceFence-appstore-debug-${BUILD_NUMBER}"

QR_MODULE_CACHE="$ROOT/build/.tracefence-qr-module-cache"
mkdir -p "$QR_MODULE_CACHE"
CLANG_MODULE_CACHE_PATH="$QR_MODULE_CACHE" \
  SWIFT_MODULE_CACHE_PATH="$QR_MODULE_CACHE" \
  xcrun swift scripts/verify_tracefence_pairing_qr.swift

xcodebuild build \
  -project AIMacCleaner.xcodeproj \
  -scheme AIMacCleaner \
  -configuration Debug \
  -destination 'platform=macOS' \
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

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/TraceFence.app"
APP_PLIST="$APP_PATH/Contents/Info.plist"
PROVIDER_ENGINE="$APP_PATH/Contents/MacOS/codexbar"
[[ -f "$APP_PLIST" ]] || { printf 'Missing built app: %s\n' "$APP_PATH" >&2; exit 1; }
[[ -x "$PROVIDER_ENGINE" ]] || { printf 'Missing embedded provider engine: %s\n' "$PROVIDER_ENGINE" >&2; exit 1; }
ENGINE_ARCHS="$(lipo -archs "$PROVIDER_ENGINE")"
[[ " $ENGINE_ARCHS " == *" arm64 "* && " $ENGINE_ARCHS " == *" x86_64 "* ]] || {
  printf 'Provider engine is not universal: %s\n' "$ENGINE_ARCHS" >&2
  exit 1
}
ENGINE_MIN_OSES="$(xcrun vtool -show-build "$PROVIDER_ENGINE" | awk '/minos/{print $2}')"
[[ "$(printf '%s\n' "$ENGINE_MIN_OSES" | awk 'NF{count++} END{print count+0}')" == "2" ]] \
  && [[ -z "$(printf '%s\n' "$ENGINE_MIN_OSES" | awk '$1 != "13.0"{print}')" ]] || {
  printf 'Provider engine slices must both target macOS 13.0; found: %s\n' "$ENGINE_MIN_OSES" >&2
  exit 1
}
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
MAIN_ENTITLEMENTS="$(mktemp /tmp/tracefence-main-entitlements.XXXXXX)"
HELPER_ENTITLEMENTS="$(mktemp /tmp/tracefence-helper-entitlements.XXXXXX)"
trap 'rm -f "$MAIN_ENTITLEMENTS" "$HELPER_ENTITLEMENTS"' EXIT
codesign -d --entitlements :- "$APP_PATH" >"$MAIN_ENTITLEMENTS" 2>/dev/null
codesign -d --entitlements :- "$PROVIDER_ENGINE" >"$HELPER_ENTITLEMENTS" 2>/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$MAIN_ENTITLEMENTS")" == "true" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$HELPER_ENTITLEMENTS")" == "true" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.inherit' "$HELPER_ENTITLEMENTS")" == "true" ]]
MAIN_TEAM="$(codesign -dvv "$APP_PATH" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
HELPER_TEAM="$(codesign -dvv "$PROVIDER_ENGINE" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
[[ -n "$MAIN_TEAM" && "$MAIN_TEAM" == "$HELPER_TEAM" ]] || {
  printf 'App and provider engine must share a signing team: app=%s helper=%s\n' "$MAIN_TEAM" "$HELPER_TEAM" >&2
  exit 1
}
HELPER_IDENTIFIER="$(codesign -dvv "$PROVIDER_ENGINE" 2>&1 | awk -F= '/^Identifier=/{value=$2} END{print value}')"
[[ "$HELPER_IDENTIFIER" == "com.aimaccleaner.app.codexbar" ]] || {
  printf 'Unexpected provider engine signing identifier: %s\n' "$HELPER_IDENTIFIER" >&2
  exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PLIST")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PLIST")" == "$BUILD_NUMBER" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :TraceFenceDistributionChannel' "$APP_PLIST")" == "appStore" ]]
MUSIC_PURPOSE="$(/usr/libexec/PlistBuddy -c 'Print :NSAppleMusicUsageDescription' "$APP_PLIST" 2>/dev/null || true)"
[[ -n "$MUSIC_PURPOSE" ]] || {
  printf 'App Store debug build is missing NSAppleMusicUsageDescription\n' >&2
  exit 1
}
for key in \
  TraceFenceDodoEnvironment \
  TraceFenceDodoBusinessID \
  TraceFenceDodoMonthlyProductID \
  TraceFenceDodoAnnualProductID \
  TraceFenceCheckoutReturnURL \
  TraceFenceUpdateAPIURL; do
  value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$APP_PLIST" 2>/dev/null || true)"
  [[ -z "$value" ]] || { printf 'App Store debug build contains direct-only configuration: %s\n' "$key" >&2; exit 1; }
done

printf '%s\n' "$APP_PATH"
