#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="/Applications/ApexTerm.app"
CTL="$ROOT/.build/release/apextermctl"
SOCKET="$HOME/Library/Application Support/ApexTerm/runtime/apexterm.sock"

[[ -d "$APP" ]]
[[ -x "$CTL" ]]

pkill -x ApexTerm 2>/dev/null || true
sleep 0.3
open "$APP"

for _ in $(seq 1 200); do
  [[ -S "$SOCKET" ]] && "$CTL" status >/dev/null 2>&1 && break
  sleep 0.05
done

status_json="$($CTL status)"
session_id="$(print -r -- "$status_json" | ruby -rjson -e '
  j=JSON.parse(STDIN.read)
  s=j.fetch("sessions").find { |item| item["kind"] == "local" }
  abort "No local session" unless s
  print s["id"]
')"

result=""
result_rc=2
for _ in $(seq 1 160); do
  set +e
  result="$($CTL exec "$session_id" "printf 'GAG_APT_ROUNDTRIP_OK\\n'; printf 'app=ApexTerm\\n'; printf 'cwd=%s\\n' \"\$PWD\"" 2>&1)"
  result_rc=$?
  set -e
  if [[ $result_rc -eq 0 ]] && print -r -- "$result" | grep -Fq "GAG_APT_ROUNDTRIP_OK"; then
    break
  fi
  sleep 0.05
done
[[ $result_rc -eq 0 ]]
print -r -- "$result" | grep -Fq "GAG_APT_ROUNDTRIP_OK"
print -r -- "$result" | grep -Fq "app=ApexTerm"
print -r -- "$result" | grep -Fq "[apexterm exit=0]"
if print -r -- "$result" | grep -Fq "__APEXTERM_"; then
  print -u2 -- "Internal command marker leaked"
  exit 1
fi
if print -r -- "$result" | awk 'BEGIN{bad=0} {line=$0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", line); if (line == "%") bad=1} END{exit bad ? 0 : 1}'; then
  print -u2 -- "Shell prompt leaked into command result"
  exit 1
fi

nonzero="$($CTL exec "$session_id" "printf 'EXPECTED_NONZERO\\n'; false")"
print -r -- "$nonzero" | grep -Fq "EXPECTED_NONZERO"
print -r -- "$nonzero" | grep -Fq "[apexterm exit=1]"

set +e
denied="$($CTL exec "$session_id" "git push --force origin main" 2>&1)"
denied_rc=$?
set -e
[[ $denied_rc -eq 2 ]]
print -r -- "$denied" | grep -Fq "Foreground approval required"

print -r -- "COMMAND_ROUNDTRIP_E2E=PASS"
print -r -- "NONZERO_EXIT_CAPTURE_E2E=PASS"
print -r -- "RISK_DENIAL_E2E=PASS"
print -r -- "SESSION_ID=$session_id"
print -r -- "--- RESULT ---"
print -r -- "$result"
