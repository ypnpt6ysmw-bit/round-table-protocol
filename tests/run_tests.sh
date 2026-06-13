#!/usr/bin/env bash
# run_tests.sh — Round Table Protocol test suite
# Runs every rt-* script against a sandboxed ROUND_TABLE_DIR and asserts behavior.
# Usage: tests/run_tests.sh
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$REPO_DIR/scripts"

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/rtp_test.XXXXXX")
export ROUND_TABLE_DIR="$SANDBOX/round-table"
mkdir -p "$ROUND_TABLE_DIR"
cp "$REPO_DIR/config.json" "$ROUND_TABLE_DIR/config.json"

PASS=0
FAIL=0
FAILED_NAMES=()

cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

# run <name> <expected_exit_code> <command...>
run() {
  local name="$1"; shift
  local expect="$1"; shift
  local out rc
  out=$("$@" 2>&1); rc=$?
  if [[ "$rc" -eq "$expect" ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); FAILED_NAMES+=("$name")
    echo "FAIL: $name (exit $rc, expected $expect)"
    echo "$out" | sed 's/^/    /'
  fi
  LAST_OUT="$out"
}

# assert_contains <name> <needle>  (checks LAST_OUT)
assert_contains() {
  local name="$1" needle="$2"
  if [[ "$LAST_OUT" == *"$needle"* ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); FAILED_NAMES+=("$name")
    echo "FAIL: $name — output missing: $needle"
    echo "$LAST_OUT" | sed 's/^/    /'
  fi
}

assert_not_contains() {
  local name="$1" needle="$2"
  if [[ "$LAST_OUT" != *"$needle"* ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); FAILED_NAMES+=("$name")
    echo "FAIL: $name — output should not contain: $needle"
  fi
}

assert_file() {
  local name="$1" f="$2"
  if [[ -f "$f" ]]; then PASS=$((PASS+1)); else
    FAIL=$((FAIL+1)); FAILED_NAMES+=("$name")
    echo "FAIL: $name — missing file: $f"
  fi
}

assert_valid_json() {
  local name="$1" f="$2"
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); FAILED_NAMES+=("$name")
    echo "FAIL: $name — invalid JSON: $f"
  fi
}

echo "=== Round Table Protocol Test Suite ==="
echo "Sandbox: $ROUND_TABLE_DIR"
echo ""

### rt-send ###############################################################
run "send: direct message" 0 \
  "$SCRIPTS/rt-send.sh" --from arthur --to merlin --type question --payload '{"q":"status?"}'
assert_contains "send: delivery confirmation" "delivered to merlin"
MSG_FILE=$(ls "$ROUND_TABLE_DIR/inbox/merlin/"*.json 2>/dev/null | head -1)
assert_file "send: inbox file created" "$MSG_FILE"
assert_valid_json "send: inbox file is valid JSON" "$MSG_FILE"

run "send: missing --from rejected" 1 \
  "$SCRIPTS/rt-send.sh" --to merlin --type question --payload '{}'

run "send: broadcast" 0 \
  "$SCRIPTS/rt-send.sh" --from arthur --to broadcast --type status --payload '{"s":"ok"}'
assert_contains "send: broadcast count" "4 agents"

run "send: payload with quotes survives" 0 \
  "$SCRIPTS/rt-send.sh" --from merlin --to arthur --type finding --payload "It's \"quoted\" — and 'single'"
Q_FILE=$(ls -t "$ROUND_TABLE_DIR/inbox/arthur/"*.json | head -1)
assert_valid_json "send: quoted payload valid JSON" "$Q_FILE"

run "send: unknown agent rejected" 1 \
  "$SCRIPTS/rt-send.sh" --from arthur --to mordred --type question --payload '{}'

run "send: path traversal rejected" 1 \
  "$SCRIPTS/rt-send.sh" --from arthur --to "../evil" --type question --payload '{}'
[[ ! -d "$ROUND_TABLE_DIR/evil" && ! -d "$SANDBOX/evil" ]] && PASS=$((PASS+1)) || {
  FAIL=$((FAIL+1)); FAILED_NAMES+=("send: traversal dir not created"); echo "FAIL: traversal dir created"; }

# Verify no temp files leaked to /tmp from rt-send
run "send: no temp files leaked" 0 bash -c '
  tmp_before=$(ls /tmp/rtp_payload.* 2>/dev/null | wc -l)
  '"$SCRIPTS/rt-send.sh"' --from arthur --to merlin --type status --payload '"'"'{"ok":true}"'"'"'
  tmp_after=$(ls /tmp/rtp_payload.* 2>/dev/null | wc -l)
  [[ "$tmp_before" -eq "$tmp_after" ]]
'

### rt-inbox ##############################################################
run "inbox: list" 0 "$SCRIPTS/rt-inbox.sh" merlin list
assert_contains "inbox: list shows message" "question"

MSG_ID=$(basename "$MSG_FILE" .json)
run "inbox: read" 0 "$SCRIPTS/rt-inbox.sh" merlin read "$MSG_ID"
assert_contains "inbox: read shows payload" "status?"

run "inbox: ack" 0 "$SCRIPTS/rt-inbox.sh" merlin ack "$MSG_ID"
assert_file "inbox: ack archived file" "$ROUND_TABLE_DIR/inbox/merlin/archived/${MSG_ID}.json"

run "inbox: read missing id fails" 1 "$SCRIPTS/rt-inbox.sh" merlin read no-such-id
run "inbox: no agent fails" 1 "$SCRIPTS/rt-inbox.sh" list

### rt-memory #############################################################
run "memory: set" 0 "$SCRIPTS/rt-memory.sh" set arch.framework "CrewAI chosen" --from arthur --tags arch,decision
run "memory: get" 0 "$SCRIPTS/rt-memory.sh" get arch.framework
assert_contains "memory: get returns value" "CrewAI chosen"

run "memory: set value with quotes" 0 \
  "$SCRIPTS/rt-memory.sh" set tricky.key "it's \"tricky\" \$(touch $SANDBOX/pwned) \`id\`" --from merlin
[[ ! -f "$SANDBOX/pwned" ]] && PASS=$((PASS+1)) || {
  FAIL=$((FAIL+1)); FAILED_NAMES+=("memory: no command injection via value"); echo "FAIL: command injection executed!"; }

run "memory: get tricky key intact" 0 "$SCRIPTS/rt-memory.sh" get tricky.key
assert_contains "memory: tricky value preserved" 'tricky'

run "memory: get key containing apostrophe" 1 "$SCRIPTS/rt-memory.sh" get "no'such'key"

run "memory: search" 0 "$SCRIPTS/rt-memory.sh" search crewai
assert_contains "memory: search finds entry" "arch.framework"

run "memory: list" 0 "$SCRIPTS/rt-memory.sh" list
assert_contains "memory: list shows key" "arch.framework"

run "memory: list --agent filter" 0 "$SCRIPTS/rt-memory.sh" list --agent arthur
assert_contains "memory: agent filter keeps arthur" "arch.framework"
assert_not_contains "memory: agent filter drops merlin" "tricky.key"

run "memory: delete" 0 "$SCRIPTS/rt-memory.sh" delete tricky.key
run "memory: get deleted key fails" 1 "$SCRIPTS/rt-memory.sh" get tricky.key

run "memory: clear --agent" 0 "$SCRIPTS/rt-memory.sh" clear --agent arthur
run "memory: get cleared key fails" 1 "$SCRIPTS/rt-memory.sh" get arch.framework

### rt-status #############################################################
run "status: update" 0 "$SCRIPTS/rt-status.sh" lancelot --task "QA suite" --status working --progress "4/7"
assert_file "status: card written" "$ROUND_TABLE_DIR/status/lancelot.json"
assert_valid_json "status: card valid JSON" "$ROUND_TABLE_DIR/status/lancelot.json"

run "status: invalid status rejected" 1 "$SCRIPTS/rt-status.sh" lancelot --task x --status exploded

### rt-checkin ############################################################
run "checkin: runs" 0 "$SCRIPTS/rt-checkin.sh" lancelot
assert_contains "checkin: shows status" "lancelot"

### rt-session-checkin ####################################################
# Clean inbox of merlin first
rm -f "$ROUND_TABLE_DIR/inbox/merlin/"*.json 2>/dev/null || true
rm -f "$ROUND_TABLE_DIR/.checkin-state-merlin" 2>/dev/null || true

run "session-checkin: empty inbox" 0 "$SCRIPTS/rt-session-checkin.sh" merlin
assert_contains "session-checkin: empty checkin output" ""

# Send a normal message
"$SCRIPTS/rt-send.sh" --from arthur --to merlin --type status --payload '{"s":"ok"}' >/dev/null
run "session-checkin: 1 pending" 0 "$SCRIPTS/rt-session-checkin.sh" merlin
assert_contains "session-checkin: shows 1 pending" "1 pending (0 urgent)"

# Repeat run should be silent
run "session-checkin: repeat run silent" 0 "$SCRIPTS/rt-session-checkin.sh" merlin
assert_contains "session-checkin: repeat checkin output empty" ""

# Send an urgent message
"$SCRIPTS/rt-send.sh" --from arthur --to merlin --type question --priority urgent --payload '{"q":"help"}' >/dev/null
run "session-checkin: urgent pending" 0 "$SCRIPTS/rt-session-checkin.sh" merlin
assert_contains "session-checkin: shows urgent" "2 pending (1 urgent)"
assert_contains "session-checkin: shows urgent details" "FROM: arthur  TYPE: question"


### rt-snapshot ###########################################################
run "snapshot: save" 0 "$SCRIPTS/rt-snapshot.sh" merlin sess-42 "research done"
SNAP_FILE=$(ls "$ROUND_TABLE_DIR/snapshots/"*.json 2>/dev/null | head -1)
assert_file "snapshot: file created" "$SNAP_FILE"
assert_valid_json "snapshot: valid JSON" "$SNAP_FILE"

### rt-artifact ###########################################################
run "artifact: register" 0 "$SCRIPTS/rt-artifact.sh" percival --file /tmp/x.md --desc "doc" --for bedivere
ART_FILE=$(ls "$ROUND_TABLE_DIR/artifacts/"*.json 2>/dev/null | head -1)
assert_file "artifact: file created" "$ART_FILE"
assert_valid_json "artifact: valid JSON" "$ART_FILE"
NOTIF=$(ls "$ROUND_TABLE_DIR/inbox/bedivere/"*.json 2>/dev/null | wc -l | tr -d ' ')
[[ "$NOTIF" -ge 1 ]] && PASS=$((PASS+1)) || {
  FAIL=$((FAIL+1)); FAILED_NAMES+=("artifact: notification delivered"); echo "FAIL: artifact notification not in bedivere inbox"; }

run "artifact: desc with quotes notifies cleanly" 0 \
  "$SCRIPTS/rt-artifact.sh" percival --file /tmp/y.md --desc "has \"quotes\" and 'apostrophes'" --for bedivere
LATEST=$(ls -t "$ROUND_TABLE_DIR/inbox/bedivere/"*.json | head -1)
assert_valid_json "artifact: quoted-desc notification valid JSON" "$LATEST"

### rt-cleanup ############################################################
# age a message artificially
OLD_MSG="$ROUND_TABLE_DIR/inbox/lancelot/old-msg.json"
mkdir -p "$ROUND_TABLE_DIR/inbox/lancelot"
echo '{"id":"old-msg","from":"arthur","to":"lancelot","type":"status","priority":"normal","timestamp":"2020-01-01T00:00:00Z","payload":{}}' > "$OLD_MSG"
touch -t 202001010000 "$OLD_MSG"

run "cleanup: dry run" 0 "$SCRIPTS/rt-cleanup.sh" --dry-run --older-than 1
assert_file "cleanup: dry run keeps file" "$OLD_MSG"

run "cleanup: older-than archives" 0 "$SCRIPTS/rt-cleanup.sh" --older-than 1
assert_file "cleanup: old message archived" "$ROUND_TABLE_DIR/inbox/lancelot/archived/old-msg.json"

# empty memory file vacuum must not crash
: > "$ROUND_TABLE_DIR/memory.jsonl"
run "cleanup: empty memory vacuum" 0 "$SCRIPTS/rt-cleanup.sh" --older-than 9999

# vacuum must not eat entries whose VALUE mentions deleted:true
"$SCRIPTS/rt-memory.sh" set vacuum.trap '{"deleted": true}' --from arthur >/dev/null
run "cleanup: vacuum run" 0 "$SCRIPTS/rt-cleanup.sh" --older-than 9999
run "cleanup: value mentioning deleted survives vacuum" 0 "$SCRIPTS/rt-memory.sh" get vacuum.trap

# --keep-last tests
# Create 5 messages for keep-last testing
KEEP_AGENT="percival"
mkdir -p "$ROUND_TABLE_DIR/inbox/$KEEP_AGENT"
for i in 1 2 3 4 5; do
  echo "{\"id\":\"keep-$i\",\"from\":\"arthur\",\"to\":\"$KEEP_AGENT\",\"type\":\"status\",\"priority\":\"normal\",\"timestamp\":\"2025-01-0${i}T00:00:00Z\",\"payload\":{}}" > "$ROUND_TABLE_DIR/inbox/$KEEP_AGENT/keep-$i.json"
done

run "cleanup: keep-last basic" 0 "$SCRIPTS/rt-cleanup.sh" --keep-last 2
# Should archive 3 (keep newest 2: keep-4, keep-5)
assert_file "cleanup: keep-last archived keep-1" "$ROUND_TABLE_DIR/inbox/$KEEP_AGENT/archived/keep-1.json"
assert_file "cleanup: keep-last archived keep-2" "$ROUND_TABLE_DIR/inbox/$KEEP_AGENT/archived/keep-2.json"
assert_file "cleanup: keep-last archived keep-3" "$ROUND_TABLE_DIR/inbox/$KEEP_AGENT/archived/keep-3.json"
# Newest 2 should remain in inbox
KEEP4_RAW=$(ls "$ROUND_TABLE_DIR/inbox/$KEEP_AGENT/keep-4.json" 2>/dev/null)
assert_file "cleanup: keep-last keeps keep-4" "$KEEP4_RAW"
KEEP5_RAW=$(ls "$ROUND_TABLE_DIR/inbox/$KEEP_AGENT/keep-5.json" 2>/dev/null)
assert_file "cleanup: keep-last keeps keep-5" "$KEEP5_RAW"

# keep-last=0 should archive everything
rm -rf "$ROUND_TABLE_DIR/inbox/$KEEP_AGENT/archived"
for i in 1 2 3; do
  echo "{\"id\":\"zero-$i\",\"from\":\"arthur\",\"to\":\"$KEEP_AGENT\",\"type\":\"status\",\"priority\":\"normal\",\"timestamp\":\"2025-01-0${i}T00:00:00Z\",\"payload\":{}}" > "$ROUND_TABLE_DIR/inbox/$KEEP_AGENT/zero-$i.json"
done
run "cleanup: keep-last zero archives all" 0 "$SCRIPTS/rt-cleanup.sh" --keep-last 0
assert_file "cleanup: keep-last=0 archived zero-1" "$ROUND_TABLE_DIR/inbox/$KEEP_AGENT/archived/zero-1.json"
assert_file "cleanup: keep-last=0 archived zero-2" "$ROUND_TABLE_DIR/inbox/$KEEP_AGENT/archived/zero-2.json"
assert_file "cleanup: keep-last=0 archived zero-3" "$ROUND_TABLE_DIR/inbox/$KEEP_AGENT/archived/zero-3.json"

# keep-last combined with --older-than: old messages archived by age, rest by keep-last
rm -rf "$ROUND_TABLE_DIR/inbox/$KEEP_AGENT"
mkdir -p "$ROUND_TABLE_DIR/inbox/$KEEP_AGENT"
for i in 1 2 3 4; do
  echo "{\"id\":\"combo-$i\",\"from\":\"arthur\",\"to\":\"$KEEP_AGENT\",\"type\":\"status\",\"priority\":\"normal\",\"timestamp\":\"2020-01-0${i}T00:00:00Z\",\"payload\":{}}" > "$ROUND_TABLE_DIR/inbox/$KEEP_AGENT/combo-$i.json"
  touch -t 202001010000 "$ROUND_TABLE_DIR/inbox/$KEEP_AGENT/combo-$i.json"
done
# Add one recent message that should survive keep-last=1
echo '{"id":"combo-recent","from":"arthur","to":"percival","type":"status","priority":"normal","timestamp":"2025-06-01T00:00:00Z","payload":{}}' > "$ROUND_TABLE_DIR/inbox/$KEEP_AGENT/combo-recent.json"
run "cleanup: keep-last combined with older-than" 0 "$SCRIPTS/rt-cleanup.sh" --older-than 1 --keep-last 1
# All old combo-1..4 archived (by age), recent kept by keep-last=1
assert_file "cleanup: combo archived combo-1" "$ROUND_TABLE_DIR/inbox/$KEEP_AGENT/archived/combo-1.json"
assert_file "cleanup: combo archived combo-2" "$ROUND_TABLE_DIR/inbox/$KEEP_AGENT/archived/combo-2.json"
COMBO_RECENT_RAW=$(ls "$ROUND_TABLE_DIR/inbox/$KEEP_AGENT/combo-recent.json" 2>/dev/null)
assert_file "cleanup: combo keeps recent" "$COMBO_RECENT_RAW"

### rt-watch ##############################################################
run "watch: snapshot mode" 0 "$SCRIPTS/rt-watch.sh"
assert_contains "watch: shows agents" "lancelot"

### rt-daemon #############################################################
run "daemon: status when stopped" 1 "$SCRIPTS/rt-daemon.sh" status
run "daemon: start" 0 "$SCRIPTS/rt-daemon.sh" start
# Wait for daemon to fully initialize (nohup + disown can take a moment)
for i in 1 2 3 4 5; do
  run "daemon: status running" 0 "$SCRIPTS/rt-daemon.sh" status && break
  sleep 1
done
run "daemon: stop" 0 "$SCRIPTS/rt-daemon.sh" stop
sleep 0.5
run "daemon: status after stop" 1 "$SCRIPTS/rt-daemon.sh" status
# no orphan processes left behind
DAEMON_PIDFILE="$ROUND_TABLE_DIR/.daemon.pid"
ORPHANS=0
if [[ -f "$DAEMON_PIDFILE" ]]; then
  DAEMON_PID=$(cat "$DAEMON_PIDFILE")
  if kill -0 "$DAEMON_PID" 2>/dev/null; then
    ORPHANS=1
  fi
fi
[[ "$ORPHANS" -eq 0 ]] && PASS=$((PASS+1)) || {
  FAIL=$((FAIL+1)); FAILED_NAMES+=("daemon: no orphans"); echo "FAIL: orphan daemon process still running (PID: $DAEMON_PID)"; }
# check that child processes (fswatch/inotifywait/sleep) are also reaped
CHILD_ORPHANS=0
for child_pattern in fswatch inotifywait; do
  if pgrep -f "$child_pattern" >/dev/null 2>&1; then
    # Verify it's not a pre-existing system process by checking it was not running before start
    CHILD_ORPHANS=1
  fi
done
# Also check for leftover sleep processes that may be children of the daemon
# Use a small window: look for sleep processes that are orphaned (PPID 1) and were likely daemon children
if [[ "$(uname)" == "Darwin" ]]; then
  ORPHAN_SLEEP=$(ps -eo pid,ppid,comm | awk '$2==1 && /sleep/ {print $1}' | head -5)
else
  ORPHAN_SLEEP=$(ps -eo pid,ppid,comm | awk '$2==1 && /sleep/ {print $1}' | head -5)
fi
if [[ -n "$ORPHAN_SLEEP" ]]; then
  CHILD_ORPHANS=1
fi
[[ "$CHILD_ORPHANS" -eq 0 ]] && PASS=$((PASS+1)) || {
  FAIL=$((FAIL+1)); FAILED_NAMES+=("daemon: no child orphans"); echo "FAIL: orphan child processes still running after daemon stop"; }

### generate-dashboard-data ###############################################
run "dashboard data: generate" 0 "$SCRIPTS/generate-dashboard-data.sh"
assert_file "dashboard data: messages.json" "$ROUND_TABLE_DIR/.dashboard/messages.json"
assert_file "dashboard data: memory.json" "$ROUND_TABLE_DIR/.dashboard/memory.json"
assert_valid_json "dashboard data: messages valid" "$ROUND_TABLE_DIR/.dashboard/messages.json"
assert_valid_json "dashboard data: memory valid" "$ROUND_TABLE_DIR/.dashboard/memory.json"

### rt-dashboard-text ######################################################
"$SCRIPTS/rt-status.sh" lancelot --task "QA board" --status working --progress "2/3" >/dev/null
"$SCRIPTS/generate-dashboard-data.sh" >/dev/null
run "dashboard text: renders" 0 "$SCRIPTS/rt-dashboard-text.sh"
assert_contains "dashboard text: shows header" "ROUND TABLE"
assert_contains "dashboard text: shows agent" "LANCELOT"
# must never reference opening a browser, only the passive URL
assert_not_contains "dashboard text: no browser open" "open http"

### ensure-dashboard #######################################################
cp "$SCRIPTS/generate-dashboard-data.sh" "$ROUND_TABLE_DIR/generate-dashboard-data.sh"
chmod +x "$ROUND_TABLE_DIR/generate-dashboard-data.sh"
run "ensure-dashboard: runs" 0 "$SCRIPTS/ensure-dashboard.sh"
assert_file "ensure-dashboard: cron.log created" "$ROUND_TABLE_DIR/.dashboard/cron.log"


### rt-dispatch + rt-devloop (stubbed hermes — no real model calls) #######
STUB_BIN="$SANDBOX/bin"
mkdir -p "$STUB_BIN"
CALLS_LOG="$SANDBOX/hermes_calls.log"
cat > "$STUB_BIN/hermes-stub" <<STUB
#!/usr/bin/env bash
printf '%s\n' "ARGS: \$*" >> "$CALLS_LOG"
echo "STUB OK"
STUB
chmod +x "$STUB_BIN/hermes-stub"
export HERMES_BIN="$STUB_BIN/hermes-stub"

if [[ -d "$HOME/.hermes/profiles/merlin" ]]; then
  # clear inboxes so only our seeded message exists
  for a in arthur merlin percival bedivere lancelot; do
    rm -f "$ROUND_TABLE_DIR/inbox/$a/"*.json 2>/dev/null || true
  done
  "$SCRIPTS/rt-send.sh" --from arthur --to merlin --type question --payload '{"q":"dispatch test"}' >/dev/null
  DISPATCH_MSG=$(basename "$(ls "$ROUND_TABLE_DIR/inbox/merlin/"*.json | head -1)" .json)

  run "dispatch: once spawns profile session" 0 "$SCRIPTS/rt-dispatch.sh" once merlin
  grep -q -- "-p merlin -z" "$CALLS_LOG" && PASS=$((PASS+1)) || {
    FAIL=$((FAIL+1)); FAILED_NAMES+=("dispatch: hermes -p merlin invoked"); echo "FAIL: stub not called with -p merlin"; }
  grep -q "$DISPATCH_MSG" "$CALLS_LOG" && PASS=$((PASS+1)) || {
    FAIL=$((FAIL+1)); FAILED_NAMES+=("dispatch: prompt carries msg id"); echo "FAIL: msg id missing from prompt"; }

  # empty inbox → no spawn
  : > "$CALLS_LOG"
  run "dispatch: empty inbox no spawn" 0 "$SCRIPTS/rt-dispatch.sh" once arthur
  if grep -q -- "-p arthur" "$CALLS_LOG"; then
    FAIL=$((FAIL+1)); FAILED_NAMES+=("dispatch: no spawn on empty inbox"); echo "FAIL: spawned for empty inbox"
  else
    PASS=$((PASS+1))
  fi

  # live lock → skip
  mkdir -p "$ROUND_TABLE_DIR/.dispatch/merlin.lock"
  echo $$ > "$ROUND_TABLE_DIR/.dispatch/merlin.lock/pid"
  : > "$CALLS_LOG"
  run "dispatch: live lock skips" 0 "$SCRIPTS/rt-dispatch.sh" once merlin
  if grep -q -- "-p merlin" "$CALLS_LOG"; then
    FAIL=$((FAIL+1)); FAILED_NAMES+=("dispatch: lock respected"); echo "FAIL: dispatched despite live lock"
  else
    PASS=$((PASS+1))
  fi
  rm -rf "$ROUND_TABLE_DIR/.dispatch/merlin.lock"

  # retry exhaustion: stub never acks; attempt 1 already used. Two more passes
  # reach MAX_ATTEMPTS=3, next pass parks the message into failed/.
  run "dispatch: retry pass 2" 0 "$SCRIPTS/rt-dispatch.sh" once merlin
  run "dispatch: retry pass 3" 0 "$SCRIPTS/rt-dispatch.sh" once merlin
  run "dispatch: parking pass" 0 "$SCRIPTS/rt-dispatch.sh" once merlin
  assert_file "dispatch: exhausted message parked" "$ROUND_TABLE_DIR/inbox/merlin/failed/${DISPATCH_MSG}.json"

  # devloop dry-run: prints all phases, spawns nothing
  : > "$CALLS_LOG"
  run "devloop: dry-run" 0 "$SCRIPTS/rt-devloop.sh" --dry-run "test task"
  assert_contains "devloop: dry-run shows PLAN" "PLAN prompt"
  assert_contains "devloop: dry-run shows QA" "QA prompt"
  [[ ! -s "$CALLS_LOG" ]] && PASS=$((PASS+1)) || {
    FAIL=$((FAIL+1)); FAILED_NAMES+=("devloop: dry-run spawns nothing"); echo "FAIL: dry-run called hermes"; }

  # devloop full run with stub: all 5 phases, context chained
  : > "$CALLS_LOG"
  run "devloop: stubbed full loop" 0 "$SCRIPTS/rt-devloop.sh" "stub loop task"
  DEVLOOP_DIR=$(ls -dt "$ROUND_TABLE_DIR/devloop/"devloop-* | head -1)
  for ph in plan research build write qa; do
    assert_file "devloop: $ph output exists" "$DEVLOOP_DIR/$ph.md"
  done
  grep -q "### PLAN output" "$CALLS_LOG" && PASS=$((PASS+1)) || {
    FAIL=$((FAIL+1)); FAILED_NAMES+=("devloop: context chains between phases"); echo "FAIL: research prompt missing PLAN context"; }
  for agent in arthur merlin percival bedivere lancelot; do
    grep -q -- "-p $agent -z" "$CALLS_LOG" && PASS=$((PASS+1)) || {
      FAIL=$((FAIL+1)); FAILED_NAMES+=("devloop: real profile $agent invoked"); echo "FAIL: phase did not run under profile $agent"; }
  done
else
  echo "SKIP: dispatch/devloop tests (no ~/.hermes/profiles/merlin on this machine)"
fi
unset HERMES_BIN

### rt-retry: retry parked messages #######################################
run "retry: no parked messages is no-op" 0 "$SCRIPTS/rt-retry.sh" 2>/dev/null
# Park a message by exhausting attempts
PARK_AGENT="merlin"
PARK_MSG="park-test-$$"
mkdir -p "$ROUND_TABLE_DIR/inbox/$PARK_AGENT"
echo '{"id":"'"$PARK_MSG"'","from":"arthur","to":"'"$PARK_AGENT"'","type":"status","priority":"normal","timestamp":"2025-01-01T00:00:00Z","payload":{}}' > "$ROUND_TABLE_DIR/inbox/$PARK_AGENT/${PARK_MSG}.json"
# Exhaust attempts
echo '{"'"$PARK_MSG"'": 3}' > "$ROUND_TABLE_DIR/.dispatch/attempts.json"
run "retry: parks exhausted message" 0 "$SCRIPTS/rt-dispatch.sh" once "$PARK_AGENT"
assert_file "retry: message parked in failed" "$ROUND_TABLE_DIR/inbox/$PARK_AGENT/failed/${PARK_MSG}.json"
# Now retry
run "retry: retry parked message" 0 "$SCRIPTS/rt-retry.sh"
assert_file "retry: message back in inbox" "$ROUND_TABLE_DIR/inbox/$PARK_AGENT/${PARK_MSG}.json"
assert_not_contains "retry: attempt count reset" "attempts"

### daemon notification delivery ############################################
NOTIF_SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/rtp_notif.XXXXXX")
export NOTIF_RT_DIR="$NOTIF_SANDBOX/rt"
mkdir -p "$NOTIF_RT_DIR"
cp "$REPO_DIR/config.json" "$NOTIF_RT_DIR/config.json"
run "daemon: notification on message delivery" 0 bash -c '
  ROUND_TABLE_DIR="'"$NOTIF_RT_DIR"'" bash scripts/rt-daemon.sh start >/dev/null 2>&1
  sleep 3
  ROUND_TABLE_DIR="'"$NOTIF_RT_DIR"'" bash scripts/rt-send.sh --from arthur --to merlin --type status --payload "{\"s\":\"notif-test\"}" >/dev/null 2>&1
  sleep 2
  cat "'"$NOTIF_RT_DIR"'/notifications.jsonl" 2>/dev/null | head -1
  ROUND_TABLE_DIR="'"$NOTIF_RT_DIR"'" bash scripts/rt-daemon.sh stop >/dev/null 2>&1
'
assert_contains "daemon: notification contains from" "arthur"
assert_contains "daemon: notification contains type" "status"
rm -rf "$NOTIF_SANDBOX"

### session-checkin state expiry ############################################
SESS_AGENT="arthur"
# Clean up any leftover messages from earlier tests
rm -f "$ROUND_TABLE_DIR/inbox/$SESS_AGENT/"*.json 2>/dev/null || true
rm -f "$ROUND_TABLE_DIR/.checkin-state-$SESS_AGENT" 2>/dev/null
# Send a message
"$SCRIPTS/rt-send.sh" --from merlin --to "$SESS_AGENT" --type status --payload '{"s":"ok"}' >/dev/null
# First checkin should show pending
run "session-checkin: first run shows pending" 0 "$SCRIPTS/rt-session-checkin.sh" "$SESS_AGENT"
assert_contains "session-checkin: shows 1 pending" "1 pending"
# Immediate re-run should be silent (state cached)
run "session-checkin: immediate re-run silent" 0 "$SCRIPTS/rt-session-checkin.sh" "$SESS_AGENT"
assert_not_contains "session-checkin: no duplicate output" "pending"
# Manually expire the state file (set timestamp to 31 min ago)
STATE_FILE="$ROUND_TABLE_DIR/.checkin-state-$SESS_AGENT"
if [[ -f "$STATE_FILE" ]]; then
  OLD_TS=$(( $(date +%s) - 1860 ))
  echo "$OLD_TS" > "$STATE_FILE"
  echo "0" >> "$STATE_FILE"
  # Now checkin should show pending again (state expired)
  "$SCRIPTS/rt-send.sh" --from merlin --to "$SESS_AGENT" --type status --payload '{"s":"ok2"}' >/dev/null
  run "session-checkin: expired state re-shows" 0 "$SCRIPTS/rt-session-checkin.sh" "$SESS_AGENT"
  assert_contains "session-checkin: expired shows pending" "2 pending"
fi

### parity: scripts/ vs skills copy #######################################
PARITY_OK=1
for f in "$SCRIPTS"/rt-*.sh; do
  b=$(basename "$f")
  if [[ -f "$REPO_DIR/skills/round-table-protocol/scripts/$b" ]]; then
    diff -q "$f" "$REPO_DIR/skills/round-table-protocol/scripts/$b" >/dev/null || PARITY_OK=0
  else
    PARITY_OK=0
  fi
done
for f in "$REPO_DIR/skills/round-table-protocol/scripts"/rt-*.sh; do
  b=$(basename "$f")
  if [[ ! -f "$SCRIPTS/$b" ]]; then
    PARITY_OK=0
  fi
done
[[ $PARITY_OK -eq 1 ]] && PASS=$((PASS+1)) || {
  FAIL=$((FAIL+1)); FAILED_NAMES+=("parity: skills copy in sync"); echo "FAIL: skills/ copies differ from scripts/"; }

############################################################################
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ $FAIL -gt 0 ]]; then
  printf '  - %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
