#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-debug}"
SOURCE_APP="${APEXTERM_SCREENSHOT_APP:-$ROOT/.artifacts/ApexTerm.app}"
OUTPUT_DIR="${APEXTERM_SCREENSHOT_OUTPUT_DIR:-$ROOT/docs/images}"
TMP_ROOT="$(mktemp -d /tmp/apexterm-readme-screenshots.XXXXXX)"
DEMO_APP="$TMP_ROOT/ApexTermReadme.app"
PROCESS_NAME="ApexTermReadme"
EXECUTABLE="$DEMO_APP/Contents/MacOS/$PROCESS_NAME"

cleanup() {
  pkill -x "$PROCESS_NAME" 2>/dev/null || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT INT TERM

if [[ ! -d "$SOURCE_APP" ]]; then
  BUILD_CONFIGURATION="$BUILD_CONFIGURATION" OUTPUT_DIR="$ROOT/.artifacts" \
    zsh "$ROOT/scripts/build-app.zsh" >/dev/null
fi
[[ -d "$SOURCE_APP" ]]

mkdir -p "$OUTPUT_DIR"
cp -R "$SOURCE_APP" "$DEMO_APP"
mv "$DEMO_APP/Contents/MacOS/ApexTerm" "$EXECUTABLE"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable ApexTermReadme' "$DEMO_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.uniplanck.ApexTerm.readme' "$DEMO_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName ApexTermReadme' "$DEMO_APP/Contents/Info.plist"
chmod 755 "$EXECUTABLE"
codesign --force --deep --sign - "$DEMO_APP" >/dev/null
codesign --verify --deep --strict "$DEMO_APP"

capture_scene() {
  local scene="$1"
  local output="$OUTPUT_DIR/$2"
  local scene_root="$TMP_ROOT/$scene"
  local support="$scene_root/support"
  local ready="$scene_root/ready.txt"
  local app_log="$scene_root/app.log"
  local pid=""

  mkdir -p "$support"
  pkill -x "$PROCESS_NAME" 2>/dev/null || true

  env -i \
    HOME="$HOME" \
    USER="${USER:-$(id -un)}" \
    LOGNAME="${LOGNAME:-${USER:-$(id -un)}}" \
    SHELL="${SHELL:-/bin/zsh}" \
    PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    TMPDIR="${TMPDIR:-/tmp}" \
    APEXTERM_SUPPORT_DIRECTORY="$support" \
    APEXTERM_README_SCREENSHOT_SCENE="$scene" \
    APEXTERM_README_SCREENSHOT_LANGUAGE="en" \
    APEXTERM_README_SCREENSHOT_APPEARANCE="dark" \
    APEXTERM_README_SCREENSHOT_READY_FILE="$ready" \
    APEXTERM_README_SCREENSHOT_OUTPUT_FILE="$output" \
    "$EXECUTABLE" >"$app_log" 2>&1 &
  pid=$!

  for _ in {1..600}; do
    if [[ -f "$ready" ]] && grep -Fqx 'ready=1' "$ready"; then
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      print -u2 -r -- "ApexTerm README scene exited early: $scene"
      tail -100 "$app_log" >&2 || true
      return 1
    fi
    sleep 0.05
  done
  [[ -f "$ready" ]]
  grep -Fqx 'ready=1' "$ready"
  grep -Fqx 'app_appearance=dark' "$ready"
  grep -Fqx 'screenshot_written=1' "$ready"
  [[ -s "$output" ]]

  local corner="$(/opt/homebrew/bin/magick "$output" -format '%[pixel:p{0,0}]' info:)"
  local center="$(/opt/homebrew/bin/magick "$output" -format '%[pixel:p{w/2,h/2}]' info:)"
  [[ "$corner" == *"255,255,255"* || "$corner" == *"ffffff"* ]]
  [[ "$center" != *"255,255,255"* && "$center" != *"ffffff"* ]]
  /opt/homebrew/bin/magick identify "$output"

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

capture_scene overview overview.png
capture_scene search universal-search.png
capture_scene timeline command-timeline.png
capture_scene settings settings.png
capture_scene compact compact-tabs.png

printf 'README_SCREENSHOTS=PASS\n'
