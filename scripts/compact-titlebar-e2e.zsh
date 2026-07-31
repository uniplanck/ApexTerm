#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="${APEXTERM_APP_BUNDLE:-/Applications/ApexTerm.app}"
RESTORE_APP="${APEXTERM_RESTORE_APP_BUNDLE:-$APP}"
TMP_ROOT="$(mktemp -d /tmp/apexterm-compact-titlebar.XXXXXX)"
SUPPORT="$TMP_ROOT/support"
PROBE="$TMP_ROOT/compact-titlebar-probe.txt"

cleanup() {
  launchctl unsetenv APEXTERM_SUPPORT_DIRECTORY 2>/dev/null || true
  launchctl unsetenv APEXTERM_COMPACT_TITLEBAR_PROBE_FILE 2>/dev/null || true
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
launchctl setenv APEXTERM_COMPACT_TITLEBAR_PROBE_FILE "$PROBE"
open "$APP"

for _ in $(seq 1 400); do
  [[ -f "$PROBE" ]] && break
  sleep 0.05
done
[[ -f "$PROBE" ]]

for expected in \
  'window_found=1' \
  'compact_toolbar_installed=1' \
  'toolbar_identifier=1' \
  'unified_compact_style=1' \
  'title_hidden=1' \
  'titlebar_new_tab=1' \
  'titlebar_window_drag=1' \
  'content_new_tab_removed=1' \
  'compact_pane_outline_suppressed=1' \
  'expanded_pane_outline_preserved=1' \
  'transcript_cycle_button_width_bounded=1' \
  'transcript_cycle_button_right_inset=1' \
  'compact_pane_header_top_padding=1' \
  'narrow_icon_tabs_rendered=1' \
  'narrow_separator_forced=1' \
  'wide_labels_rendered=1' \
  'wide_separator_hidden_by_setting=1' \
  'normal_separator_hidden=1' \
  'normal_separator_shown=1' \
  'titlebar_auto_updates=1' \
  'workspace_switch_cycles=40' \
  'agent_switch_cycles=40' \
  'titlebar_host_reused=1' \
  'titlebar_layout_stable=1' \
  'titlebar_content_updated=1' \
  'titlebar_host_fills_container=1' \
  'titlebar_vertical_gap_eliminated=1' \
  'expanded_toolbar_removed=1' \
  'expanded_title_restored=1'
do
  grep -Fqx "$expected" "$PROBE"
done

printf 'COMPACT_TITLEBAR_E2E=PASS\n'
cat "$PROBE"
