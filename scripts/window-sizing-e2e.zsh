#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="${APEXTERM_APP_EXECUTABLE:-$ROOT/.build/debug/ApexTerm}"
INSTALLED_APP="/Applications/ApexTerm.app"
TMP_ROOT="$(mktemp -d /tmp/apexterm-window-sizing.XXXXXX)"
SUPPORT="$TMP_ROOT/support"
PROBE="$TMP_ROOT/window-probe.txt"
APP_LOG="$TMP_ROOT/app.log"
APP_PID=""

stop_app() {
  pkill -x ApexTerm 2>/dev/null || true
  for _ in {1..100}; do
    pgrep -x ApexTerm >/dev/null 2>&1 || return 0
    sleep 0.05
  done
  print -u2 -r -- "ApexTerm did not stop before window sizing E2E"
  return 1
}

cleanup() {
  if [[ -n "$APP_PID" ]]; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  stop_app 2>/dev/null || true
  pkill -f "$SUPPORT/shell-integration/tmux.conf" 2>/dev/null || true
  rm -rf "$TMP_ROOT"
  open "$INSTALLED_APP" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

[[ -x "$APP" ]]
mkdir -p "$SUPPORT"
stop_app

APEXTERM_SUPPORT_DIRECTORY="$SUPPORT" \
APEXTERM_WINDOW_PROBE_FILE="$PROBE" \
APEXTERM_WINDOW_PROBE_EXIT=1 \
"$APP" >"$APP_LOG" 2>&1 &
APP_PID=$!

for _ in {1..600}; do
  [[ -f "$PROBE" ]] && break
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    print -u2 -r -- "ApexTerm exited before the window sizing probe completed"
    tail -80 "$APP_LOG" >&2 || true
    exit 1
  fi
  sleep 0.025
done

if [[ ! -f "$PROBE" ]]; then
  print -u2 -r -- "Window sizing probe timed out"
  tail -80 "$APP_LOG" >&2 || true
  exit 1
fi

typeset -a missing
missing=()
for expected in \
  'resizable=1' \
  'requested_minimum=320x250' \
  'minimum=320x250' \
  'compact=640x480' \
  'expanded=1280x780'
do
  grep -Fqx "$expected" "$PROBE" || missing+=("$expected")
done

if (( ${#missing[@]} > 0 )); then
  print -u2 -r -- "Window sizing probe assertions failed:"
  printf '  %s\n' "${missing[@]}" >&2
  print -u2 -r -- '--- PROBE ---'
  cat "$PROBE" >&2
  print -u2 -r -- '--- APP LOG ---'
  tail -120 "$APP_LOG" >&2 || true
  exit 1
fi

print -r -- 'WINDOW_SIZING_UI_E2E=PASS'
cat "$PROBE"
