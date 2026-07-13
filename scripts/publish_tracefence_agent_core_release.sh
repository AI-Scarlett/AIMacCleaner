#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
REPOSITORY="${TRACEFENCE_CORE_GITHUB_REPOSITORY:-AI-Scarlett/TraceFence}"
CHANNEL_TAG="${TRACEFENCE_CORE_GITHUB_TAG:-agent-core-stable}"
CORE_SOURCE="$ROOT_DIR/TraceFenceAgentCore/Sources/TraceFenceAgentCore/main.swift"
VERSION="${TRACEFENCE_CORE_VERSION:-$(sed -n 's/^private let coreVersion = "\([^"]*\)"/\1/p' "$CORE_SOURCE" | head -n 1)}"
OUTPUT_DIR="${TRACEFENCE_CORE_RELEASE_OUTPUT_DIR:-$ROOT_DIR/build/TraceFenceAgentCore-$VERSION}"
ARCHIVE="$OUTPUT_DIR/TraceFenceAgentCore-$VERSION.zip"
MANIFEST="$OUTPUT_DIR/tracefence-agent-core-stable.json"

if [ ! -f "$ARCHIVE" ] || [ ! -f "$MANIFEST" ]; then
  printf '%s\n' "Core release artifacts are missing; build them first." >&2
  exit 1
fi

if ! gh release view "$CHANNEL_TAG" --repo "$REPOSITORY" >/dev/null 2>&1; then
  gh release create "$CHANNEL_TAG" \
    --repo "$REPOSITORY" \
    --target main \
    --title "TraceFence Agent Core Stable" \
    --notes "Independent signed TraceFence Agent Core and adapter update channel. This release does not contain the macOS application." \
    --latest=false
fi

gh release upload "$CHANNEL_TAG" \
  "$ARCHIVE" \
  "$MANIFEST" \
  --repo "$REPOSITORY" \
  --clobber

MANIFEST_URL="https://github.com/$REPOSITORY/releases/download/$CHANNEL_TAG/$(basename "$MANIFEST")"
PACKAGE_URL="https://github.com/$REPOSITORY/releases/download/$CHANNEL_TAG/$(basename "$ARCHIVE")"
curl --fail --silent --show-error --location --output /dev/null "$MANIFEST_URL"
curl --fail --silent --show-error --location --output /dev/null "$PACKAGE_URL"

printf '%s\n' "Published TraceFence Agent Core $VERSION"
printf '%s\n' "Manifest: $MANIFEST_URL"
printf '%s\n' "Package:  $PACKAGE_URL"
