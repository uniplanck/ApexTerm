#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="/Applications/ApexTerm.app"
CTL="$ROOT/.build/release/apextermctl"
TMP_ROOT="$(mktemp -d /tmp/apexterm-terminal-persistence.XXXXXX)"
SUPPORT="$TMP_ROOT/support"
PROBE="$TMP_ROOT/persistence.log"
PROGRAMMATIC_PROBE="$TMP_ROOT/programmatic-input.txt"
MARKER="APT_TERMINAL_PERSISTENCE_${RANDOM}_${RANDOM}"
W1="$(uuidgen)"
W2="$(uuidgen)"
S1="$(uuidgen)"
S2="$(uuidgen)"

cleanup() {
  launchctl unsetenv APEXTERM_SUPPORT_DIRECTORY 2>/dev/null || true
  launchctl unsetenv APEXTERM_TERMINAL_PERSISTENCE_PROBE_FILE 2>/dev/null || true
  launchctl unsetenv APEXTERM_TERMINAL_PERSISTENCE_MARKER 2>/dev/null || true
  launchctl unsetenv APEXTERM_PROGRAMMATIC_INPUT_PROBE_FILE 2>/dev/null || true
  launchctl unsetenv APEXTERM_PROGRAMMATIC_INPUT_PROBE_MARKER 2>/dev/null || true
  pkill -x ApexTerm 2>/dev/null || true
  pkill -f "$SUPPORT/shell-integration/tmux.conf" 2>/dev/null || true
  sleep 0.25
  open "$APP" >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT INT TERM

mkdir -p "$SUPPORT"
jq -n \
  --arg w1 "$W1" --arg w2 "$W2" \
  --arg s1 "$S1" --arg s2 "$S2" \
  --arg home "$HOME" \
  '{
    schemaVersion: 1,
    workspaces: [
      {
        createdAt: 0,
        id: $w1,
        layout: {pane: {sessionID: $s1}},
        name: "Persistence One",
        rootDirectory: $home,
        updatedAt: 0
      },
      {
        createdAt: 0,
        id: $w2,
        layout: {pane: {sessionID: $s2}},
        name: "Persistence Two",
        rootDirectory: $home,
        updatedAt: 0
      }
    ],
    sessions: [
      {
        createdAt: 0,
        id: $s1,
        kind: {local: {}},
        state: "created",
        title: "Local Shell",
        workingDirectory: $home
      },
      {
        createdAt: 0,
        id: $s2,
        kind: {local: {}},
        state: "created",
        title: "Local Shell",
        workingDirectory: $home
      }
    ]
  }' > "$SUPPORT/workspaces.json"

pkill -x ApexTerm 2>/dev/null || true
sleep 0.3
launchctl setenv APEXTERM_SUPPORT_DIRECTORY "$SUPPORT"
launchctl setenv APEXTERM_TERMINAL_PERSISTENCE_PROBE_FILE "$PROBE"
launchctl setenv APEXTERM_TERMINAL_PERSISTENCE_MARKER "$MARKER"
launchctl setenv APEXTERM_PROGRAMMATIC_INPUT_PROBE_FILE "$PROGRAMMATIC_PROBE"
launchctl setenv APEXTERM_PROGRAMMATIC_INPUT_PROBE_MARKER "$MARKER"
open "$APP"

SOCKET="$SUPPORT/runtime/apexterm.sock"
for _ in $(seq 1 240); do
  [[ -S "$SOCKET" ]] && break
  sleep 0.05
done
[[ -S "$SOCKET" ]]

for _ in $(seq 1 240); do
  status_json="$(APEXTERM_SUPPORT_DIRECTORY="$SUPPORT" "$CTL" status 2>/dev/null || true)"
  state="$(print -r -- "$status_json" | jq -r --arg id "$S1" '.sessions[]? | select(.id == $id) | .state')"
  [[ "$state" == "attached" ]] && break
  sleep 0.05
done
[[ "$state" == "attached" ]]

for _ in $(seq 1 240); do
  [[ -f "$PROGRAMMATIC_PROBE" ]] \
    && grep -Fqx 'programmatic_input=1' "$PROGRAMMATIC_PROBE" \
    && grep -Fqx 'process=1' "$PROGRAMMATIC_PROBE" \
    && break
  sleep 0.05
done
[[ -f "$PROGRAMMATIC_PROBE" ]]
grep -Fqx 'programmatic_input=1' "$PROGRAMMATIC_PROBE"
grep -Fqx 'process=1' "$PROGRAMMATIC_PROBE"

APEXTERM_SUPPORT_DIRECTORY="$SUPPORT" "$CTL" workspace "$W2" >/dev/null
for _ in $(seq 1 240); do
  selected="$(APEXTERM_SUPPORT_DIRECTORY="$SUPPORT" "$CTL" status | jq -r '.selectedWorkspaceID')"
  [[ "$selected" == "$W2" ]] && grep -Fq "create:$S2" "$PROBE" 2>/dev/null && break
  sleep 0.05
done
[[ "$selected" == "$W2" ]]
for _ in $(seq 1 240); do
  grep -Fq "detach:$S1" "$PROBE" 2>/dev/null && break
  sleep 0.05
done

APEXTERM_SUPPORT_DIRECTORY="$SUPPORT" "$CTL" workspace "$W1" >/dev/null
for _ in $(seq 1 240); do
  selected="$(APEXTERM_SUPPORT_DIRECTORY="$SUPPORT" "$CTL" status | jq -r '.selectedWorkspaceID')"
  grep -Fq "reuse:$S1:buffer=1:" "$PROBE" 2>/dev/null && [[ "$selected" == "$W1" ]] && break
  sleep 0.05
done
[[ "$selected" == "$W1" ]]
grep -Fq "reuse:$S1:buffer=1:" "$PROBE"

create_count="$(grep -Fc "create:$S1" "$PROBE")"
[[ "$create_count" == "1" ]]
! grep -Fq "shutdown:$S1" "$PROBE"

initial_pid="$(grep -F "process:$S1:pid=" "$PROBE" | head -1 | sed 's/.*pid=//')"
reuse_pid="$(grep -F "reuse:$S1:buffer=1:pid=" "$PROBE" | tail -1 | sed 's/.*pid=//')"
[[ "$initial_pid" == <-> && "$initial_pid" -gt 0 ]]
[[ "$reuse_pid" == "$initial_pid" ]]
kill -0 "$initial_pid"

osascript -e 'tell application "System Events" to set visible of process "ApexTerm" to false' >/dev/null
sleep 0.35
osascript -e 'tell application "System Events" to set visible of process "ApexTerm" to true' >/dev/null
osascript -e 'tell application "ApexTerm" to activate' >/dev/null
sleep 0.5

APEXTERM_SUPPORT_DIRECTORY="$SUPPORT" "$CTL" workspace "$W2" >/dev/null
for _ in $(seq 1 240); do
  selected="$(APEXTERM_SUPPORT_DIRECTORY="$SUPPORT" "$CTL" status | jq -r '.selectedWorkspaceID')"
  [[ "$selected" == "$W2" ]] && break
  sleep 0.05
done
[[ "$selected" == "$W2" ]]

APEXTERM_SUPPORT_DIRECTORY="$SUPPORT" "$CTL" workspace "$W1" >/dev/null
for _ in $(seq 1 240); do
  selected="$(APEXTERM_SUPPORT_DIRECTORY="$SUPPORT" "$CTL" status | jq -r '.selectedWorkspaceID')"
  reuse_count="$(grep -Fc "reuse:$S1:buffer=1:pid=$initial_pid" "$PROBE" 2>/dev/null || true)"
  [[ "$selected" == "$W1" && "$reuse_count" -ge 2 ]] && break
  sleep 0.05
done
[[ "$selected" == "$W1" ]]
[[ "$reuse_count" -ge 2 ]]
kill -0 "$initial_pid"

printf 'TERMINAL_PERSISTENCE_E2E=PASS\n'
printf 'TAB_BUFFER_PRESERVED=PASS\n'
printf 'PTY_PID_PRESERVED=%s\n' "$initial_pid"
printf 'WINDOW_RETURN=PASS\n'
