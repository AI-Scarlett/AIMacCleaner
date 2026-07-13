#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_ROOT="$HOME/Library/Application Support/TraceFence/Core"
SOURCE_BUNDLE="$ROOT_DIR/build/TraceFenceAgentCore-1.5.2/TraceFenceAgentCore.bundle"
FIXTURE_ROOT="/tmp/TraceFenceAgentCoreRollbackFixture"
FIXTURE_BUNDLE="$FIXTURE_ROOT/TraceFenceAgentCore.bundle"
ARCHIVE="$FIXTURE_ROOT/TraceFenceAgentCore-1.5.3.zip"
MANIFEST="$FIXTURE_ROOT/tracefence-agent-core-stable.json"
CONFIG="$FIXTURE_ROOT/update-config.json"
IDENTITY="${TRACEFENCE_CORE_CODESIGN_IDENTITY:-Developer ID Application: xiaoming zhou (UQ87N2WZ76)}"

rm -rf "$FIXTURE_ROOT"
mkdir -p "$FIXTURE_ROOT"
ditto "$SOURCE_BUNDLE" "$FIXTURE_BUNDLE"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.5.3" "$FIXTURE_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 1503" "$FIXTURE_BUNDLE/Contents/Info.plist"
codesign --force --sign "$IDENTITY" --options runtime --timestamp --identifier "com.tracefence.agent-core.bundle" "$FIXTURE_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$FIXTURE_BUNDLE"

(
  cd "$FIXTURE_ROOT"
  /usr/bin/zip -qry "$(basename "$ARCHIVE")" "$(basename "$FIXTURE_BUNDLE")"
)

HASH="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
SIZE="$(stat -f %z "$ARCHIVE")"
PUBLISHED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
cat > "$MANIFEST" <<EOF
{
  "schemaVersion": 1,
  "channel": "stable",
  "version": "1.5.3",
  "build": 1503,
  "minimumProtocolVersion": 1,
  "packageURL": "TraceFenceAgentCore-1.5.3.zip",
  "packageSHA256": "$HASH",
  "packageSize": $SIZE,
  "bundleIdentifier": "com.tracefence.agent-core.bundle",
  "publishedAt": "$PUBLISHED_AT"
}
EOF
cat > "$CONFIG" <<EOF
{
  "enabled": true,
  "automaticInstall": true,
  "channel": "stable",
  "manifestURL": "file://$MANIFEST",
  "trustedTeamID": "UQ87N2WZ76",
  "checkIntervalSeconds": 21600,
  "allowLocalPackages": true,
  "allowAdHocForLocalTesting": false
}
EOF

set +e
OUTPUT="$("$INSTALL_ROOT/TraceFenceAgentCoreUpdater" check-and-install \
  --config "$CONFIG" \
  --install-root "$INSTALL_ROOT" \
  --socket "$INSTALL_ROOT/agent-core.sock" \
  --current-version 1.5.2 \
  --current-build 1502 \
  --force 2>&1)"
STATUS=$?
set -e

if [ "$STATUS" -eq 0 ]; then
  printf '%s\n' "Rollback fixture unexpectedly installed." >&2
  exit 1
fi
case "$OUTPUT" in
  *updated_core_health_check_failed*) ;;
  *) printf '%s\n' "$OUTPUT" >&2; exit 1 ;;
esac

CURRENT_VERSION="$("$INSTALL_ROOT/TraceFenceAgentCore" --version)"
if [ "$CURRENT_VERSION" != "1.5.2" ]; then
  printf '%s\n' "Expected rollback to 1.5.2, got $CURRENT_VERSION" >&2
  exit 1
fi
if ! grep -q '"state":"rolled_back"' "$INSTALL_ROOT/update-status.json"; then
  printf '%s\n' "Updater did not preserve rolled_back state." >&2
  exit 1
fi
if [ -e "$INSTALL_ROOT/releases/1.5.3-1503" ]; then
  printf '%s\n' "Failed release was not removed." >&2
  exit 1
fi

printf '%s\n' "TRACEFENCE_CORE_ROLLBACK_PASS"
printf '%s\n' "current_version=$CURRENT_VERSION"
printf '%s\n' "failed_candidate=1.5.3-1503"
