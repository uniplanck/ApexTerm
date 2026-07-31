#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/.artifacts}"
APP_BUNDLE="$OUTPUT_DIR/ApexTerm.app"
EXECUTABLE="$ROOT_DIR/.build/$BUILD_CONFIGURATION/ApexTerm"
GAG_EXECUTABLE="$ROOT_DIR/.build/$BUILD_CONFIGURATION/gag"

cd "$ROOT_DIR"
swift build -c "$BUILD_CONFIGURATION" --product ApexTerm
swift build -c "$BUILD_CONFIGURATION" --product gag

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources/bin"

cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/ApexTerm"
cp "$GAG_EXECUTABLE" "$APP_BUNDLE/Contents/Resources/bin/gag"
cp "$ROOT_DIR/Packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
for localization in "$ROOT_DIR"/Sources/ApexTermApp/Resources/*.lproj; do
  cp -R "$localization" "$APP_BUNDLE/Contents/Resources/"
done
"$ROOT_DIR/scripts/build-icon.zsh" "$APP_BUNDLE/Contents/Resources/ApexTermIcon.icns" >/dev/null
chmod 755 "$APP_BUNDLE/Contents/MacOS/ApexTerm" "$APP_BUNDLE/Contents/Resources/bin/gag"
strip -x "$APP_BUNDLE/Contents/MacOS/ApexTerm" "$APP_BUNDLE/Contents/Resources/bin/gag"

plutil -lint "$APP_BUNDLE/Contents/Info.plist" >/dev/null
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
codesign --verify --deep --strict "$APP_BUNDLE"

printf '%s\n' "$APP_BUNDLE"
