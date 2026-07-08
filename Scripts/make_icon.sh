#!/bin/bash
# Generates Icon/AppIcon.icns from the custom renderer.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
OUT="$ROOT/Icon"
mkdir -p "$OUT"

echo "==> Rendering master PNG"
swift "$ROOT/Scripts/make_icon.swift" "$TMP/master.png"

echo "==> Building iconset"
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for pair in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
    set -- $pair
    sips -z "$1" "$1" "$TMP/master.png" --out "$ICONSET/icon_$2.png" >/dev/null
done

echo "==> Building icns"
iconutil -c icns "$ICONSET" -o "$OUT/AppIcon.icns"
echo "==> Done: $OUT/AppIcon.icns"
rm -rf "$TMP"
