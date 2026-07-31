#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="/Applications/ApexTerm.app"
TMP_ROOT="$(mktemp -d /tmp/apexterm-agent-chat.XXXXXX)"
SUPPORT="$TMP_ROOT/support"
PROBE="$TMP_ROOT/agent-chat-probe.txt"

stop_app() {
  pkill -x ApexTerm 2>/dev/null || true
  for _ in {1..80}; do
    pgrep -x ApexTerm >/dev/null 2>&1 || return 0
    sleep 0.05
  done
  print -u2 -r -- "ApexTerm did not stop before Agent Chat E2E"
  return 1
}

cleanup() {
  launchctl unsetenv APEXTERM_SUPPORT_DIRECTORY 2>/dev/null || true
  launchctl unsetenv APEXTERM_AGENT_CHAT_E2E_FILE 2>/dev/null || true
  launchctl unsetenv APEXTERM_AGENT_CHAT_E2E_TARGET 2>/dev/null || true
  launchctl unsetenv APEXTERM_AGENT_CHAT_E2E_PERFORMANCE 2>/dev/null || true
  stop_app 2>/dev/null || true
  sleep 0.15
  open "$APP" >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT INT TERM

mkdir -p "$SUPPORT"
stop_app
launchctl setenv APEXTERM_SUPPORT_DIRECTORY "$SUPPORT"
launchctl setenv APEXTERM_AGENT_CHAT_E2E_FILE "$PROBE"
launchctl setenv APEXTERM_AGENT_CHAT_E2E_TARGET local
launchctl setenv APEXTERM_AGENT_CHAT_E2E_PERFORMANCE high
open "$APP"

for _ in $(seq 1 600); do
  [[ -f "$PROBE" ]] && break
  sleep 0.5
done
[[ -f "$PROBE" ]]
cat "$PROBE"

for expected in \
  'agent_chat_job_started=1' \
  'agent_chat_progress=1' \
  'agent_chat_succeeded=1' \
  'agent_chat_response=1' \
  'agent_chat_tokens=1' \
  'agent_chat_requested_performance=1' \
  'agent_chat_actual_model=1' \
  'agent_chat_sol_model=1' \
  'agent_chat_cost=1' \
  'agent_chat_url=1'
do
  grep -Fqx "$expected" "$PROBE"
done

printf 'AGENT_CHAT_REAL_E2E=PASS\n'
cat "$PROBE"
