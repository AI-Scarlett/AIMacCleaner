#!/bin/bash
set -euo pipefail

SOURCE="${SRCROOT}/AIMacCleaner/Resources/codexbar"
SOURCE_CHECKSUM="${SRCROOT}/AIMacCleaner/Resources/codexbar.sha256"
HELPER_APP="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers/CodexBarHelper.app"
HELPER_CONTENTS="${HELPER_APP}/Contents"
HELPER_EXE="${HELPER_CONTENTS}/MacOS/codexbar"
INFO_PLIST="${HELPER_CONTENTS}/Info.plist"
LEGACY_HELPER="${TARGET_BUILD_DIR}/${EXECUTABLE_FOLDER_PATH}/codexbar"
HELPER_ENTITLEMENTS="${SRCROOT}/AIMacCleaner/CodexBarHelper.entitlements"

if [ ! -x "${SOURCE}" ]; then
  echo "error: bundled quota helper is missing or not executable: ${SOURCE}" >&2
  exit 1
fi

if [ ! -f "${SOURCE_CHECKSUM}" ]; then
  echo "error: bundled quota helper checksum is missing: ${SOURCE_CHECKSUM}" >&2
  exit 1
fi

EXPECTED_HASH="$(awk '{print $1}' "${SOURCE_CHECKSUM}")"
ACTUAL_HASH="$(/usr/bin/shasum -a 256 "${SOURCE}" | awk '{print $1}')"
if [ -z "${EXPECTED_HASH}" ] || [ "${ACTUAL_HASH}" != "${EXPECTED_HASH}" ]; then
  echo "error: bundled quota helper checksum mismatch." >&2
  echo "  expected: ${EXPECTED_HASH}" >&2
  echo "  actual:   ${ACTUAL_HASH}" >&2
  echo "  update ${SOURCE_CHECKSUM} only when intentionally replacing the vendored helper." >&2
  exit 1
fi

rm -f "${LEGACY_HELPER}"
rm -rf "${HELPER_APP}"
mkdir -p "${HELPER_CONTENTS}/MacOS"

cp "${SOURCE}" "${HELPER_EXE}"
chmod 755 "${HELPER_EXE}"

cat > "${INFO_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>codexbar</string>
  <key>CFBundleIdentifier</key>
  <string>com.aimaccleaner.app.codexbar</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>CodexBarHelper</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${MARKETING_VERSION:-1.0}</string>
  <key>CFBundleVersion</key>
  <string>${CURRENT_PROJECT_VERSION:-1}</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

if [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  /usr/bin/codesign \
    --force \
    --deep \
    --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
    --options runtime \
    --entitlements "${HELPER_ENTITLEMENTS}" \
    "${HELPER_APP}"
fi
