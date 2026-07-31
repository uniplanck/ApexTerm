#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-debug}"
SOURCE_APP="${APEXTERM_SCREENSHOT_APP:-$ROOT/.artifacts/ApexTerm.app}"
OUTPUT_DIR="${APEXTERM_SCREENSHOT_OUTPUT_DIR:-$ROOT/docs/images}"
TMP_ROOT="$(mktemp -d /tmp/apexterm-readme-screenshots.XXXXXX)"
DEMO_APP="$TMP_ROOT/ApexTermReadme.app"
PROCESS_NAME="ApexTermReadme"
DEMO_BUNDLE_ID="com.uniplanck.ApexTerm.readme.$RANDOM.$RANDOM"
EXECUTABLE="$DEMO_APP/Contents/MacOS/$PROCESS_NAME"
CURRENT_PID=""

terminate_current_process() {
  if [[ -z "$CURRENT_PID" ]]; then
    return
  fi
  if kill -0 "$CURRENT_PID" 2>/dev/null; then
    kill "$CURRENT_PID" 2>/dev/null || true
    for _ in {1..40}; do
      if ! kill -0 "$CURRENT_PID" 2>/dev/null; then
        break
      fi
      sleep 0.05
    done
    if kill -0 "$CURRENT_PID" 2>/dev/null; then
      kill -9 "$CURRENT_PID" 2>/dev/null || true
    fi
  fi
  wait "$CURRENT_PID" 2>/dev/null || true
  CURRENT_PID=""
}

cleanup() {
  terminate_current_process
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
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $DEMO_BUNDLE_ID" "$DEMO_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName ApexTermReadme' "$DEMO_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :LSMultipleInstancesProhibited false' "$DEMO_APP/Contents/Info.plist"
chmod 755 "$EXECUTABLE"
codesign --force --deep --sign - "$DEMO_APP" >/dev/null
codesign --verify --deep --strict "$DEMO_APP"

capture_scene() {
  local scene="$1"
  local output="$OUTPUT_DIR/$2"
  local scene_root="$TMP_ROOT/$scene"
  local support="$scene_root/support"
  local ready="$scene_root/ready.txt"
  local window_probe="$scene_root/window.txt"
  local app_log="$scene_root/app.log"
  local pid=""

  mkdir -p "$support"

  /usr/bin/open \
    -n \
    --stdout "$app_log" \
    --stderr "$app_log" \
    --env "APEXTERM_SUPPORT_DIRECTORY=$support" \
    --env "APEXTERM_README_SCREENSHOT_SCENE=$scene" \
    --env "APEXTERM_README_SCREENSHOT_LANGUAGE=en" \
    --env "APEXTERM_README_SCREENSHOT_APPEARANCE=dark" \
    --env "APEXTERM_README_SCREENSHOT_READY_FILE=$ready" \
    --env "APEXTERM_README_SCREENSHOT_OUTPUT_FILE=$output" \
    --env "APEXTERM_WINDOW_PROBE_FILE=$window_probe" \
    "$DEMO_APP" \
    --args \
    -ApplePersistenceIgnoreState YES \
    -NSQuitAlwaysKeepsWindows NO

  for _ in {1..200}; do
    pid="$(pgrep -f "$EXECUTABLE" | head -1 || true)"
    if [[ -n "$pid" ]]; then
      break
    fi
    sleep 0.05
  done
  if [[ -z "$pid" ]]; then
    print -u2 -r -- "ApexTerm README scene failed to launch: $scene"
    tail -100 "$app_log" >&2 || true
    return 1
  fi
  CURRENT_PID="$pid"

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
  if [[ ! -f "$ready" ]] || ! grep -Fqx 'ready=1' "$ready"; then
    print -u2 -r -- "ApexTerm README scene timed out before ready: $scene"
    if [[ -f "$ready" ]]; then
      print -u2 -r -- "--- ready.txt ---"
      cat "$ready" >&2
    fi
    if [[ -f "$window_probe" ]]; then
      print -u2 -r -- "--- window.txt ---"
      cat "$window_probe" >&2
    fi
    print -u2 -r -- "--- app.log ---"
    tail -100 "$app_log" >&2 || true
    return 1
  fi
  grep -Fqx 'app_appearance=dark' "$ready"
  grep -Fqx 'screenshot_written=1' "$ready"
  [[ -s "$output" ]]

  local corner="$(/opt/homebrew/bin/magick "$output" -format '%[pixel:p{0,0}]' info:)"
  local center="$(/opt/homebrew/bin/magick "$output" -format '%[pixel:p{w/2,h/2}]' info:)"
  local dimensions="$(/opt/homebrew/bin/magick "$output" -format '%wx%h' info:)"
  [[ "$corner" == *"255,255,255"* || "$corner" == *"ffffff"* ]]
  [[ "$center" != *"255,255,255"* && "$center" != *"ffffff"* ]]
  case "$scene" in
    overview) [[ "$dimensions" == "1324x864" ]] ;;
    compact) [[ "$dimensions" == "904x574" ]] ;;
  esac
  /opt/homebrew/bin/magick identify "$output"

  terminate_current_process
}

capture_scene overview overview.png
capture_scene search universal-search.png
capture_scene timeline command-timeline.png
capture_scene settings settings.png
capture_scene compact compact-tabs.png

printf 'README_SCREENSHOTS=PASS\n'
