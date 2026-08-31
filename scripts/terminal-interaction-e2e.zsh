#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
DEFAULT_APP="/Applications/ApexTerm.app"
APP="${APEXTERM_APP_BUNDLE:-$DEFAULT_APP}"
RESTORE_APP="${APEXTERM_RESTORE_APP_BUNDLE:-$APP}"
APP_EXECUTABLE="$APP/Contents/MacOS/ApexTerm"
LAUNCH_MODE="${APEXTERM_LAUNCH_MODE:-launchservices}"
RESTORE_APP_ON_EXIT=0
TMP_ROOT="$(mktemp -d /tmp/apexterm-terminal-interaction.XXXXXX)"
SUPPORT="$TMP_ROOT/support"
SCROLL_PROBE="$TMP_ROOT/scroll-probe.txt"
BLOCK_PROBE="$TMP_ROOT/block-probe.txt"
PROMPT_PROBE="$TMP_ROOT/prompt-probe.txt"
PROGRAMMATIC_PROBE="$TMP_ROOT/programmatic-input-probe.txt"
READY_PROBE="$TMP_ROOT/ready.txt"
PROGRAMMATIC_MARKER="APT_PROGRAMMATIC_INPUT_${RANDOM}_${RANDOM}"
MARKER="APT_SCROLL_PROBE_DONE_${RANDOM}_${RANDOM}"
TMUX_SERVER="apexterm-e2e-${RANDOM}-${RANDOM}"

app_pids() {
  ps -axo pid=,command= | awk -v executable="$APP_EXECUTABLE" \
    '$2 == executable { print $1 }'
}

launch_app() {
  if [[ "$LAUNCH_MODE" == "direct" ]]; then
    "$APP_EXECUTABLE" >/dev/null 2>&1 &
  else
    open -n "$APP"
  fi
}

stop_app() {
  local pids
  pids="$(app_pids)"
  if [[ -z "$pids" ]]; then
    return 0
  fi
  for pid in ${(f)pids}; do
    kill "$pid" 2>/dev/null || true
  done
  for _ in {1..80}; do
    [[ -z "$(app_pids)" ]] && return 0
    sleep 0.05
  done
  print -u2 -r -- "Target ApexTerm did not stop before Terminal Interaction E2E: $APP"
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
  launchctl unsetenv APEXTERM_READY_FILE 2>/dev/null || true
  stop_app 2>/dev/null || true
  tmux -L "$TMUX_SERVER" kill-server 2>/dev/null || true
  sleep 0.2
  if (( RESTORE_APP_ON_EXIT )); then
    open "$RESTORE_APP" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT INT TERM

mkdir -p "$SUPPORT"
[[ -n "$(app_pids)" ]] && RESTORE_APP_ON_EXIT=1
stop_app

export APEXTERM_SUPPORT_DIRECTORY="$SUPPORT"
export APEXTERM_TMUX_SERVER="$TMUX_SERVER"
export APEXTERM_SCROLL_PROBE_FILE="$SCROLL_PROBE"
export APEXTERM_SCROLL_PROBE_MARKER="$MARKER"
export APEXTERM_COMMAND_BLOCK_PROBE_FILE="$BLOCK_PROBE"
export APEXTERM_PROMPT_DECORATION_PROBE_FILE="$PROMPT_PROBE"
export APEXTERM_PROGRAMMATIC_INPUT_PROBE_FILE="$PROGRAMMATIC_PROBE"
export APEXTERM_PROGRAMMATIC_INPUT_PROBE_MARKER="$PROGRAMMATIC_MARKER"
export APEXTERM_READY_FILE="$READY_PROBE"
launchctl setenv APEXTERM_SUPPORT_DIRECTORY "$SUPPORT"
launchctl setenv APEXTERM_TMUX_SERVER "$TMUX_SERVER"
launchctl setenv APEXTERM_SCROLL_PROBE_FILE "$SCROLL_PROBE"
launchctl setenv APEXTERM_SCROLL_PROBE_MARKER "$MARKER"
launchctl setenv APEXTERM_COMMAND_BLOCK_PROBE_FILE "$BLOCK_PROBE"
launchctl setenv APEXTERM_PROMPT_DECORATION_PROBE_FILE "$PROMPT_PROBE"
launchctl setenv APEXTERM_PROGRAMMATIC_INPUT_PROBE_FILE "$PROGRAMMATIC_PROBE"
launchctl setenv APEXTERM_PROGRAMMATIC_INPUT_PROBE_MARKER "$PROGRAMMATIC_MARKER"
launchctl setenv APEXTERM_READY_FILE "$READY_PROBE"
launch_app

for _ in $(seq 1 300); do
  [[ -f "$SCROLL_PROBE" && -f "$BLOCK_PROBE" && -f "$PROMPT_PROBE" && -f "$PROGRAMMATIC_PROBE" && -f "$READY_PROBE" ]] && break
  sleep 0.05
done
[[ -f "$SCROLL_PROBE" ]]
[[ -f "$BLOCK_PROBE" ]]
[[ -f "$PROMPT_PROBE" ]]
[[ -f "$PROGRAMMATIC_PROBE" ]]
[[ -f "$READY_PROBE" ]]
grep -Fqx 'ready=1' "$READY_PROBE"
grep -Fqx 'metal=1' "$READY_PROBE"
grep -Fqx 'programmatic_input=1' "$PROGRAMMATIC_PROBE"
grep -Fqx 'process=1' "$PROGRAMMATIC_PROBE"

for expected in \
  'command_captured=1' \
  'output_captured=1' \
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
