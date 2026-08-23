#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="${APEXTERM_APP_BUNDLE:-$ROOT/.artifacts/ApexTerm.app}"
EXECUTABLE="$APP/Contents/MacOS/ApexTerm"
TMP_ROOT="$(mktemp -d /tmp/apexterm-column-tabs-drag.XXXXXX)"
CURRENT_PID=""
CASE_SUPPORT=""
CASE_COLUMN_PROBE=""
CASE_DRAG_PROBE=""
CASE_APP_LOG=""

terminate_preview_processes() {
  local pid
  for pid in $(pgrep -f "$EXECUTABLE" 2>/dev/null || true); do
    kill "$pid" 2>/dev/null || true
  done
  for _ in {1..100}; do
    pgrep -f "$EXECUTABLE" >/dev/null 2>&1 || return 0
    sleep 0.05
  done
  return 1
}

terminate_current_process() {
  if [[ -n "$CURRENT_PID" ]] && kill -0 "$CURRENT_PID" 2>/dev/null; then
    kill "$CURRENT_PID" 2>/dev/null || true
    for _ in {1..100}; do
      kill -0 "$CURRENT_PID" 2>/dev/null || break
      sleep 0.05
    done
  fi
  CURRENT_PID=""
}

cleanup() {
  terminate_current_process
  terminate_preview_processes 2>/dev/null || true
  rm -rf "$TMP_ROOT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

column_json() {
  local node_path="$1"
  jq -c "$node_path | (.column._0 // .column)" "$2"
}

column_count() {
  jq '[.. | objects | select(has("column"))] | length' "$1"
}

launch_case() {
  local case_name="$1"
  local case_root="$TMP_ROOT/$case_name"
  CASE_SUPPORT="$case_root/support"
  CASE_COLUMN_PROBE="$case_root/column-tabs.txt"
  CASE_DRAG_PROBE="$case_root/drag.json"
  CASE_APP_LOG="$case_root/app.log"

  terminate_preview_processes
  mkdir -p "$CASE_SUPPORT"
  APEXTERM_SUPPORT_DIRECTORY="$CASE_SUPPORT" \
  APEXTERM_COLUMN_TABS_PROBE_FILE="$CASE_COLUMN_PROBE" \
  APEXTERM_NATIVE_PANE_DRAG_PROBE_FILE="$CASE_DRAG_PROBE" \
    "$EXECUTABLE" \
      -ApplePersistenceIgnoreState YES \
      -NSQuitAlwaysKeepsWindows NO \
      >"$CASE_APP_LOG" 2>&1 &
  CURRENT_PID="$!"

  for _ in {1..240}; do
    kill -0 "$CURRENT_PID" 2>/dev/null && break
    sleep 0.05
  done
  if [[ -z "$CURRENT_PID" ]]; then
    print -u2 -r -- "Preview ApexTerm failed to launch for $case_name"
    tail -100 "$CASE_APP_LOG" >&2 || true
    return 1
  fi

  for _ in {1..300}; do
    if [[ -f "$CASE_COLUMN_PROBE" ]] \
      && [[ -f "$CASE_DRAG_PROBE" ]] \
      && [[ "$(jq '.handles | length' "$CASE_DRAG_PROBE" 2>/dev/null || echo 0)" -ge 3 ]] \
      && [[ "$(jq '.targets | length' "$CASE_DRAG_PROBE" 2>/dev/null || echo 0)" -ge 2 ]]; then
      break
    fi
    kill -0 "$CURRENT_PID" 2>/dev/null || {
      print -u2 -r -- "Preview ApexTerm exited during $case_name"
      tail -100 "$CASE_APP_LOG" >&2 || true
      return 1
    }
    sleep 0.05
  done

  for expected in \
    'two_columns=1' \
    'focused_plus_visible=1' \
    'nonfocused_plus_hidden=1' \
    'plus_press=1' \
    'column_count_stable=1' \
    'tab_count_incremented=1' \
    'tab_added_inside_focused_column=1' \
    'new_selected_tab_plus_visible=1'
  do
    grep -Fqx "$expected" "$CASE_COLUMN_PROBE"
  done
  [[ "$(jq '.handles | length' "$CASE_DRAG_PROBE")" -ge 3 ]]
  [[ "$(jq '.targets | length' "$CASE_DRAG_PROBE")" -ge 2 ]]
  jq -e '[.handles[].width] | all(. <= 100)' "$CASE_DRAG_PROBE" >/dev/null
  sleep 0.4
}

front_preview() {
  osascript -e "tell application \"System Events\" to set frontmost of first application process whose unix id is $CURRENT_PID to true"
  sleep 0.6
}

drag_from_to() {
  local source_x="$1"
  local source_y="$2"
  local target_x="$3"
  local target_y="$4"
  front_preview
  cliclick "c:$source_x,$source_y"
  sleep 0.2
  cliclick -e 5 -w 90 \
    "m:$source_x,$source_y" \
    "dd:$source_x,$source_y" \
    "m:$((source_x + 14)),$source_y" \
    "m:$target_x,$target_y" \
    "du:$target_x,$target_y"
}

wait_for_layout_change() {
  local file="$1"
  local before="$2"
  for _ in {1..160}; do
    local after="$(jq -c '.workspaces[0].layout' "$file" 2>/dev/null || true)"
    [[ -n "$after" && "$after" != "$before" ]] && return 0
    sleep 0.05
  done
  return 1
}

wait_for_drag_entries() {
  local probe="$1"
  local handle_id="$2"
  local target_id="$3"
  for _ in {1..160}; do
    if jq -e \
      --arg handle "$handle_id" \
      --arg target "$target_id" \
      '(.handles[$handle].x // null) != null
       and (.handles[$handle].width // 0) > 0
       and (.targets[$target].x // null) != null
       and (.targets[$target].width // 0) > 0' \
      "$probe" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.05
  done
  print -u2 -r -- "DRAG_ENTRIES_TIMEOUT handle=$handle_id target=$target_id"
  jq -c \
    --arg handle "$handle_id" \
    --arg target "$target_id" \
    '{handle: .handles[$handle], target: .targets[$target]}' \
    "$probe" >&2 2>/dev/null || true
  return 1
}

wait_for_local_side_split_widths() {
  local probe="$1"
  local first_id="$2"
  local second_id="$3"
  local untouched_id="$4"
  for _ in {1..160}; do
    if jq -e \
      --arg first "$first_id" \
      --arg second "$second_id" \
      --arg untouched "$untouched_id" \
      '(.targets[$first].width // 0) as $a
       | (.targets[$second].width // 0) as $b
       | (.targets[$untouched].width // 0) as $u
       | $a > 0 and $b > 0 and $u > 0
       and (($a - $b) | fabs) <= 24
       and ((($a + $b) - $u) | fabs) <= 32' \
      "$probe" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.05
  done
  print -u2 -r -- "LOCAL_SIDE_WIDTHS_TIMEOUT first=$first_id second=$second_id untouched=$untouched_id"
  jq -c \
    --arg first "$first_id" \
    --arg second "$second_id" \
    --arg untouched "$untouched_id" \
    '{first: .targets[$first], second: .targets[$second], untouched: .targets[$untouched]}' \
    "$probe" >&2 2>/dev/null || true
  return 1
}

wait_for_local_top_split_geometry() {
  local probe="$1"
  local top_id="$2"
  local bottom_id="$3"
  local untouched_id="$4"
  for _ in {1..160}; do
    if jq -e \
      --arg top "$top_id" \
      --arg bottom "$bottom_id" \
      --arg untouched "$untouched_id" \
      '(.targets[$top]) as $t
       | (.targets[$bottom]) as $b
       | (.targets[$untouched]) as $u
       | ($t.width // 0) > 0 and ($b.width // 0) > 0 and ($u.width // 0) > 0
       and (($t.width - $b.width) | fabs) <= 24
       and (($t.width - $u.width) | fabs) <= 28
       and (($t.height - $b.height) | fabs) <= 28
       and $u.height >= ($t.height * 1.55)' \
      "$probe" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.05
  done
  print -u2 -r -- "LOCAL_TOP_GEOMETRY_TIMEOUT top=$top_id bottom=$bottom_id untouched=$untouched_id"
  jq -c \
    --arg top "$top_id" \
    --arg bottom "$bottom_id" \
    --arg untouched "$untouched_id" \
    '{top: .targets[$top], bottom: .targets[$bottom], untouched: .targets[$untouched]}' \
    "$probe" >&2 2>/dev/null || true
  return 1
}

wait_for_absorbed_target_width() {
  local probe="$1"
  local survivor_id="$2"
  local target_id="$3"
  for _ in {1..160}; do
    if jq -e \
      --arg survivor "$survivor_id" \
      --arg target "$target_id" \
      '(.targets[$survivor].width // 0) as $s
       | (.targets[$target].width // 0) as $t
       | $s > 0 and $t > 0
       and (($t - (3 * $s)) | fabs) <= 48' \
      "$probe" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.05
  done
  print -u2 -r -- "ABSORBED_TARGET_WIDTH_TIMEOUT survivor=$survivor_id target=$target_id"
  jq -c \
    --arg survivor "$survivor_id" \
    --arg target "$target_id" \
    '{survivor: .targets[$survivor], target: .targets[$target]}' \
    "$probe" >&2 2>/dev/null || true
  return 1
}

drag_and_wait_for_layout_change() {
  local file="$1"
  local before="$2"
  local source_x="$3"
  local source_y="$4"
  local target_x="$5"
  local target_y="$6"

  drag_from_to "$source_x" "$source_y" "$target_x" "$target_y"
  wait_for_layout_change "$file" "$before" && return 0

  sleep 0.4
  drag_from_to "$source_x" "$source_y" "$target_x" "$target_y"
  wait_for_layout_change "$file" "$before"
}

run_case() {
  local case_name="$1"
  local region="${2:-}"
  local support column_probe drag_probe app_log
  launch_case "$case_name"
  support="$CASE_SUPPORT"
  column_probe="$CASE_COLUMN_PROBE"
  drag_probe="$CASE_DRAG_PROBE"
  app_log="$CASE_APP_LOG"
  local workspace_file="$support/workspaces.json"

  local first_column second_column first_id base_right_id extra_right_id
  first_column="$(column_json '.workspaces[0].layout.split.first' "$workspace_file")"
  second_column="$(column_json '.workspaces[0].layout.split.second' "$workspace_file")"
  first_id="$(print -r -- "$first_column" | jq -r '.sessionIDs[0]')"
  base_right_id="$(print -r -- "$second_column" | jq -r '.sessionIDs[0]')"
  extra_right_id="$(print -r -- "$second_column" | jq -r '.sessionIDs[1]')"
  [[ -n "$first_id" && "$first_id" != null ]]
  [[ -n "$base_right_id" && "$base_right_id" != null ]]
  [[ -n "$extra_right_id" && "$extra_right_id" != null ]]
  [[ "$extra_right_id" != "$base_right_id" ]]

  local source_x source_y target_x target_y before_layout
  source_x="$(jq -r --arg id "$extra_right_id" '.handles[$id] | (.x + .width / 2) | floor' "$drag_probe")"
  source_y="$(jq -r --arg id "$extra_right_id" '.handles[$id] | (.y + .height / 2) | floor' "$drag_probe")"
  before_layout="$(jq -c '.workspaces[0].layout' "$workspace_file")"

  if [[ "$case_name" == reorder ]]; then
    target_x="$(jq -r --arg id "$base_right_id" '.handles[$id] | (.x + .width * 0.12) | floor' "$drag_probe")"
    target_y="$(jq -r --arg id "$base_right_id" '.handles[$id] | (.y + .height / 2) | floor' "$drag_probe")"
    drag_and_wait_for_layout_change \
      "$workspace_file" "$before_layout" \
      "$source_x" "$source_y" "$target_x" "$target_y"
    local reordered
    reordered="$(column_json '.workspaces[0].layout.split.second' "$workspace_file")"
    [[ "$(print -r -- "$reordered" | jq -r '.sessionIDs[0]')" == "$extra_right_id" ]]
    [[ "$(print -r -- "$reordered" | jq -r '.sessionIDs[1]')" == "$base_right_id" ]]
    [[ "$(column_count "$workspace_file")" -eq 2 ]]
    printf 'TERMINAL_COLUMN_TAB_REORDER_E2E=PASS\n'
  else
    local target_session_id="$first_id"
    case "$region" in
      center)
        target_x="$(jq -r --arg id "$target_session_id" '.targets[$id] | (.x + .width / 2) | floor' "$drag_probe")"
        target_y="$(jq -r --arg id "$target_session_id" '.targets[$id] | (.y + .height / 2) | floor' "$drag_probe")"
        ;;
      left)
        target_x="$(jq -r --arg id "$target_session_id" '.targets[$id] | (.x + .width * 0.08) | floor' "$drag_probe")"
        target_y="$(jq -r --arg id "$target_session_id" '.targets[$id] | (.y + .height / 2) | floor' "$drag_probe")"
        ;;
      right)
        target_x="$(jq -r --arg id "$target_session_id" '.targets[$id] | (.x + .width * 0.92) | floor' "$drag_probe")"
        target_y="$(jq -r --arg id "$target_session_id" '.targets[$id] | (.y + .height / 2) | floor' "$drag_probe")"
        ;;
      top)
        target_x="$(jq -r --arg id "$target_session_id" '.targets[$id] | (.x + .width / 2) | floor' "$drag_probe")"
        target_y="$(jq -r --arg id "$target_session_id" '.targets[$id] | (.y + .height * 0.08) | floor' "$drag_probe")"
        ;;
      bottom)
        target_x="$(jq -r --arg id "$target_session_id" '.targets[$id] | (.x + .width / 2) | floor' "$drag_probe")"
        target_y="$(jq -r --arg id "$target_session_id" '.targets[$id] | (.y + .height * 0.92) | floor' "$drag_probe")"
        ;;
      *)
        return 2
        ;;
    esac

    drag_and_wait_for_layout_change \
      "$workspace_file" "$before_layout" \
      "$source_x" "$source_y" "$target_x" "$target_y"

    if [[ "$region" == center ]]; then
      [[ "$(column_count "$workspace_file")" -eq 2 ]]
      local moved_target moved_source
      moved_target="$(column_json '.workspaces[0].layout.split.first' "$workspace_file")"
      moved_source="$(column_json '.workspaces[0].layout.split.second' "$workspace_file")"
      [[ "$(print -r -- "$moved_target" | jq -r --arg id "$extra_right_id" '.sessionIDs | index($id) != null')" == true ]]
      [[ "$(print -r -- "$moved_target" | jq -r --arg id "$first_id" '.sessionIDs | index($id) != null')" == true ]]
      [[ "$(print -r -- "$moved_source" | jq -r '.sessionIDs | length')" -eq 1 ]]
      [[ "$(print -r -- "$moved_source" | jq -r '.sessionIDs[0]')" == "$base_right_id" ]]
      printf 'TERMINAL_COLUMN_CENTER_MOVE_E2E=PASS\n'
    else
      [[ "$(column_count "$workspace_file")" -eq 3 ]]
      local nested_axis nested_first nested_second
      nested_axis="$(jq -r '.workspaces[0].layout.split.first.split.axis' "$workspace_file")"
      nested_first="$(column_json '.workspaces[0].layout.split.first.split.first' "$workspace_file")"
      nested_second="$(column_json '.workspaces[0].layout.split.first.split.second' "$workspace_file")"
      case "$region" in
        left)
          [[ "$nested_axis" == vertical ]]
          [[ "$(print -r -- "$nested_first" | jq -r '.sessionIDs[0]')" == "$extra_right_id" ]]
          [[ "$(print -r -- "$nested_second" | jq -r '.sessionIDs[0]')" == "$first_id" ]]
          wait_for_local_side_split_widths \
            "$drag_probe" "$extra_right_id" "$first_id" "$base_right_id"
          printf 'TERMINAL_COLUMN_LOCAL_WIDTHS_LEFT_E2E=PASS\n'
          ;;
        right)
          [[ "$nested_axis" == vertical ]]
          [[ "$(print -r -- "$nested_first" | jq -r '.sessionIDs[0]')" == "$first_id" ]]
          [[ "$(print -r -- "$nested_second" | jq -r '.sessionIDs[0]')" == "$extra_right_id" ]]
          wait_for_local_side_split_widths \
            "$drag_probe" "$first_id" "$extra_right_id" "$base_right_id"
          printf 'TERMINAL_COLUMN_LOCAL_WIDTHS_RIGHT_E2E=PASS\n'
          ;;
        top)
          [[ "$nested_axis" == horizontal ]]
          [[ "$(print -r -- "$nested_first" | jq -r '.sessionIDs[0]')" == "$extra_right_id" ]]
          [[ "$(print -r -- "$nested_second" | jq -r '.sessionIDs[0]')" == "$first_id" ]]
          wait_for_local_top_split_geometry \
            "$drag_probe" "$extra_right_id" "$first_id" "$base_right_id"
          printf 'TERMINAL_COLUMN_LOCAL_GEOMETRY_TOP_E2E=PASS\n'
          ;;
        bottom)
          [[ "$nested_axis" == horizontal ]]
          [[ "$(print -r -- "$nested_first" | jq -r '.sessionIDs[0]')" == "$first_id" ]]
          [[ "$(print -r -- "$nested_second" | jq -r '.sessionIDs[0]')" == "$extra_right_id" ]]
          wait_for_local_top_split_geometry \
            "$drag_probe" "$first_id" "$extra_right_id" "$base_right_id"
          printf 'TERMINAL_COLUMN_LOCAL_GEOMETRY_BOTTOM_E2E=PASS\n'
          ;;
      esac
      printf 'TERMINAL_COLUMN_EDGE_SPLIT_%s_E2E=PASS\n' "${region:u}"
    fi
  fi

  terminate_current_process
  rm -rf "${support:h}" 2>/dev/null || true
  sleep 0.7
}

run_same_column_left_case() {
  local case_name="same-left"
  local support drag_probe workspace_file
  launch_case "$case_name"
  support="$CASE_SUPPORT"
  drag_probe="$CASE_DRAG_PROBE"
  workspace_file="$support/workspaces.json"

  local first_column second_column first_id base_right_id extra_right_id
  first_column="$(column_json '.workspaces[0].layout.split.first' "$workspace_file")"
  second_column="$(column_json '.workspaces[0].layout.split.second' "$workspace_file")"
  first_id="$(print -r -- "$first_column" | jq -r '.sessionIDs[0]')"
  base_right_id="$(print -r -- "$second_column" | jq -r '.sessionIDs[0]')"
  extra_right_id="$(print -r -- "$second_column" | jq -r '.sessionIDs[1]')"

  local source_x source_y target_x target_y before_layout
  source_x="$(jq -r --arg id "$extra_right_id" '.handles[$id] | (.x + .width / 2) | floor' "$drag_probe")"
  source_y="$(jq -r --arg id "$extra_right_id" '.handles[$id] | (.y + .height / 2) | floor' "$drag_probe")"
  target_x="$(jq -r --arg id "$first_id" '.targets[$id] | (.x + .width / 2) | floor' "$drag_probe")"
  target_y="$(jq -r --arg id "$first_id" '.targets[$id] | (.y + .height / 2) | floor' "$drag_probe")"
  before_layout="$(jq -c '.workspaces[0].layout' "$workspace_file")"
  drag_and_wait_for_layout_change \
    "$workspace_file" "$before_layout" \
    "$source_x" "$source_y" "$target_x" "$target_y"

  [[ "$(column_count "$workspace_file")" -eq 2 ]]
  local left_after_center right_after_center
  left_after_center="$(column_json '.workspaces[0].layout.split.first' "$workspace_file")"
  right_after_center="$(column_json '.workspaces[0].layout.split.second' "$workspace_file")"
  [[ "$(print -r -- "$left_after_center" | jq -r --arg id "$extra_right_id" '.sessionIDs | index($id) != null')" == true ]]
  [[ "$(print -r -- "$right_after_center" | jq -r '.sessionIDs[0]')" == "$base_right_id" ]]

  sleep 0.5
  source_x="$(jq -r --arg id "$extra_right_id" '.handles[$id] | (.x + .width / 2) | floor' "$drag_probe")"
  source_y="$(jq -r --arg id "$extra_right_id" '.handles[$id] | (.y + .height / 2) | floor' "$drag_probe")"
  target_x="$(jq -r --arg id "$extra_right_id" '.targets[$id] | (.x + .width * 0.08) | floor' "$drag_probe")"
  target_y="$(jq -r --arg id "$extra_right_id" '.targets[$id] | (.y + .height / 2) | floor' "$drag_probe")"
  before_layout="$(jq -c '.workspaces[0].layout' "$workspace_file")"
  drag_and_wait_for_layout_change \
    "$workspace_file" "$before_layout" \
    "$source_x" "$source_y" "$target_x" "$target_y"

  [[ "$(column_count "$workspace_file")" -eq 3 ]]
  local nested_axis nested_first nested_second final_right
  nested_axis="$(jq -r '.workspaces[0].layout.split.first.split.axis' "$workspace_file")"
  nested_first="$(column_json '.workspaces[0].layout.split.first.split.first' "$workspace_file")"
  nested_second="$(column_json '.workspaces[0].layout.split.first.split.second' "$workspace_file")"
  final_right="$(column_json '.workspaces[0].layout.split.second' "$workspace_file")"
  [[ "$nested_axis" == vertical ]]
  [[ "$(print -r -- "$nested_first" | jq -r '.sessionIDs[0]')" == "$extra_right_id" ]]
  [[ "$(print -r -- "$nested_second" | jq -r '.sessionIDs[0]')" == "$first_id" ]]
  [[ "$(print -r -- "$final_right" | jq -r '.sessionIDs[0]')" == "$base_right_id" ]]
  jq -e --arg id "$extra_right_id" '.events | index("region:" + $id + ":left") != null' "$drag_probe" >/dev/null
  jq -e --arg id "$extra_right_id" '.events | index("drop:" + $id + ":" + $id + ":left") != null' "$drag_probe" >/dev/null
  wait_for_local_side_split_widths \
    "$drag_probe" "$extra_right_id" "$first_id" "$base_right_id"
  printf 'TERMINAL_COLUMN_SAME_COLUMN_LEFT_EDGE_E2E=PASS\n'
  printf 'TERMINAL_COLUMN_LOCAL_WIDTHS_SAME_LEFT_E2E=PASS\n'

  sleep 0.5
  source_x="$(jq -r --arg id "$extra_right_id" '.handles[$id] | (.x + .width / 2) | floor' "$drag_probe")"
  source_y="$(jq -r --arg id "$extra_right_id" '.handles[$id] | (.y + .height / 2) | floor' "$drag_probe")"
  target_x="$(jq -r --arg id "$base_right_id" '.targets[$id] | (.x + .width / 2) | floor' "$drag_probe")"
  target_y="$(jq -r --arg id "$base_right_id" '.targets[$id] | (.y + .height / 2) | floor' "$drag_probe")"
  before_layout="$(jq -c '.workspaces[0].layout' "$workspace_file")"
  drag_and_wait_for_layout_change \
    "$workspace_file" "$before_layout" \
    "$source_x" "$source_y" "$target_x" "$target_y"

  [[ "$(column_count "$workspace_file")" -eq 2 ]]
  [[ "$(jq -r '.workspaces[0].layout.split.axis' "$workspace_file")" == vertical ]]
  local absorbed_ratio absorbed_left absorbed_right absorbed_visible_id
  absorbed_ratio="$(jq -r '.workspaces[0].layout.split.ratio' "$workspace_file")"
  absorbed_left="$(column_json '.workspaces[0].layout.split.first' "$workspace_file")"
  absorbed_right="$(column_json '.workspaces[0].layout.split.second' "$workspace_file")"
  absorbed_visible_id="$(print -r -- "$absorbed_right" | jq -r '.selectedSessionID')"
  [[ "$(awk -v r="$absorbed_ratio" 'BEGIN { print (r > 0.23 && r < 0.27) ? 1 : 0 }')" -eq 1 ]]
  [[ "$(print -r -- "$absorbed_left" | jq -r '.sessionIDs[0]')" == "$first_id" ]]
  [[ "$(print -r -- "$absorbed_right" | jq -r --arg id "$extra_right_id" '.sessionIDs | index($id) != null')" == true ]]
  [[ "$(print -r -- "$absorbed_right" | jq -r --arg id "$base_right_id" '.sessionIDs | index($id) != null')" == true ]]
  [[ "$absorbed_visible_id" == "$extra_right_id" ]]
  wait_for_absorbed_target_width "$drag_probe" "$first_id" "$absorbed_visible_id"
  printf 'TERMINAL_COLUMN_CENTER_MERGE_ABSORBS_SOURCE_WIDTH_E2E=PASS\n'

  terminate_current_process
  rm -rf "${support:h}" 2>/dev/null || true
  sleep 0.7
}

run_same_column_top_case() {
  local case_name="same-top"
  local support drag_probe workspace_file
  launch_case "$case_name"
  support="$CASE_SUPPORT"
  drag_probe="$CASE_DRAG_PROBE"
  workspace_file="$support/workspaces.json"

  local first_column second_column first_id base_right_id extra_right_id
  first_column="$(column_json '.workspaces[0].layout.split.first' "$workspace_file")"
  second_column="$(column_json '.workspaces[0].layout.split.second' "$workspace_file")"
  first_id="$(print -r -- "$first_column" | jq -r '.sessionIDs[0]')"
  base_right_id="$(print -r -- "$second_column" | jq -r '.sessionIDs[0]')"
  extra_right_id="$(print -r -- "$second_column" | jq -r '.sessionIDs[1]')"

  local source_x source_y target_x target_y before_layout
  wait_for_drag_entries "$drag_probe" "$extra_right_id" "$first_id"
  source_x="$(jq -r --arg id "$extra_right_id" '.handles[$id] | (.x + .width / 2) | floor' "$drag_probe")"
  source_y="$(jq -r --arg id "$extra_right_id" '.handles[$id] | (.y + .height / 2) | floor' "$drag_probe")"
  target_x="$(jq -r --arg id "$first_id" '.targets[$id] | (.x + .width / 2) | floor' "$drag_probe")"
  target_y="$(jq -r --arg id "$first_id" '.targets[$id] | (.y + .height / 2) | floor' "$drag_probe")"
  before_layout="$(jq -c '.workspaces[0].layout' "$workspace_file")"
  drag_and_wait_for_layout_change \
    "$workspace_file" "$before_layout" \
    "$source_x" "$source_y" "$target_x" "$target_y"

  [[ "$(column_count "$workspace_file")" -eq 2 ]]
  sleep 0.5
  wait_for_drag_entries "$drag_probe" "$extra_right_id" "$extra_right_id"
  source_x="$(jq -r --arg id "$extra_right_id" '.handles[$id] | (.x + .width / 2) | floor' "$drag_probe")"
  source_y="$(jq -r --arg id "$extra_right_id" '.handles[$id] | (.y + .height / 2) | floor' "$drag_probe")"
  target_x="$(jq -r --arg id "$extra_right_id" '.targets[$id] | (.x + .width / 2) | floor' "$drag_probe")"
  target_y="$(jq -r --arg id "$extra_right_id" '.targets[$id] | (.y + .height * 0.08) | floor' "$drag_probe")"
  before_layout="$(jq -c '.workspaces[0].layout' "$workspace_file")"
  drag_and_wait_for_layout_change \
    "$workspace_file" "$before_layout" \
    "$source_x" "$source_y" "$target_x" "$target_y"

  [[ "$(column_count "$workspace_file")" -eq 3 ]]
  [[ "$(jq -r '.workspaces[0].layout.split.axis' "$workspace_file")" == vertical ]]
  [[ "$(jq -r '.workspaces[0].layout.split.first.split.axis' "$workspace_file")" == horizontal ]]
  local top_column bottom_column final_right
  top_column="$(column_json '.workspaces[0].layout.split.first.split.first' "$workspace_file")"
  bottom_column="$(column_json '.workspaces[0].layout.split.first.split.second' "$workspace_file")"
  final_right="$(column_json '.workspaces[0].layout.split.second' "$workspace_file")"
  [[ "$(print -r -- "$top_column" | jq -r '.sessionIDs[0]')" == "$extra_right_id" ]]
  [[ "$(print -r -- "$bottom_column" | jq -r '.sessionIDs[0]')" == "$first_id" ]]
  [[ "$(print -r -- "$final_right" | jq -r '.sessionIDs[0]')" == "$base_right_id" ]]
  wait_for_local_top_split_geometry \
    "$drag_probe" "$extra_right_id" "$first_id" "$base_right_id"
  printf 'TERMINAL_COLUMN_SAME_COLUMN_TOP_EDGE_E2E=PASS\n'
  printf 'TERMINAL_COLUMN_SAME_COLUMN_TOP_LOCAL_GEOMETRY_E2E=PASS\n'

  terminate_current_process
  rm -rf "${support:h}" 2>/dev/null || true
  sleep 0.7
}

[[ -d "$APP" ]]
[[ -x "$EXECUTABLE" ]]
command -v cliclick >/dev/null
command -v jq >/dev/null

typeset -a requested_cases
if [[ -n "${APEXTERM_DRAG_CASES:-}" ]]; then
  requested_cases=("${(@s: :)APEXTERM_DRAG_CASES}")
else
  requested_cases=(reorder center left right top bottom same-left same-top)
fi

for case_name in "${requested_cases[@]}"; do
  case "$case_name" in
    reorder)
      run_case reorder
      ;;
    center|left|right|top|bottom)
      run_case "$case_name" "$case_name"
      ;;
    same-left)
      run_same_column_left_case
      ;;
    same-top)
      run_same_column_top_case
      ;;
    *)
      print -u2 -r -- "Unknown APEXTERM_DRAG_CASES entry: $case_name"
      exit 2
      ;;
  esac
done

printf 'COLUMN_FOCUSED_PLUS_UI_E2E=PASS\n'
printf 'NATIVE_PANE_DRAG_E2E=PASS\n'
printf 'TERMINAL_COLUMN_TABS_E2E=PASS\n'
