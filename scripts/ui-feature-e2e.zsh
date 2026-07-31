#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="${APEXTERM_APP_BUNDLE:-/Applications/ApexTerm.app}"
RESTORE_APP="${APEXTERM_RESTORE_APP_BUNDLE:-$APP}"
TMP_ROOT="$(mktemp -d /tmp/apexterm-ui-feature.XXXXXX)"
SUPPORT="$TMP_ROOT/support"
PROBE="$TMP_ROOT/feature-probe.txt"
CTL="${APEXTERM_CTL_EXECUTABLE:-$ROOT/.build/release/apextermctl}"

cleanup() {
  launchctl unsetenv APEXTERM_SUPPORT_DIRECTORY 2>/dev/null || true
  launchctl unsetenv APEXTERM_UI_FEATURE_PROBE_FILE 2>/dev/null || true
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
launchctl setenv APEXTERM_UI_FEATURE_PROBE_FILE "$PROBE"
open "$APP"

for _ in $(seq 1 240); do
  [[ -f "$PROBE" ]] && break
  sleep 0.05
done
[[ -f "$PROBE" ]]
for expected in \
  'tab_reorder=1' \
  'tab_drop_intent=1' \
  'native_drag_payload=1' \
  'local_shell_without_tmux=1' \
  'plus_left_click_local=1' \
  'plus_right_click_menu=1' \
  'pane_header_move=1' \
  'pane_whole_swap=1' \
  'pane_drop_preview=1' \
  'pane_maximize=1' \
  'pane_navigation=1' \
  'history_search_action=1' \
  'history_search_view=1' \
  'history_filter=1' \
  'smart_paste=1' \
  'secure_input_action=1' \
  'auto_copy_command_output=1' \
  'auto_collapse_large_output=1' \
  'bounded_output_render=1' \
  'drop_split=1' \
  'drop_nested_tree=1' \
  'tab_merge_four_panes=1' \
  'mixed_tab_order=1' \
  'left_collapsed=1' \
  'right_collapsed=1' \
  'window_floating=1' \
  'compact_mode=1' \
  'rename_window=1' \
  'rename_tab=1' \
  'rename_group=1' \
  'local_shell_initial_number=1' \
  'local_shell_sequential_number=1' \
  'local_shell_gap_reuse=1' \
  'direct_workspace_rename=1' \
  'direct_terminal_rename=1' \
  'close_tab=1' \
  'named_tmux=1' \
  'agent_chat_created=1' \
  'agent_chat_target=1' \
  'agent_chat_draft=1' \
  'agent_chat_selected=1' \
  'agent_chat_performance=1' \
  'agent_chat_compact=1'
do
  grep -Fqx "$expected" "$PROBE"
done

status_json="$(APEXTERM_SUPPORT_DIRECTORY="$SUPPORT" "$CTL" status)"
named_session_id="$(print -r -- "$status_json" | ruby -rjson -e '
  j=JSON.parse(STDIN.read)
  session=j.fetch("sessions").find { |item| item["kind"] == "local-tmux:main-probe" }
  exit 1 unless session
  print session["id"]
')"
named_result="$(APEXTERM_SUPPORT_DIRECTORY="$SUPPORT" "$CTL" exec "$named_session_id" "printf 'NAMED_TMUX_AUTOMATION_OK\\n'")"
print -r -- "$named_result" | grep -Fq 'NAMED_TMUX_AUTOMATION_OK'
print -r -- "$named_result" | grep -Fq '[apexterm exit=0]'

printf 'UI_LAYOUT_FEATURE_E2E=PASS\n'
printf 'NAMED_TMUX_AUTOMATION_E2E=PASS\n'
cat "$PROBE"
