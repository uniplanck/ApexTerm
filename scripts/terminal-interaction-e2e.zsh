#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="${APEXTERM_APP_BUNDLE:-/Applications/ApexTerm.app}"
RESTORE_APP="${APEXTERM_RESTORE_APP_BUNDLE:-$APP}"
TMP_ROOT="$(mktemp -d /tmp/apexterm-terminal-interaction.XXXXXX)"
SUPPORT="$TMP_ROOT/support"
SCROLL_PROBE="$TMP_ROOT/scroll-probe.txt"
BLOCK_PROBE="$TMP_ROOT/block-probe.txt"
PROMPT_PROBE="$TMP_ROOT/prompt-probe.txt"
PROGRAMMATIC_PROBE="$TMP_ROOT/programmatic-input-probe.txt"
PROGRAMMATIC_MARKER="APT_PROGRAMMATIC_INPUT_${RANDOM}_${RANDOM}"
MARKER="APT_SCROLL_PROBE_DONE_${RANDOM}_${RANDOM}"
TMUX_SERVER="apexterm-e2e-${RANDOM}-${RANDOM}"

stop_app() {
  pkill -x ApexTerm 2>/dev/null || true
  for _ in {1..80}; do
    pgrep -x ApexTerm >/dev/null 2>&1 || return 0
    sleep 0.05
  done
  print -u2 -r -- "ApexTerm did not stop before Terminal Interaction E2E"
  return 1
}

cleanup() {
  launchctl unsetenv APEXTERM_SUPPORT_DIRECTORY 2>/dev/null || true
  launchctl unsetenv APEXTERM_TMUX_SERVER 2>/dev/null || true
  launchctl unsetenv APEXTERM_SCROLL_PROBE_FILE 2>/dev/null || true
  launchctl unsetenv APEXTERM_SCROLL_PROBE_MARKER 2>/dev/null || true
  launchctl unsetenv APEXTERM_COMMAND_BLOCK_PROBE_FILE 2>/dev/null || true
  launchctl unsetenv APEXTERM_PROMPT_DECORATION_PROBE_FILE 2>/dev/null || true
  launchctl unsetenv APEXTERM_PROGRAMMATIC_INPUT_PROBE_FILE 2>/dev/null || true
  launchctl unsetenv APEXTERM_PROGRAMMATIC_INPUT_PROBE_MARKER 2>/dev/null || true
  stop_app 2>/dev/null || true
  tmux -L "$TMUX_SERVER" kill-server 2>/dev/null || true
  sleep 0.2
  open "$RESTORE_APP" >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT INT TERM

mkdir -p "$SUPPORT"
stop_app

launchctl setenv APEXTERM_SUPPORT_DIRECTORY "$SUPPORT"
launchctl setenv APEXTERM_TMUX_SERVER "$TMUX_SERVER"
launchctl setenv APEXTERM_SCROLL_PROBE_FILE "$SCROLL_PROBE"
launchctl setenv APEXTERM_SCROLL_PROBE_MARKER "$MARKER"
launchctl setenv APEXTERM_COMMAND_BLOCK_PROBE_FILE "$BLOCK_PROBE"
launchctl setenv APEXTERM_PROMPT_DECORATION_PROBE_FILE "$PROMPT_PROBE"
launchctl setenv APEXTERM_PROGRAMMATIC_INPUT_PROBE_FILE "$PROGRAMMATIC_PROBE"
launchctl setenv APEXTERM_PROGRAMMATIC_INPUT_PROBE_MARKER "$PROGRAMMATIC_MARKER"
open "$APP"

for _ in $(seq 1 300); do
  [[ -f "$SCROLL_PROBE" && -f "$BLOCK_PROBE" && -f "$PROMPT_PROBE" && -f "$PROGRAMMATIC_PROBE" ]] && break
  sleep 0.05
done
[[ -f "$SCROLL_PROBE" ]]
[[ -f "$BLOCK_PROBE" ]]
[[ -f "$PROMPT_PROBE" ]]
[[ -f "$PROGRAMMATIC_PROBE" ]]
grep -Fqx 'programmatic_input=1' "$PROGRAMMATIC_PROBE"
grep -Fqx 'process=1' "$PROGRAMMATIC_PROBE"

for expected in \
  'command_captured=1' \
  'output_captured=1' \
  'mouse_mode=0' \
  'alternate_buffer=0' \
  'scroll_event_sent=1' \
  'scrollback_changed=1'
do
  grep -Fqx "$expected" "$SCROLL_PROBE"
done

for expected in \
  'button_found=1' \
  'button_enabled=1' \
  'button_hittable=1' \
  'button_visible=1' \
  'menu_items=1' \
  'output_copy_action=1' \
  'toggle_action=1' \
  'transcript_mode_button_found=1' \
  'transcript_mode_button_enabled=1' \
  'transcript_mode_button_hittable=1' \
  'mode_button_cycles_off=1' \
  'mode_button_cycles_ex=1' \
  'mode_button_cycles_c=1' \
  'mode_button_cycles_on=1'
do
  grep -Fqx "$expected" "$BLOCK_PROBE"
done

for expected in \
  'prompt_button_found=1' \
  'prompt_button_visible=1' \
  'prompt_button_hittable=1' \
  'prompt_button_action=1' \
  'prompt_button_count=1'
do
  grep -Fqx "$expected" "$PROMPT_PROBE"
done

if tmux -L "$TMUX_SERVER" has-session 2>/dev/null; then
  print -u2 'Normal Local Shell unexpectedly started tmux'
  exit 1
fi

event_store="$SUPPORT/events.sqlite"
legacy_history="$SUPPORT/command-history.json"
if [[ -f "$event_store" ]]; then
  clean_output="$(
    sqlite3 -cmd '.timeout 5000' "$event_store" \
      "SELECT CAST(payload AS TEXT) FROM events WHERE kind = 'command' ORDER BY occurred_at DESC, rowid DESC LIMIT 1;" \
      | jq -r '.output'
  )"
elif [[ -f "$legacy_history" ]]; then
  clean_output="$(jq -r '.[0].output' "$legacy_history")"
else
  print -u2 -r -- "Command history was not persisted to SQLite or legacy JSON"
  exit 1
fi
[[ "$clean_output" == APT_SCROLL_PROBE_001* ]]
[[ "$clean_output" == *"$MARKER" ]]
[[ "$clean_output" != *'BAPT_SCROLL_PROBE_'* ]]
[[ "$clean_output" != *$'\e'* ]]
[[ "$clean_output" != *'[detached (from session '* ]]

printf 'TERMINAL_INTERACTION_E2E=PASS\n'
printf 'LOCAL_SCROLLBACK=PASS\n'
printf 'LOCAL_SHELL_WITHOUT_TMUX=PASS\n'
printf 'COMMAND_BLOCK_CONTROL=PASS\n'
printf 'PROGRAMMATIC_INPUT=PASS\n'
printf 'SHELL_INTEGRATION_ENV=PASS\n'
printf 'CLEAN_CAPTURED_OUTPUT=PASS\n'
cat "$SCROLL_PROBE"
cat "$BLOCK_PROBE"
cat "$PROMPT_PROBE"
cat "$PROGRAMMATIC_PROBE"
