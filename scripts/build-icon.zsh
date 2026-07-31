#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
SVG="$ROOT_DIR/Packaging/ApexTermIcon.svg"
OUTPUT="${1:-$ROOT_DIR/.artifacts/ApexTermIcon.icns}"
TMP_ROOT="$(mktemp -d /tmp/apexterm-icon.XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

mkdir -p "${OUTPUT:h}" "$TMP_ROOT/icon.iconset"
/usr/bin/qlmanage -t -s 1024 -o "$TMP_ROOT" "$SVG" >/dev/null 2>&1
SOURCE_PNG="$TMP_ROOT/${SVG:t}.png"
[[ -f "$SOURCE_PNG" ]]

for spec in \
  '16 icon_16x16.png' \
  '32 icon_16x16@2x.png' \
  '32 icon_32x32.png' \
  '64 icon_32x32@2x.png' \
  '128 icon_128x128.png' \
  '256 icon_128x128@2x.png' \
  '256 icon_256x256.png' \
  '512 icon_256x256@2x.png' \
  '512 icon_512x512.png' \
  '1024 icon_512x512@2x.png'
do
  size="${spec%% *}"
  name="${spec#* }"
  /usr/bin/sips -z "$size" "$size" "$SOURCE_PNG" --out "$TMP_ROOT/icon.iconset/$name" >/dev/null
 done

/usr/bin/iconutil -c icns "$TMP_ROOT/icon.iconset" -o "$OUTPUT"
printf '%s\n' "$OUTPUT"
