#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="/Applications/ApexTerm.app"
TMP_ROOT="$(mktemp -d /tmp/apexterm-tmux-manager.XXXXXX)"
SUPPORT="$TMP_ROOT/support"
PROBE="$TMP_ROOT/tmux-manager-probe.txt"
TMUX_SERVER="apexterm-manager-e2e-${RANDOM}-${RANDOM}"

cleanup() {
  launchctl unsetenv APEXTERM_SUPPORT_DIRECTORY 2>/dev/null || true
  launchctl unsetenv APEXTERM_TMUX_SERVER 2>/dev/null || true
  launchctl unsetenv APEXTERM_TMUX_MANAGER_LOCAL_ONLY 2>/dev/null || true
  launchctl unsetenv APEXTERM_TMUX_MANAGER_PROBE_FILE 2>/dev/null || true
  pkill -x ApexTerm 2>/dev/null || true
  tmux -L "$TMUX_SERVER" kill-server 2>/dev/null || true
  sleep 0.25
  open "$APP" >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT INT TERM

mkdir -p "$SUPPORT"
pkill -x ApexTerm 2>/dev/null || true
sleep 0.25
launchctl setenv APEXTERM_SUPPORT_DIRECTORY "$SUPPORT"
launchctl setenv APEXTERM_TMUX_SERVER "$TMUX_SERVER"
launchctl setenv APEXTERM_TMUX_MANAGER_LOCAL_ONLY 1
launchctl setenv APEXTERM_TMUX_MANAGER_PROBE_FILE "$PROBE"
open "$APP"

for _ in {1..360}; do
  [[ -f "$PROBE" ]] && break
  sleep 0.05
done
[[ -f "$PROBE" ]]
for expected in \
  'manager_presented=1' \
  'local_session_listed=1' \
  'workspace_tmux_detected=1' \
  'session_killed=1' \
  'process_alive=1'
do
  grep -Fqx "$expected" "$PROBE"
done
pgrep -x ApexTerm >/dev/null
if tmux -L "$TMUX_SERVER" has-session -t tmux-manager-probe 2>/dev/null; then
  print -u2 'tmux manager probe session still exists'
  exit 1
fi

printf 'TMUX_MANAGER_E2E=PASS\n'
cat "$PROBE"
