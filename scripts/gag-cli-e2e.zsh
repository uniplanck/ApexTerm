#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CLI="${GAG_CLI_BIN:-$HOME/.local/bin/gag}"
APP="/Applications/ApexTerm.app"
SOCKET="$HOME/Library/Application Support/ApexTerm/runtime/apexterm.sock"

[[ -x "$CLI" ]]
[[ -d "$APP" ]]
"$CLI" version | grep -Fqx 'gag 0.1.0'

open "$APP" >/dev/null 2>&1 || true
for _ in {1..240}; do
  [[ -S "$SOCKET" ]] && break
  sleep 0.05
done
[[ -S "$SOCKET" ]]

doctor_json="$("$CLI" doctor --target both --json)"
print -r -- "$doctor_json" | ruby -rjson -e '
  report = JSON.parse(STDIN.read)
  abort "ApexTerm socket unavailable" unless report.fetch("apexTermConnected")
  targets = report.fetch("targets")
  abort "expected local and gae" unless targets.map { |x| x.fetch("target") }.sort == %w[gae local]
  targets.each do |target|
    abort "backend unavailable: #{target}" unless target.fetch("backendAvailable")
    abort "computer disabled: #{target}" unless target.fetch("computerUseEnabled")
    abort "browser unavailable: #{target}" unless target.fetch("browserReady")
  end
'

jobs_json="$("$CLI" list --target both --json)"
latest_success_ref="$(print -r -- "$jobs_json" | ruby -rjson -e '
  jobs = JSON.parse(STDIN.read)
  item = jobs.find { |entry| entry.dig("job", "preset") == "chatgpt-task" && entry.dig("job", "status") == "succeeded" }
  abort "no succeeded chatgpt-task job available" unless item
  print "#{item.fetch("target")}/#{item.fetch("job").fetch("id")}"
')"

status_json="$("$CLI" status "$latest_success_ref" --json)"
print -r -- "$status_json" | ruby -rjson -e '
  value = JSON.parse(STDIN.read)
  abort "missing job" unless value.dig("envelope", "job", "id")
  abort "unexpected preset" unless value.dig("envelope", "job", "preset") == "chatgpt-task"
'

result_json="$("$CLI" result "$latest_success_ref" --json)"
print -r -- "$result_json" | ruby -rjson -e '
  value = JSON.parse(STDIN.read)
  abort "result is not succeeded" unless value.dig("job", "status") == "succeeded"
  abort "response missing" if value.dig("job", "state", "responseText").to_s.empty?
'

watch_line="$("$CLI" watch "$latest_success_ref" --json-lines --timeout-seconds 5 | head -n 1)"
print -r -- "$watch_line" | ruby -rjson -e '
  value = JSON.parse(STDIN.read)
  abort "watch target missing" if value.fetch("target").to_s.empty?
  abort "watch job mismatch" unless value.dig("job", "status") == "succeeded"
  abort "watch job id missing" if value.dig("job", "id").to_s.empty?
'

if [[ "${GAG_CLI_REAL_CHATGPT:-0}" == "1" ]]; then
  local_marker="GAG_CLI_LOCAL_E2E_$(date +%s)"
  gae_marker="GAG_CLI_GAE_E2E_$(date +%s)"
  "$CLI" run --target local --expect "$local_marker" --timeout-seconds 240 --writing-kernel off \
    "Respond with exactly $local_marker"
  "$CLI" run --target gae --expect "$gae_marker" --timeout-seconds 240 --writing-kernel off \
    "Respond with exactly $gae_marker"
  print -r -- 'GAG_CLI_REAL_CHATGPT_E2E=PASS'
fi

print -r -- 'GAG_CLI_E2E=PASS'
print -r -- "LATEST_SUCCESS=$latest_success_ref"
