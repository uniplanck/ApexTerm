#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="/Applications/ApexTerm.app"
CTL="$ROOT/.build/release/apextermctl"
TMP_ROOT="$(mktemp -d /tmp/apexterm-live-resize.XXXXXX)"
SUPPORT="$TMP_ROOT/support"
PROBE="$TMP_ROOT/resize.json"
FRAME_PROBE="$TMP_ROOT/live-pane-frame.json"
SCROLL_PROBE="$TMP_ROOT/scroll.txt"
SCROLL_MARKER="APEXTERM_RESIZE_E2E_${RANDOM}_${RANDOM}"
SOCKET="$SUPPORT/runtime/apexterm.sock"

stop_app() {
  pkill -x ApexTerm 2>/dev/null || true
  for _ in {1..80}; do
    pgrep -x ApexTerm >/dev/null 2>&1 || return 0
    sleep 0.05
  done
  print -u2 -r -- "ApexTerm did not stop before resize E2E"
  return 1
}

cleanup() {
  launchctl unsetenv APEXTERM_SUPPORT_DIRECTORY 2>/dev/null || true
  launchctl unsetenv APEXTERM_LIVE_PANE_RESIZE_PROBE_FILE 2>/dev/null || true
  launchctl unsetenv APEXTERM_LIVE_PANE_FRAME_PROBE_FILE 2>/dev/null || true
  launchctl unsetenv APEXTERM_SCROLL_PROBE_FILE 2>/dev/null || true
  launchctl unsetenv APEXTERM_SCROLL_PROBE_MARKER 2>/dev/null || true
  stop_app 2>/dev/null || true
  sleep 0.15
  open "$APP" >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mkdir -p "$SUPPORT"
stop_app
env -i \
HOME="$HOME" \
USER="${USER:-$(id -un)}" \
LOGNAME="${LOGNAME:-${USER:-$(id -un)}}" \
SHELL="${SHELL:-/bin/zsh}" \
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
TMPDIR="${TMPDIR:-/tmp}" \
APEXTERM_SUPPORT_DIRECTORY="$SUPPORT" \
APEXTERM_LIVE_PANE_RESIZE_PROBE_FILE="$PROBE" \
APEXTERM_LIVE_PANE_FRAME_PROBE_FILE="$FRAME_PROBE" \
APEXTERM_SCROLL_PROBE_FILE="$SCROLL_PROBE" \
APEXTERM_SCROLL_PROBE_MARKER="$SCROLL_MARKER" \
"$APP/Contents/MacOS/ApexTerm" >/dev/null 2>&1 &

for _ in {1..240}; do
  [[ -S "$SOCKET" ]] && break
  sleep 0.05
done
[[ -S "$SOCKET" ]]

for _ in {1..300}; do
  if [[ -f "$SCROLL_PROBE" && -f "$PROBE" && -f "$FRAME_PROBE" ]] \
      && [[ "$(jq -r '.frame.height // 0' "$PROBE" 2>/dev/null || echo 0)" -ge 8 ]] \
      && [[ "$(jq -r '(.hostHeight // 0) | floor' "$FRAME_PROBE" 2>/dev/null || echo 0)" -ge 70 ]]; then
    break
  fi
  sleep 0.05
done
[[ -f "$PROBE" ]]
[[ -f "$FRAME_PROBE" ]]
[[ -f "$SCROLL_PROBE" ]]
grep -Fqx 'command_captured=1' "$SCROLL_PROBE"

start_height="$(jq -r '.currentHeight' "$PROBE")"
start_actual_height="$(jq -r '(.hostHeight // 0) | floor' "$FRAME_PROBE")"
x="$(jq -r '.frame | (.x + .width / 2) | floor' "$PROBE")"
y="$(jq -r '.frame | (.y + .height / 2) | floor' "$PROBE")"
target_y=$((y - 90))

osascript -e 'tell application "System Events" to tell process "ApexTerm" to set frontmost to true'
sleep 0.3
cliclick -e 3 -w 24 \
  "m:$x,$y" \
  "dd:$x,$y" \
  "m:$x,$((y - 18))" \
  "m:$x,$((y - 36))" \
  "m:$x,$((y - 54))" \
  "m:$x,$((y - 72))" \
  "m:$x,$target_y" \
  "du:$x,$target_y"

for _ in {1..160}; do
  process_alive="$(pgrep -x ApexTerm >/dev/null && echo 1 || echo 0)"
  end_height="$(jq -r '.currentHeight // 0' "$PROBE" 2>/dev/null || echo 0)"
  end_actual_height="$(jq -r '(.hostHeight // 0) | floor' "$FRAME_PROBE" 2>/dev/null || echo 0)"
  events="$(jq -r '.events[]?' "$PROBE" 2>/dev/null || true)"
  if [[ "$process_alive" == 1 ]] \
      && [[ "$end_height" != "$start_height" ]] \
      && [[ "$end_actual_height" != "$start_actual_height" ]] \
      && print -r -- "$events" | grep -q '^up:'; then
    break
  fi
  sleep 0.05
done

pgrep -x ApexTerm >/dev/null
end_height="$(jq -r '.currentHeight' "$PROBE")"
end_actual_height="$(jq -r '(.hostHeight // 0) | floor' "$FRAME_PROBE")"
actual_delta=$((end_actual_height - start_actual_height))
(( actual_delta >= 0 )) || actual_delta=$((-actual_delta))
events="$(jq -r '.events[]?' "$PROBE")"
[[ "$end_height" != "$start_height" ]]
[[ "$end_actual_height" != "$start_actual_height" ]]
(( actual_delta >= 60 ))
print -r -- "$events" | grep -q '^down$'
print -r -- "$events" | grep -q '^drag:'
print -r -- "$events" | grep -q '^up:'

printf 'LIVE_PANE_RESIZE_E2E=PASS\n'
printf 'start_height=%s\n' "$start_height"
printf 'end_height=%s\n' "$end_height"
printf 'start_actual_height=%s\n' "$start_actual_height"
printf 'end_actual_height=%s\n' "$end_actual_height"
printf 'actual_delta=%s\n' "$actual_delta"
