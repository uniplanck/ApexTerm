#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="${APEXTERM_APP_BUNDLE:-/Applications/ApexTerm.app}"
RESTORE_APP="${APEXTERM_RESTORE_APP_BUNDLE:-$APP}"
TMP_ROOT="$(mktemp -d /tmp/apexterm-shortcut-actions.XXXXXX)"
SUPPORT="$TMP_ROOT/support"
PROBE="$TMP_ROOT/shortcut-actions-probe.txt"

cleanup() {
  launchctl unsetenv APEXTERM_SUPPORT_DIRECTORY 2>/dev/null || true
  launchctl unsetenv APEXTERM_SHORTCUT_ACTIONS_PROBE_FILE 2>/dev/null || true
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
launchctl setenv APEXTERM_SHORTCUT_ACTIONS_PROBE_FILE "$PROBE"
open "$APP"

for _ in $(seq 1 500); do
  [[ -f "$PROBE" ]] && break
  sleep 0.05
done
[[ -f "$PROBE" ]]

for expected in \
  'window_found=1' \
  'defaults_configured=1' \
  'next_shortcut_handled=1' \
  'next_tab_selected=1' \
  'previous_shortcut_handled=1' \
  'previous_tab_selected=1' \
  'direct_shortcut_handled=1' \
  'direct_tab_selected=1' \
  'pane_four_shortcut_handled=1' \
  'pane_four_selected=1' \
  'pane_two_shortcut_handled=1' \
  'pane_two_selected=1' \
  'copy_shortcut_handled=1' \
  'latest_output_copied=1' \
  'copy_notice_state=1' \
  'copy_notice_visible=1' \
  'copy_notice_dismissed=1' \
  'transcript_shortcuts_handled=1' \
  'transcript_cycle=1' \
  'history_shortcut_handled=1' \
  'history_toggled=1' \
  'left_sidebar_shortcut_handled=1' \
  'left_sidebar_toggled=1' \
  'right_sidebar_shortcut_handled=1' \
  'right_sidebar_toggled=1' \
  'new_agent_shortcut_handled=1' \
  'new_agent_created=1'
do
  grep -Fqx "$expected" "$PROBE"
done

printf 'SHORTCUT_ACTIONS_E2E=PASS\n'
cat "$PROBE"
