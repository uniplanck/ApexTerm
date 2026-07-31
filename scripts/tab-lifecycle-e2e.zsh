#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="${APEXTERM_APP_BUNDLE:-/Applications/ApexTerm.app}"
RESTORE_APP="${APEXTERM_RESTORE_APP_BUNDLE:-$APP}"
TMP_ROOT="$(mktemp -d /tmp/apexterm-tab-lifecycle.XXXXXX)"
SUPPORT="$TMP_ROOT/support"
PROBE="$TMP_ROOT/tab-lifecycle-probe.txt"

cleanup() {
  launchctl unsetenv APEXTERM_SUPPORT_DIRECTORY 2>/dev/null || true
  launchctl unsetenv APEXTERM_TAB_LIFECYCLE_PROBE_FILE 2>/dev/null || true
  pkill -x ApexTerm 2>/dev/null || true
  pkill -f "$SUPPORT/shell-integration/tmux.conf" 2>/dev/null || true
  sleep 0.2
  open "$RESTORE_APP" >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT INT TERM

mkdir -p "$SUPPORT"
pkill -x ApexTerm 2>/dev/null || true
sleep 0.3
launchctl setenv APEXTERM_SUPPORT_DIRECTORY "$SUPPORT"
launchctl setenv APEXTERM_TAB_LIFECYCLE_PROBE_FILE "$PROBE"
open "$APP"

for _ in $(seq 1 400); do
  [[ -f "$PROBE" ]] && break
  sleep 0.05
done
[[ -f "$PROBE" ]]

for expected in \
  'close_cycles=20' \
  'terminal_runtime_recovered=1' \
  'terminal_focus_recovered=1' \
  'removed_runtime_released=1' \
  'composer_focus_recovered=1' \
  'terminal_focus_after_chat_close=1'
do
  grep -Fqx "$expected" "$PROBE"
done

printf 'TAB_LIFECYCLE_E2E=PASS\n'
cat "$PROBE"
