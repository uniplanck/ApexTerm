#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/.build/release/ApexTerm"
INSTALLED_APP="/Applications/ApexTerm.app"
CTL="$ROOT/.build/release/apextermctl"
TMP_ROOT="$(mktemp -d /tmp/apexterm-e2e.XXXXXX)"
typeset -a APP_PIDS
APP_PIDS=()
typeset -a TMUX_NAMES
TMUX_NAMES=()
typeset -a TMUX_SERVERS
TMUX_SERVERS=()

cleanup() {
  local pid name
  for pid in $APP_PIDS; do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  for name in $TMUX_NAMES; do
    tmux -L apexterm kill-session -t "$name" 2>/dev/null || true
  done
  for name in $TMUX_SERVERS; do
    tmux -L "$name" kill-server 2>/dev/null || true
  done
  rm -rf "$TMP_ROOT"
  open "$INSTALLED_APP" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

wait_ready() {
  local ready_file="$1"
  local pid="$2"
  local i=0
  while [[ ! -f "$ready_file" && $i -lt 500 ]]; do
    kill -0 "$pid" 2>/dev/null || return 1
    sleep 0.01
    i=$((i + 1))
  done
  [[ -f "$ready_file" ]]
}

status_to() {
  local support="$1"
  local output="$2"
  APEXTERM_SUPPORT_DIRECTORY="$support" "$CTL" status > "$output"
}

selected_session_id() {
  ruby -rjson -e 'print JSON.parse(File.read(ARGV[0]))["selectedSessionID"]' "$1"
}

selected_session_pair() {
  ruby -rjson -e '
    j=JSON.parse(File.read(ARGV[0]))
    id=j["selectedSessionID"]
    s=j.fetch("sessions").find { |item| item["id"] == id }
    puts "#{s && s["state"]} #{s && s["kind"]}"
  ' "$1"
}

pkill -x ApexTerm 2>/dev/null || true
for _ in {1..80}; do
  pgrep -x ApexTerm >/dev/null 2>&1 || break
  sleep 0.05
done

cd "$ROOT"
swift build -c release >/dev/null

print -r -- "[1/3] Structured agent lifecycle"
support_agent="$TMP_ROOT/agent-support"
ready_agent="$TMP_ROOT/agent-ready"
mkdir -p "$support_agent"
APEXTERM_SUPPORT_DIRECTORY="$support_agent" \
APEXTERM_READY_FILE="$ready_agent" \
APEXTERM_DISABLE_LOCAL_TMUX=1 \
"$APP" >"$TMP_ROOT/agent-app.log" 2>&1 &
pid_agent=$!
APP_PIDS+=($pid_agent)
wait_ready "$ready_agent" "$pid_agent"
run_id="$(uuidgen)"
APEXTERM_SUPPORT_DIRECTORY="$support_agent" "$CTL" \
  agent "$run_id" running gag ApexTermBuild "$ROOT" 0.35 Compiling >/dev/null
sleep 0.15
status_to "$support_agent" "$TMP_ROOT/agent-running.json"
ruby -rjson -e '
  j=JSON.parse(File.read(ARGV[0])); a=j.fetch("agents").first
  abort unless j["activeAgentCount"] == 1 && a["state"] == "running" && a["progress"] == 0.35
' "$TMP_ROOT/agent-running.json"
APEXTERM_SUPPORT_DIRECTORY="$support_agent" "$CTL" \
  agent "$run_id" waitingApproval gag ApexTermBuild "$ROOT" 0.6 ApprovalRequired >/dev/null
sleep 0.15
status_to "$support_agent" "$TMP_ROOT/agent-approval.json"
ruby -rjson -e '
  j=JSON.parse(File.read(ARGV[0])); a=j.fetch("agents").first
  abort unless a["state"] == "waitingApproval" && a["message"] == "ApprovalRequired"
' "$TMP_ROOT/agent-approval.json"
APEXTERM_SUPPORT_DIRECTORY="$support_agent" "$CTL" \
  agent "$run_id" succeeded gag ApexTermBuild "$ROOT" 1 Done >/dev/null
sleep 0.15
status_to "$support_agent" "$TMP_ROOT/agent-done.json"
ruby -rjson -e '
  j=JSON.parse(File.read(ARGV[0])); a=j.fetch("agents").first
  abort unless j["activeAgentCount"] == 0 && a["state"] == "succeeded" && a["progress"] == 1
' "$TMP_ROOT/agent-done.json"
kill "$pid_agent" 2>/dev/null || true
wait "$pid_agent" 2>/dev/null || true
APP_PIDS=(${APP_PIDS:#$pid_agent})
print -r -- "AGENT_LIFECYCLE_E2E=PASS"

print -r -- "[2/3] Durable local session"
support_local="$TMP_ROOT/local-support"
ready_local_1="$TMP_ROOT/local-ready-1"
ready_local_2="$TMP_ROOT/local-ready-2"
tmux_server="apexterm-e2e-$$-$RANDOM"
TMUX_SERVERS+=($tmux_server)
mkdir -p "$support_local"
local_session_seed="$(uuidgen)"
local_workspace_seed="$(uuidgen)"
tmux_name="apexterm-$(print -rn -- "$local_session_seed" | tr -d '-' | tr '[:upper:]' '[:lower:]')"
TMUX_NAMES+=($tmux_name)
ruby -rjson -e '
  support, workspace_id, session_id, tmux_name, root = ARGV
  document = {
    schemaVersion: 1,
    workspaces: [{
      id: workspace_id,
      name: "Durable tmux",
      rootDirectory: root,
      layout: { pane: { sessionID: session_id } },
      createdAt: 0,
      updatedAt: 0
    }],
    sessions: [{
      id: session_id,
      title: "Durable tmux",
      kind: { localTmux: { session: tmux_name } },
      state: "created",
      workingDirectory: root,
      createdAt: 0
    }]
  }
  File.write(File.join(support, "workspaces.json"), JSON.pretty_generate(document) + "\n")
' "$support_local" "$local_workspace_seed" "$local_session_seed" "$tmux_name" "$ROOT"
APEXTERM_SUPPORT_DIRECTORY="$support_local" \
APEXTERM_TMUX_SERVER="$tmux_server" \
APEXTERM_READY_FILE="$ready_local_1" \
"$APP" >"$TMP_ROOT/local-app-1.log" 2>&1 &
pid_local_1=$!
APP_PIDS+=($pid_local_1)
wait_ready "$ready_local_1" "$pid_local_1"
status_to "$support_local" "$TMP_ROOT/local-status-1.json"
local_session_1="$(selected_session_id "$TMP_ROOT/local-status-1.json")"
[[ "$local_session_1" == "$local_session_seed" ]]
tmux -L "$tmux_server" has-session -t "$tmux_name"
kill "$pid_local_1" 2>/dev/null || true
wait "$pid_local_1" 2>/dev/null || true
APP_PIDS=(${APP_PIDS:#$pid_local_1})
sleep 0.2
tmux -L "$tmux_server" has-session -t "$tmux_name"
APEXTERM_SUPPORT_DIRECTORY="$support_local" \
APEXTERM_TMUX_SERVER="$tmux_server" \
APEXTERM_READY_FILE="$ready_local_2" \
"$APP" >"$TMP_ROOT/local-app-2.log" 2>&1 &
pid_local_2=$!
APP_PIDS+=($pid_local_2)
wait_ready "$ready_local_2" "$pid_local_2"
sleep 0.2
status_to "$support_local" "$TMP_ROOT/local-status-2.json"
local_session_2="$(selected_session_id "$TMP_ROOT/local-status-2.json")"
[[ "$local_session_1" == "$local_session_2" ]]
tmux -L "$tmux_server" has-session -t "$tmux_name"
kill "$pid_local_2" 2>/dev/null || true
wait "$pid_local_2" 2>/dev/null || true
APP_PIDS=(${APP_PIDS:#$pid_local_2})
print -r -- "LOCAL_DURABILITY_E2E=PASS"

print -r -- "[3/3] Remote reconnect"
support_remote="$TMP_ROOT/remote-support"
ready_remote="$TMP_ROOT/remote-ready"
count_file="$TMP_ROOT/remote-attempt-count"
fake_ssh="$TMP_ROOT/fake-ssh"
mkdir -p "$support_remote"
cat > "$fake_ssh" <<'SH'
#!/bin/zsh
set -eu
count_file="${APEXTERM_FAKE_COUNT_FILE:?}"
count=0
[[ ! -f "$count_file" ]] || count=$(<"$count_file")
count=$((count + 1))
printf '%s\n' "$count" > "$count_file"
if (( count < 3 )); then
  sleep 0.08
  exit 42
fi
sleep 30
SH
chmod 700 "$fake_ssh"
APEXTERM_SUPPORT_DIRECTORY="$support_remote" \
APEXTERM_READY_FILE="$ready_remote" \
APEXTERM_DISABLE_LOCAL_TMUX=1 \
APEXTERM_SSH_EXECUTABLE="$fake_ssh" \
APEXTERM_FAKE_COUNT_FILE="$count_file" \
"$APP" >"$TMP_ROOT/remote-app.log" 2>&1 &
pid_remote=$!
APP_PIDS+=($pid_remote)
wait_ready "$ready_remote" "$pid_remote"
APEXTERM_SUPPORT_DIRECTORY="$support_remote" "$CTL" attach fakehost - >/dev/null
seen_reconnecting=0
remote_state=""
remote_kind=""
for _ in $(seq 1 240); do
  status_to "$support_remote" "$TMP_ROOT/remote-status.json"
  read -r remote_state remote_kind <<< "$(selected_session_pair "$TMP_ROOT/remote-status.json")"
  [[ "$remote_state" != "reconnecting" ]] || seen_reconnecting=1
  attempts=0
  [[ ! -f "$count_file" ]] || attempts=$(<"$count_file")
  if [[ $attempts -ge 3 && "$remote_state" == "attached" ]]; then
    break
  fi
  sleep 0.05
done
attempts=0
[[ ! -f "$count_file" ]] || attempts=$(<"$count_file")
[[ $attempts -eq 3 ]]
[[ $seen_reconnecting -eq 1 ]]
[[ "$remote_state" == "attached" ]]
[[ "$remote_kind" == "ssh:fakehost" ]]
print -r -- "REMOTE_RECONNECT_E2E=PASS"

print -r -- "E2E_GATE=PASS"
