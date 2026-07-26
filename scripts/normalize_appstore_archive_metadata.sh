#!/usr/bin/env bash
set -euo pipefail

EXPECTED_XCODE_VERSION="${EXPECTED_XCODE_VERSION:-Xcode 26.6}"
EXPECTED_XCODE_BUILD="${EXPECTED_XCODE_BUILD:-17F113}"
EXPECTED_DTXCODE="${EXPECTED_DTXCODE:-2660}"
EXPECTED_HOST_OS_BUILD="${EXPECTED_HOST_OS_BUILD:-$(sw_vers -buildVersion)}"

fail() {
  printf 'normalize_appstore_archive_metadata: %s\n' "$*" >&2
  exit 1
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

if [[ $# -ne 1 ]]; then
  fail "usage: $0 <archive.xcarchive>"
fi

archive_path="$1"
[[ -d "$archive_path" ]] || fail "archive not found: $archive_path"

xcode_version="$(xcodebuild -version)"
printf '%s\n' "$xcode_version" | grep -qx "$EXPECTED_XCODE_VERSION" || fail "expected $EXPECTED_XCODE_VERSION"
printf '%s\n' "$xcode_version" | grep -qx "Build version $EXPECTED_XCODE_BUILD" || fail "expected Xcode build $EXPECTED_XCODE_BUILD"

app_plists="$(find "$archive_path/Products/Applications" -type f -name Info.plist -print)"
[[ -n "$app_plists" ]] || fail "no application Info.plist found"

printf '%s\n' "$app_plists" | while IFS= read -r app_plist; do
  dtxcode="$(plist_value "$app_plist" DTXcode)"
  dtxcode_build="$(plist_value "$app_plist" DTXcodeBuild)"
  sdk_name="$(plist_value "$app_plist" DTSDKName)"
  [[ "$dtxcode" == "$EXPECTED_DTXCODE" ]] || fail "unexpected DTXcode in $app_plist: $dtxcode"
  [[ "$dtxcode_build" == "$EXPECTED_XCODE_BUILD" ]] || fail "unexpected DTXcodeBuild in $app_plist: $dtxcode_build"
  [[ "$sdk_name" == iphoneos26.5 || "$sdk_name" == macosx26.5 ]] || fail "unexpected DTSDKName in $app_plist: $sdk_name"

  actual="$(plist_value "$app_plist" BuildMachineOSBuild)"
  [[ "$actual" == "$EXPECTED_HOST_OS_BUILD" ]] \
    || fail "archive metadata does not match the real build host in $app_plist: expected $EXPECTED_HOST_OS_BUILD, found $actual"
  printf 'Verified %s: DTXcode=%s DTXcodeBuild=%s DTSDKName=%s BuildMachineOSBuild=%s\n' \
    "$app_plist" "$dtxcode" "$dtxcode_build" "$sdk_name" "$actual"
done
