#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="${APEXTERM_APP_BUNDLE:-$ROOT/.artifacts/ApexTerm.app}"
TMP_ROOT="$(mktemp -d /tmp/apexterm-quick-e2e.XXXXXX)"
SUPPORT="$TMP_ROOT/support"
PROBE="$TMP_ROOT/probe.txt"
SERVER="apexterm-quick-probe-$$"

cleanup() {
  pkill -x ApexTerm 2>/dev/null || true
  tmux -L "$SERVER" kill-server 2>/dev/null || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT INT TERM

mkdir -p "$SUPPORT"
pkill -x ApexTerm 2>/dev/null || true
sleep 0.3
launchctl setenv APEXTERM_SUPPORT_DIRECTORY "$SUPPORT"
launchctl setenv APEXTERM_TMUX_SERVER "$SERVER"
launchctl setenv APEXTERM_QUICK_TERMINAL_PROBE_FILE "$PROBE"
open "$APP"

for _ in $(seq 1 300); do
  [[ -f "$PROBE" ]] && break
  sleep 0.05
done

launchctl unsetenv APEXTERM_SUPPORT_DIRECTORY
launchctl unsetenv APEXTERM_TMUX_SERVER
launchctl unsetenv APEXTERM_QUICK_TERMINAL_PROBE_FILE

[[ -f "$PROBE" ]]
grep -Fq 'groups=2' "$PROBE"
grep -Fq 'tabs=3' "$PROBE"
grep -Fq 'split=1' "$PROBE"
grep -Fq 'named_tmux=1' "$PROBE"
grep -Fq 'tab_reorder=1' "$PROBE"
grep -Fq 'center_drop=1' "$PROBE"
grep -Fq 'close_tab=1' "$PROBE"
grep -Fq 'persisted=1' "$PROBE"
tmux -L "$SERVER" has-session -t probe-session

print -r -- 'QUICK_TERMINAL_E2E=PASS'
cat "$PROBE"
