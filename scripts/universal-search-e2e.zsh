#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="${APEXTERM_APP_EXECUTABLE:-$ROOT/.build/debug/ApexTerm}"
INSTALLED_APP="/Applications/ApexTerm.app"
TMP_ROOT="$(mktemp -d /tmp/apexterm-universal-search.XXXXXX)"
SUPPORT="$TMP_ROOT/support"
PROBE="$TMP_ROOT/universal-search-probe.txt"
APP_LOG="$TMP_ROOT/app.log"
APP_PID=""

stop_app() {
  pkill -x ApexTerm 2>/dev/null || true
  for _ in {1..100}; do
    pgrep -x ApexTerm >/dev/null 2>&1 || return 0
    sleep 0.05
  done
  print -u2 -r -- "ApexTerm did not stop before Universal Search E2E"
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
APEXTERM_UNIVERSAL_SEARCH_PROBE_FILE="$PROBE" \
"$APP" >"$APP_LOG" 2>&1 &
APP_PID=$!

for _ in {1..1200}; do
  if [[ -f "$PROBE" ]] && grep -Fqx 'probe_complete=1' "$PROBE"; then
    break
  fi
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    print -u2 -r -- "ApexTerm exited before Universal Search probe completed"
    tail -80 "$APP_LOG" >&2 || true
    exit 1
  fi
  sleep 0.025
done

if [[ ! -f "$PROBE" ]] || ! grep -Fqx 'probe_complete=1' "$PROBE"; then
  print -u2 -r -- "Universal Search probe timed out"
  tail -80 "$APP_LOG" >&2 || true
  exit 1
fi

typeset -a missing
missing=()
for expected in \
  'shortcut_configured=1' \
  'menu_shortcut=1' \
  'shortcut_handled=1' \
  'view_presented=1' \
  'field_focused=1' \
  'snapshot_loaded=1' \
  'snapshot_reused=1' \
  'loading_state=1' \
  'search_completed=1' \
  'all_kinds=1' \
  'workspace_result=1' \
  'session_result=1' \
  'command_result=1' \
  'agent_chat_result=1' \
  'agent_event_result=1' \
  'workspace_scope=1' \
  'command_scope=1' \
  'agent_scope=1' \
  'empty_state=1' \
  'focus_state=1' \
  'universal_dismissed=1' \
  'command_history_presented=1' \
  'command_history_view=1' \
  'command_history_query=1' \
  'command_history_session=1' \
  'context_cleared_after_dismiss=1'
do
  grep -Fqx "$expected" "$PROBE" || missing+=("$expected")
done

if (( ${#missing[@]} > 0 )); then
  print -u2 -r -- "Universal Search probe assertions failed:"
  printf '  %s\n' "${missing[@]}" >&2
  print -u2 -r -- '--- PROBE ---'
  cat "$PROBE" >&2
  print -u2 -r -- '--- APP LOG ---'
  tail -120 "$APP_LOG" >&2 || true
  exit 1
fi

print -r -- 'UNIVERSAL_SEARCH_UI_E2E=PASS'
cat "$PROBE"
