#!/bin/zsh
set -euo pipefail

APP="/Applications/ApexTerm.app"
TMP_ROOT="$(mktemp -d /tmp/apexterm-ui-copy.XXXXXX)"
PROBE="$TMP_ROOT/copy-probe.txt"

cleanup() {
  launchctl unsetenv APEXTERM_UI_COPY_PROBE_FILE 2>/dev/null || true
  pkill -x ApexTerm 2>/dev/null || true
  sleep 0.2
  open "$APP" >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT INT TERM

pkill -x ApexTerm 2>/dev/null || true
sleep 0.3
launchctl setenv APEXTERM_UI_COPY_PROBE_FILE "$PROBE"
open "$APP"

for _ in $(seq 1 200); do
  [[ -f "$PROBE" ]] && break
  sleep 0.05
done
[[ -f "$PROBE" ]]
grep -Fqx 'copy_all=1' "$PROBE"
grep -Fqx 'copy_output=1' "$PROBE"
grep -Fqx 'copy_command=1' "$PROBE"

printf 'COMMAND_COPY_UI_E2E=PASS\n'
cat "$PROBE"
