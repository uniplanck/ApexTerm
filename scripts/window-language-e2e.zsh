#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="/Applications/ApexTerm.app"
TMP_ROOT="$(mktemp -d /tmp/apexterm-window-language.XXXXXX)"
SUPPORT="$TMP_ROOT/support"
ACTIVATION_PROBE="$TMP_ROOT/activation.txt"
LANGUAGE_PROBE="$TMP_ROOT/language.txt"

stop_app() {
  pkill -x ApexTerm 2>/dev/null || true
  for _ in {1..80}; do
    pgrep -x ApexTerm >/dev/null 2>&1 || return 0
    sleep 0.05
  done
  print -u2 -r -- "ApexTerm did not stop before window/language E2E"
  return 1
}

cleanup() {
  launchctl unsetenv APEXTERM_SUPPORT_DIRECTORY 2>/dev/null || true
  launchctl unsetenv APEXTERM_QUICK_ACTIVATION_PROBE_FILE 2>/dev/null || true
  launchctl unsetenv APEXTERM_LANGUAGE_PROBE_FILE 2>/dev/null || true
  stop_app 2>/dev/null || true
  sleep 0.15
  open "$APP" >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT INT TERM

mkdir -p "$SUPPORT"
stop_app
launchctl setenv APEXTERM_SUPPORT_DIRECTORY "$SUPPORT"
launchctl setenv APEXTERM_QUICK_ACTIVATION_PROBE_FILE "$ACTIVATION_PROBE"
launchctl setenv APEXTERM_LANGUAGE_PROBE_FILE "$LANGUAGE_PROBE"
open "$APP"

for _ in $(seq 1 240); do
  [[ -f "$ACTIVATION_PROBE" && -f "$LANGUAGE_PROBE" ]] && break
  sleep 0.05
done
[[ -f "$ACTIVATION_PROBE" ]]
[[ -f "$LANGUAGE_PROBE" ]]

cat "$ACTIVATION_PROBE"
cat "$LANGUAGE_PROBE"

for expected in \
  'quick_key=1' \
  'main_key=0' \
  'quick_floating=1' \
  'window_roles_distinct=1'
do
  grep -Fqx "$expected" "$ACTIVATION_PROBE"
done

for expected in \
  'settings_sheet=1' \
  'language_switch=1' \
  'language_resources=1' \
  'japanese_translation=1'
do
  grep -Fqx "$expected" "$LANGUAGE_PROBE"
done

printf 'WINDOW_ACTIVATION_E2E=PASS\n'
printf 'LANGUAGE_SETTINGS_E2E=PASS\n'
cat "$ACTIVATION_PROBE"
cat "$LANGUAGE_PROBE"
