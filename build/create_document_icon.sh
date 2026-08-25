#!/bin/bash

set -euo pipefail

# The app icon is intentionally a full macOS app tile. Document icons use the
# same Van mark without that tile so Finder can composite it on any surface.
SOURCE_FILE_PATH="${1:-./build/icon.png}"
OUT_FILE_PATH="${2:-./build/document.icns}"
ICONSET_PATH="$(mktemp -d "${TMPDIR:-/tmp}/van-document-icon.XXXXXX.iconset")"

cleanup()
{
    rm -rf "$ICONSET_PATH"
}

trap cleanup EXIT

if ! command -v magick >/dev/null 2>&1 || ! command -v iconutil >/dev/null 2>&1; then
    echo "ERROR: This script requires ImageMagick and iconutil." >&2
    exit 1
fi

mkdir -p "$(dirname "$OUT_FILE_PATH")"

# Remove the near-white canvas while preserving white highlights enclosed by
# the Van mark. Flood filling from a corner avoids making those highlights
# transparent as well.
magick "$SOURCE_FILE_PATH" \
    -alpha on \
    -fuzz 12% \
    -fill none \
    -draw 'color 0,0 floodfill' \
    "$ICONSET_PATH/icon_512x512@2x.png"

magick "$ICONSET_PATH/icon_512x512@2x.png" \
    \( +clone -resize 16x16 -write "$ICONSET_PATH/icon_16x16.png" +delete \) \
    \( +clone -resize 32x32 -write "$ICONSET_PATH/icon_16x16@2x.png" +delete \) \
    \( +clone -resize 32x32 -write "$ICONSET_PATH/icon_32x32.png" +delete \) \
    \( +clone -resize 64x64 -write "$ICONSET_PATH/icon_32x32@2x.png" +delete \) \
    \( +clone -resize 128x128 -write "$ICONSET_PATH/icon_128x128.png" +delete \) \
    \( +clone -resize 256x256 -write "$ICONSET_PATH/icon_128x128@2x.png" +delete \) \
    \( +clone -resize 256x256 -write "$ICONSET_PATH/icon_256x256.png" +delete \) \
    \( +clone -resize 512x512 -write "$ICONSET_PATH/icon_256x256@2x.png" +delete \) \
    -resize 512x512 "$ICONSET_PATH/icon_512x512.png"

iconutil -c icns -o "$OUT_FILE_PATH" "$ICONSET_PATH"
