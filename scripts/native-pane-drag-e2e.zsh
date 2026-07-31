#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="/Applications/ApexTerm.app"
CTL="$ROOT/.build/release/apextermctl"
TMP_ROOT="$(mktemp -d /tmp/apexterm-native-pane-drag.XXXXXX)"

stop_app() {
  pkill -x ApexTerm 2>/dev/null || true
  for _ in {1..80}; do
    pgrep -x ApexTerm >/dev/null 2>&1 || return 0
    sleep 0.05
  done
  print -u2 -r -- "ApexTerm did not stop before the next drag case"
  return 1
}

cleanup() {
  launchctl unsetenv APEXTERM_SUPPORT_DIRECTORY 2>/dev/null || true
  launchctl unsetenv APEXTERM_NATIVE_PANE_DRAG_PROBE_FILE 2>/dev/null || true
  stop_app 2>/dev/null || true
  pkill -f "$TMP_ROOT/.*/support/shell-integration/tmux.conf" 2>/dev/null || true
  sleep 0.2
  open "$APP" >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

run_case() {
  local requested_region="$1"
  local case_root="$TMP_ROOT/$requested_region"
  local support="$case_root/support"
  local probe="$case_root/native-drag.json"
  local socket="$support/runtime/apexterm.sock"

  mkdir -p "$support"
  stop_app
  launchctl setenv APEXTERM_SUPPORT_DIRECTORY "$support"
  launchctl setenv APEXTERM_NATIVE_PANE_DRAG_PROBE_FILE "$probe"
  open "$APP"

  for _ in {1..240}; do
    [[ -S "$socket" ]] && break
    sleep 0.05
  done
  [[ -S "$socket" ]]

  local status_json initial_id
  status_json="$(APEXTERM_SUPPORT_DIRECTORY="$support" "$CTL" status)"
  initial_id="$(print -r -- "$status_json" | jq -r '.selectedSessionID')"
  [[ -n "$initial_id" && "$initial_id" != null ]]
  APEXTERM_SUPPORT_DIRECTORY="$support" "$CTL" split "$initial_id" vertical >/dev/null

  for _ in {1..240}; do
    if [[ -f "$probe" ]] && [[ "$(jq '.handles | length' "$probe" 2>/dev/null || echo 0)" -ge 2 ]]; then
      break
    fi
    sleep 0.05
  done
  [[ -f "$probe" ]]
  [[ "$(jq '.handles | length' "$probe")" -ge 2 ]]

  local first_id second_id source_id target_id event_region
  first_id="$(jq -r '.workspaces[0].layout.split.first.pane.sessionID' "$support/workspaces.json")"
  second_id="$(jq -r '.workspaces[0].layout.split.second.pane.sessionID' "$support/workspaces.json")"
  event_region="$requested_region"

  if [[ "$requested_region" == left ]]; then
    source_id="$second_id"
    target_id="$first_id"
  else
    source_id="$first_id"
    target_id="$second_id"
  fi

  local before_layout source_x source_y target_x target_y
  before_layout="$(jq -c '.workspaces[0].layout' "$support/workspaces.json")"
  source_x="$(jq -r --arg id "$source_id" '.handles[$id] | (.x + .width / 2) | floor' "$probe")"
  source_y="$(jq -r --arg id "$source_id" '.handles[$id] | (.y + .height / 2) | floor' "$probe")"

  case "$requested_region" in
    center)
      target_x="$(jq -r --arg id "$target_id" '.targets[$id] | (.x + .width / 2) | floor' "$probe")"
      target_y="$(jq -r --arg id "$target_id" '.targets[$id] | (.y + .height / 2) | floor' "$probe")"
      ;;
    left)
      target_x="$(jq -r --arg id "$target_id" '.targets[$id] | (.x + .width * 0.08) | floor' "$probe")"
      target_y="$(jq -r --arg id "$target_id" '.targets[$id] | (.y + .height / 2) | floor' "$probe")"
      ;;
    right)
      target_x="$(jq -r --arg id "$target_id" '.targets[$id] | (.x + .width * 0.92) | floor' "$probe")"
      target_y="$(jq -r --arg id "$target_id" '.targets[$id] | (.y + .height / 2) | floor' "$probe")"
      ;;
    top)
      target_x="$(jq -r --arg id "$target_id" '.targets[$id] | (.x + .width / 2) | floor' "$probe")"
      target_y="$(jq -r --arg id "$target_id" '.targets[$id] | (.y + .height * 0.08) | floor' "$probe")"
      ;;
    bottom)
      target_x="$(jq -r --arg id "$target_id" '.targets[$id] | (.x + .width / 2) | floor' "$probe")"
      target_y="$(jq -r --arg id "$target_id" '.targets[$id] | (.y + .height * 0.92) | floor' "$probe")"
      ;;
    *)
      return 2
      ;;
  esac

  osascript -e 'tell application "System Events" to tell process "ApexTerm" to set frontmost to true'
  sleep 0.15
  cliclick -e 5 -w 90 \
    "m:$source_x,$source_y" \
    "dd:$source_x,$source_y" \
    "m:$((source_x + 12)),$source_y" \
    "m:$target_x,$target_y" \
    "du:$target_x,$target_y"

  local events
  for _ in {1..160}; do
    events="$(jq -r '.events[]?' "$probe" 2>/dev/null || true)"
    print -r -- "$events" | grep -Fq "drop:${source_id}:${target_id}:${event_region}" && break
    sleep 0.05
  done
  sleep 0.3

  events="$(jq -r '.events[]?' "$probe")"
  local after_layout after_axis after_first after_second
  after_layout="$(jq -c '.workspaces[0].layout' "$support/workspaces.json")"
  after_axis="$(jq -r '.workspaces[0].layout.split.axis' "$support/workspaces.json")"
  after_first="$(jq -r '.workspaces[0].layout.split.first.pane.sessionID' "$support/workspaces.json")"
  after_second="$(jq -r '.workspaces[0].layout.split.second.pane.sessionID' "$support/workspaces.json")"

  print -r -- "$events" | grep -Fqx "drag-start:${source_id}"
  print -r -- "$events" | grep -Fqx "region:${target_id}:${event_region}"
  print -r -- "$events" | grep -Fqx "drop:${source_id}:${target_id}:${event_region}"
  [[ "$(print -r -- "$events" | grep -c '^drag-start:')" -eq 1 ]]
  [[ "$before_layout" != "$after_layout" ]]

  case "$requested_region" in
    center|right)
      [[ "$after_axis" == vertical ]]
      [[ "$after_first" == "$target_id" && "$after_second" == "$source_id" ]]
      ;;
    left)
      [[ "$after_axis" == vertical ]]
      [[ "$after_first" == "$source_id" && "$after_second" == "$target_id" ]]
      ;;
    top)
      [[ "$after_axis" == horizontal ]]
      [[ "$after_first" == "$source_id" && "$after_second" == "$target_id" ]]
      ;;
    bottom)
      [[ "$after_axis" == horizontal ]]
      [[ "$after_first" == "$target_id" && "$after_second" == "$source_id" ]]
      ;;
  esac

  printf 'NATIVE_PANE_DRAG_%s=PASS\n' "${requested_region:u}"
  launchctl unsetenv APEXTERM_SUPPORT_DIRECTORY
  launchctl unsetenv APEXTERM_NATIVE_PANE_DRAG_PROBE_FILE
  stop_app
  pkill -f "$support/shell-integration/tmux.conf" 2>/dev/null || true
  sleep 0.15
  rm -rf "$case_root"
}

for region in center left right top bottom; do
  run_case "$region"
done

printf 'NATIVE_PANE_DRAG_E2E=PASS\n'
