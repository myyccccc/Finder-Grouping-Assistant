#!/bin/zsh
set -euo pipefail
SOURCE_DIR="${0:A:h:h}"
OUTPUT_DIR="${1:-${SOURCE_DIR:h}}"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/finder-grouping-package.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
[[ -f "$OUTPUT_DIR/Finder分组助手-应用.zip" ]] || { print 'Run build.sh first.'; exit 1; }
ditto --norsrc --noextattr -x -k "$OUTPUT_DIR/Finder分组助手-应用.zip" "$STAGE_DIR"
APP_PATH="$STAGE_DIR/Finder分组助手.app"
codesign --verify --deep --strict "$APP_PATH"
"$APP_PATH/Contents/MacOS/FinderGroupingAssistant" --self-test
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
ln -s /Applications "$STAGE_DIR/Applications"
cat > "$STAGE_DIR/Read Me.txt" <<'TEXT'
Finder Grouping Assistant / Finder 分组助手

Drag the app to Applications, then open it. Click the folder icon in the menu bar to set grouping, sorting and scope. Grant Accessibility and Automation access when enabling automatic grouping. macOS 13 or later.

将应用拖入 Applications（应用程序）后打开。点击顶部菜单栏的文件夹图标，设置分组、排序及应用范围。开启自动分组时按引导授权辅助功能和自动化。需要 macOS 13 或更新版本。
TEXT
DMG="$OUTPUT_DIR/Finder分组助手-$VERSION.dmg"
hdiutil create -volname 'Finder Grouping Assistant' -srcfolder "$STAGE_DIR" -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
if [[ -n "${FINDER_SIGN_IDENTITY:-}" && "$FINDER_SIGN_IDENTITY" != '-' ]]; then
 codesign --force --sign "$FINDER_SIGN_IDENTITY" --timestamp "$DMG"
 codesign --verify --strict "$DMG"
fi
print "Packaged: $DMG"
