#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE_PROJECT="$PROJECT_DIR/ThirdParty/MacTools/MacTools.xcodeproj"
DESTINATION="$PROJECT_DIR/AIMacCleaner/Frameworks/MacToolsPluginKit.framework"
BUILD_ROOT="$(mktemp -d /tmp/tracefence-plugin-kit.XXXXXX)"
FRAMEWORK_BUNDLE_IDENTIFIER="com.tracefence.plugin-kit"

cleanup() {
  find "$BUILD_ROOT" -depth -delete
}
trap cleanup EXIT

xcodebuild \
  -project "$SOURCE_PROJECT" \
  -target MacToolsPluginKit \
  -configuration Release \
  SYMROOT="$BUILD_ROOT/Build/Products" \
  OBJROOT="$BUILD_ROOT/Build/Intermediates.noindex" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  MACOSX_DEPLOYMENT_TARGET=13.0 \
  PRODUCT_BUNDLE_IDENTIFIER="$FRAMEWORK_BUNDLE_IDENTIFIER" \
  CODE_SIGNING_ALLOWED=NO \
  build

mkdir -p "$(dirname "$DESTINATION")"
rsync -a --delete "$BUILD_ROOT/Build/Products/Release/MacToolsPluginKit.framework/" "$DESTINATION/"

BINARY="$DESTINATION/Versions/A/MacToolsPluginKit"
FRAMEWORK_INFO_PLIST="$DESTINATION/Versions/A/Resources/Info.plist"
ARCHITECTURES="$(/usr/bin/lipo -archs "$BINARY")"
if [[ "$ARCHITECTURES" != *"arm64"* || "$ARCHITECTURES" != *"x86_64"* ]]; then
  echo "Compatibility framework is not universal: $ARCHITECTURES" >&2
  exit 1
fi

BUILT_BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$FRAMEWORK_INFO_PLIST")"
if [ "$BUILT_BUNDLE_IDENTIFIER" != "$FRAMEWORK_BUNDLE_IDENTIFIER" ]; then
  echo "Compatibility framework bundle identifier is invalid: $BUILT_BUNDLE_IDENTIFIER" >&2
  exit 1
fi

echo "PLUGIN_KIT_BUILD_OK architectures=$ARCHITECTURES bundle_id=$BUILT_BUNDLE_IDENTIFIER destination=$DESTINATION"
