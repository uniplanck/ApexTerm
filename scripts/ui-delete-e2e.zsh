#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="/Applications/ApexTerm.app"
ALIAS="${1:-ec2-hermes-2222}"
TMP_ROOT="$(mktemp -d /tmp/apexterm-ui-delete.XXXXXX)"
SUPPORT="$TMP_ROOT/support"
PROBE="$TMP_ROOT/delete-probe.txt"

cleanup() {
  launchctl unsetenv APEXTERM_SUPPORT_DIRECTORY 2>/dev/null || true
  launchctl unsetenv APEXTERM_UI_DELETE_PROBE_ALIAS 2>/dev/null || true
  launchctl unsetenv APEXTERM_UI_DELETE_PROBE_FILE 2>/dev/null || true
  pkill -x ApexTerm 2>/dev/null || true
  sleep 0.2
  open "$APP" >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT INT TERM

mkdir -p "$SUPPORT"
pkill -x ApexTerm 2>/dev/null || true
sleep 0.3
launchctl setenv APEXTERM_SUPPORT_DIRECTORY "$SUPPORT"
launchctl setenv APEXTERM_UI_DELETE_PROBE_ALIAS "$ALIAS"
launchctl setenv APEXTERM_UI_DELETE_PROBE_FILE "$PROBE"
open "$APP"

for _ in $(seq 1 200); do
  [[ -f "$PROBE" ]] && break
  sleep 0.05
done
[[ -f "$PROBE" ]]
grep -Fqx 'sheet=1' "$PROBE"
grep -Fqx 'existed_before=1' "$PROBE"
grep -Fqx 'entry_removed=1' "$PROBE"
grep -Fqx 'marked_deleted=1' "$PROBE"
grep -Fqx 'workspace_removed=1' "$PROBE"

ruby -rjson -e '
  path=File.join(ARGV[0], "remote-hosts.json")
  alias_name=ARGV[1]
  j=JSON.parse(File.read(path))
  abort "alias not persisted as deleted" unless Array(j["deletedAliases"]).include?(alias_name)
' "$SUPPORT" "$ALIAS"

printf 'REMOTE_DELETE_UI_E2E=PASS\n'
cat "$PROBE"
