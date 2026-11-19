#!/bin/zsh
set -euo pipefail
SOURCE_DIR="${0:A:h}"
OUTPUT_DIR="${1:-${SOURCE_DIR:h}}"
APP_PATH="$OUTPUT_DIR/Finder分组助手.app"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/finder-grouping-build.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
STAGING_APP="$BUILD_DIR/Finder分组助手.app"
mkdir -p "$OUTPUT_DIR" "$STAGING_APP/Contents/MacOS" "$STAGING_APP/Contents/Resources"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swift "$SOURCE_DIR/Tools/Icon.swift" "$BUILD_DIR/AppIcon.iconset"
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$SOURCE_DIR/Resources/AppIcon.icns"
for ARCH in arm64 x86_64; do
    xcrun swiftc -swift-version 5 -O -sdk "$SDK_PATH" -target "$ARCH-apple-macos13.0" \
        "$SOURCE_DIR"/Sources/*.swift -o "$BUILD_DIR/FinderGroupingAssistant-$ARCH" \
        -framework SwiftUI -framework AppKit -framework ApplicationServices -framework ServiceManagement
done
xcrun lipo -create "$BUILD_DIR/FinderGroupingAssistant-arm64" "$BUILD_DIR/FinderGroupingAssistant-x86_64" -output "$STAGING_APP/Contents/MacOS/FinderGroupingAssistant"
cp "$SOURCE_DIR/Resources/Info.plist" "$STAGING_APP/Contents/Info.plist"
plutil -lint "$SOURCE_DIR/Resources/PrivacyInfo.xcprivacy"
cp "$SOURCE_DIR/Resources/PrivacyInfo.xcprivacy" "$STAGING_APP/Contents/Resources/PrivacyInfo.xcprivacy"
if [[ -f "$SOURCE_DIR/Resources/AppIcon.icns" ]]; then cp "$SOURCE_DIR/Resources/AppIcon.icns" "$STAGING_APP/Contents/Resources/"; fi
for LANGUAGE_DIR in "$SOURCE_DIR"/Resources/*.lproj; do
    ditto --norsrc --noextattr "$LANGUAGE_DIR" "$STAGING_APP/Contents/Resources/${LANGUAGE_DIR:t}"
done
SIGN_IDENTITY="${FINDER_SIGN_IDENTITY:--}"
xattr -cr "$STAGING_APP"
if [[ "$SIGN_IDENTITY" == '-' ]]; then
    codesign --force --sign - --entitlements "$SOURCE_DIR/Resources/entitlements.plist" "$STAGING_APP"
else
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp --entitlements "$SOURCE_DIR/Resources/entitlements.plist" "$STAGING_APP"
fi
codesign --verify --deep --strict "$STAGING_APP"
"$STAGING_APP/Contents/MacOS/FinderGroupingAssistant" --self-test
"$STAGING_APP/Contents/MacOS/FinderGroupingAssistant" --permission-flow-test
# Every advertised language must also survive the final distribution archive.
ARCHIVE_CHECK_DIR="$BUILD_DIR/archive-check"
mkdir -p "$ARCHIVE_CHECK_DIR"
ditto --norsrc --noextattr -c -k --keepParent "$STAGING_APP" "$OUTPUT_DIR/Finder分组助手-应用.zip"
ditto --norsrc --noextattr -x -k "$OUTPUT_DIR/Finder分组助手-应用.zip" "$ARCHIVE_CHECK_DIR"
"$ARCHIVE_CHECK_DIR/Finder分组助手.app/Contents/MacOS/FinderGroupingAssistant" --self-test
ditto --norsrc --noextattr "$STAGING_APP" "$APP_PATH"
print "Built: $APP_PATH"
