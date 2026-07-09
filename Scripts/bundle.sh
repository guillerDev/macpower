#!/bin/bash
# Builds MacPower and assembles a double-clickable MacPower.app bundle.
#
#   ./Scripts/bundle.sh            # release build -> ./dist/MacPower.app
#   ./Scripts/bundle.sh debug      # debug build
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MacPower"
BUNDLE_ID="com.macpower.app"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

# Version = single source of truth is the git tag. Priority:
#   1. MACPOWER_VERSION env (CI passes the tag being released)
#   2. the latest git tag (e.g. v1.2.0 -> 1.2.0)
#   3. a dev fallback
# The `|| true` is essential: with `set -euo pipefail`, a failing `git describe`
# (no tags — e.g. a shallow CI checkout) would otherwise abort the whole script.
GIT_TAG_VERSION="$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
VERSION="${MACPOWER_VERSION:-$GIT_TAG_VERSION}"
VERSION="${VERSION:-0.0.0}"
echo "==> Version: $VERSION"

cd "$ROOT"

# Stamp the embedded Info.plist (linked into the binary) with the same version
# for the duration of the build, then restore it so the working tree stays clean.
EMBED="$ROOT/Sources/MacPower/Info.plist"
cp "$EMBED" "$EMBED.bak"
trap 'mv "$EMBED.bak" "$EMBED"' EXIT
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$EMBED" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$EMBED" >/dev/null

echo "==> Building ($CONFIG)…"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

ICON_LINE=""
if [ -f "$ROOT/Icon/AppIcon.icns" ]; then
    cp "$ROOT/Icon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    ICON_LINE="<key>CFBundleIconFile</key><string>AppIcon</string>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    $ICON_LINE
</dict>
</plist>
PLIST

# Ad-hoc code signature so Gatekeeper lets it launch locally.
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "   (codesign skipped)"

echo "==> Done: $APP"
echo "    Launch with:  open \"$APP\""
