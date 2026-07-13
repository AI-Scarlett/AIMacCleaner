#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CORE_DIR="$ROOT_DIR/TraceFenceAgentCore"
SOURCE_FILE="$CORE_DIR/Sources/TraceFenceAgentCore/main.swift"
VERSION="${TRACEFENCE_CORE_VERSION:-$(sed -n 's/^private let coreVersion = "\([^"]*\)"/\1/p' "$SOURCE_FILE" | head -n 1)}"
BUILD="${TRACEFENCE_CORE_BUILD:-$(sed -n 's/^private let coreBuild = \([0-9][0-9]*\)/\1/p' "$SOURCE_FILE" | head -n 1)}"
CHANNEL="${TRACEFENCE_CORE_CHANNEL:-stable}"
OUTPUT_DIR="${TRACEFENCE_CORE_RELEASE_OUTPUT_DIR:-$ROOT_DIR/build/TraceFenceAgentCore-$VERSION}"
BUNDLE="$OUTPUT_DIR/TraceFenceAgentCore.bundle"
ARCHIVE="$OUTPUT_DIR/TraceFenceAgentCore-$VERSION.zip"
MANIFEST="$OUTPUT_DIR/tracefence-agent-core-$CHANNEL.json"
IDENTITY="${TRACEFENCE_CORE_CODESIGN_IDENTITY:-Developer ID Application: xiaoming zhou (UQ87N2WZ76)}"
PACKAGE_URL="${TRACEFENCE_CORE_PACKAGE_URL:-TraceFenceAgentCore-$VERSION.zip}"
TEAM_ID="${TRACEFENCE_CORE_TEAM_ID:-UQ87N2WZ76}"

if [ -z "$VERSION" ] || [ -z "$BUILD" ]; then
  printf '%s\n' "Unable to read Core version/build from $SOURCE_FILE" >&2
  exit 1
fi

swift build --package-path "$CORE_DIR" --configuration release
rm -rf "$OUTPUT_DIR"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources/adapters"

cp "$CORE_DIR/.build/release/TraceFenceAgentCore" "$BUNDLE/Contents/MacOS/TraceFenceAgentCore"
cp "$CORE_DIR/.build/release/TraceFenceAgentCoreUpdater" "$BUNDLE/Contents/MacOS/TraceFenceAgentCoreUpdater"
cp "$CORE_DIR/.build/release/TraceFenceClaudeAdapter" "$BUNDLE/Contents/Resources/adapters/TraceFenceClaudeAdapter"
cp "$CORE_DIR/.build/release/TraceFenceUniversalAdapter" "$BUNDLE/Contents/Resources/adapters/TraceFenceUniversalAdapter"
cp "$CORE_DIR/adapters"/*.json "$BUNDLE/Contents/Resources/adapters/"
chmod 755 "$BUNDLE/Contents/MacOS/TraceFenceAgentCore" "$BUNDLE/Contents/MacOS/TraceFenceAgentCoreUpdater"
chmod 755 "$BUNDLE/Contents/Resources/adapters/TraceFenceClaudeAdapter" "$BUNDLE/Contents/Resources/adapters/TraceFenceUniversalAdapter"

cat > "$BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>TraceFence Agent Core</string>
  <key>CFBundleExecutable</key>
  <string>TraceFenceAgentCore</string>
  <key>CFBundleIdentifier</key>
  <string>com.tracefence.agent-core.bundle</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>TraceFenceAgentCore</string>
  <key>CFBundlePackageType</key>
  <string>BNDL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
</dict>
</plist>
EOF

sign_item() {
  item="$1"
  identifier="$2"
  if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - --identifier "$identifier" "$item"
  else
    codesign --force --sign "$IDENTITY" --options runtime --timestamp --identifier "$identifier" "$item"
  fi
}

sign_item "$BUNDLE/Contents/MacOS/TraceFenceAgentCore" "com.tracefence.agent-core"
sign_item "$BUNDLE/Contents/MacOS/TraceFenceAgentCoreUpdater" "com.tracefence.agent-core.updater"
sign_item "$BUNDLE/Contents/Resources/adapters/TraceFenceClaudeAdapter" "com.tracefence.agent-core.adapter.claude"
sign_item "$BUNDLE/Contents/Resources/adapters/TraceFenceUniversalAdapter" "com.tracefence.agent-core.adapter.universal"
if [ "$IDENTITY" = "-" ]; then
  codesign --force --sign - --identifier "com.tracefence.agent-core.bundle" "$BUNDLE"
else
  codesign --force --sign "$IDENTITY" --options runtime --timestamp --identifier "com.tracefence.agent-core.bundle" "$BUNDLE"
fi
codesign --verify --deep --strict --verbose=2 "$BUNDLE"

(
  cd "$OUTPUT_DIR"
  /usr/bin/zip -qry "$(basename "$ARCHIVE")" "$(basename "$BUNDLE")"
)

if [ -n "${TRACEFENCE_CORE_NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$ARCHIVE" --keychain-profile "$TRACEFENCE_CORE_NOTARY_PROFILE" --wait
fi

HASH="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
SIZE="$(stat -f %z "$ARCHIVE")"
PUBLISHED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

cat > "$MANIFEST" <<EOF
{
  "schemaVersion": 1,
  "channel": "$CHANNEL",
  "version": "$VERSION",
  "build": $BUILD,
  "minimumProtocolVersion": 1,
  "packageURL": "$PACKAGE_URL",
  "packageSHA256": "$HASH",
  "packageSize": $SIZE,
  "bundleIdentifier": "com.tracefence.agent-core.bundle",
  "publishedAt": "$PUBLISHED_AT"
}
EOF

printf '%s\n' "Built signed TraceFence Agent Core $VERSION ($BUILD)"
printf '%s\n' "Bundle: $BUNDLE"
printf '%s\n' "Archive: $ARCHIVE"
printf '%s\n' "Manifest: $MANIFEST"
printf '%s\n' "Trusted Team ID: $TEAM_ID"
