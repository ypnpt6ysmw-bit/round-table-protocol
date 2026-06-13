#!/usr/bin/env bash
# rt-dispatch.sh — Round Table dispatcher: delivers inbox messages to REAL agents.
#
# This is the missing consumer of the RTP mailbox. For every agent with unread
# messages it spawns an actual Hermes session under that agent's profile
# (hermes -p <agent>), so each knight runs with its own SOUL.md, skills and
# model (ARTHUR=Opus, MERLIN=Gemini, ...). Not subagents — separate profile
# sessions.
#
# Usage:
#   rt-dispatch.sh once             # single pass: process all agents with mail
#   rt-dispatch.sh once <agent>     # single pass for one agent
#   rt-dispatch.sh start|stop|status# polling daemon (30s interval)
#   rt-dispatch.sh run              # foreground daemon loop
#
# Env:
#   ROUND_TABLE_DIR  protocol root (default ~/.hermes/round-table)
#   HERMES_BIN       hermes binary (default: hermes) — tests stub this
#   RT_DISPATCH_TIMEOUT  seconds per agent session (default 600)
set -euo pipefail

# Resolve real user home (Hermes profile may override $HOME)
_REAL_USER_HOME="$(eval echo ~"$(whoami)")"

ROUND_TABLE_DIR="${ROUND_TABLE_DIR:-$HOME/.hermes/round-table}"
CONFIG="$ROUND_TABLE_DIR/config.json"
HERMES_BIN="${HERMES_BIN:-hermes}"
DISPATCH_DIR="$ROUND_TABLE_DIR/.dispatch"
PIDFILE="$DISPATCH_DIR/.dispatcher.pid"
ATTEMPTS_FILE="$DISPATCH_DIR/attempts.json"
TIMEOUT_SECS="${RT_DISPATCH_TIMEOUT:-600}"
MAX_ATTEMPTS=3
POLL_INTERVAL=30
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$DISPATCH_DIR"

get_agents() {
  python3 -c "import json,sys; print(' '.join(json.load(open(sys.argv[1]))['agents']))" "$CONFIG" 2>/dev/null \
    || echo "arthur merlin percival bedivere lancelot"
}

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >> "$DISPATCH_DIR/dispatch.log"
}

# Attempt tracking: skip messages that already failed MAX_ATTEMPTS sessions,
# parking them in inbox/<agent>/failed/ so they stop burning model calls.
bump_attempts() {  # bump_attempts <agent> <msg ids...> -> prints ids still eligible
  local agent="$1"; shift
  python3 -c '
import json, os, sys
attempts_file, agent, max_attempts = sys.argv[1], sys.argv[2], int(sys.argv[3])
ids = sys.argv[4:]
try:
    data = json.load(open(attempts_file))
except (OSError, ValueError):
    data = {}
eligible = []
for mid in ids:
    n = data.get(mid, 0)
    if n >= max_attempts:
        continue
    data[mid] = n + 1
    eligible.append(mid)
tmp = attempts_file + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f)
os.replace(tmp, attempts_file)
print(" ".join(eligible))
' "$ATTEMPTS_FILE" "$agent" "$MAX_ATTEMPTS" "$@"
}

park_exhausted() {  # move messages past MAX_ATTEMPTS to failed/
  local agent="$1" inbox="$ROUND_TABLE_DIR/inbox/$1"
  python3 -c '
import json, os, sys, shutil
attempts_file, inbox, max_attempts = sys.argv[1], sys.argv[2], int(sys.argv[3])
try:
    data = json.load(open(attempts_file))
except (OSError, ValueError):
    sys.exit(0)
failed_dir = os.path.join(inbox, "failed")
for mid, n in data.items():
    src = os.path.join(inbox, mid + ".json")
    if n >= max_attempts and os.path.isfile(src):
        os.makedirs(failed_dir, exist_ok=True)
        shutil.move(src, os.path.join(failed_dir, mid + ".json"))
        print("parked: " + mid)
' "$ATTEMPTS_FILE" "$inbox" "$MAX_ATTEMPTS"
}

unread_ids() {  # print msg ids in agent inbox (top level only)
  local inbox="$ROUND_TABLE_DIR/inbox/$1"
  [[ -d "$inbox" ]] || return 0
  local f
  shopt -s nullglob
  for f in "$inbox"/*.json; do
    basename "$f" .json
  done
  shopt -u nullglob
}

build_prompt() {  # build_prompt <agent> <msg id list...>
  local agent="$1"; shift
  local rt="$ROUND_TABLE_DIR"
  local agent_uc
  agent_uc=$(printf '%s' "$agent" | tr '[:lower:]' '[:upper:]')

  # Read role info from config.json
  local role_info
  role_info=$(python3 -c "
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
    roles = cfg.get('roles', {})
    r = roles.get(sys.argv[2], {})
    caps = ', '.join(r.get('capabilities', []))
    accepts = ', '.join(r.get('accepts_types', []))
    print(f\"Role: {r.get('title', 'Unknown')}\")
    print(f\"Your capabilities: {caps}\")
    print(f\"Message types you accept: {accepts}\")
except Exception as e:
    print(f'Role: {sys.argv[2]}')
" "$CONFIG" "$agent" 2>/dev/null || echo "Role: $agent_uc")

  cat <<PROMPT
You are ${agent_uc}, a knight of the Round Table multi-agent system. Your role
and personality are defined in your SOUL.md. You have $# unread Round Table
message(s) waiting.

${role_info}

Protocol scripts (run with bash, ROUND_TABLE_DIR=$rt is already set):
  $SCRIPT_DIR/rt-inbox.sh $agent list
  $SCRIPT_DIR/rt-inbox.sh $agent read <id>
  $SCRIPT_DIR/rt-inbox.sh $agent ack <id>
  $SCRIPT_DIR/rt-send.sh --from $agent --to <agent> --type <type> --payload '<json>'
  $SCRIPT_DIR/rt-status.sh $agent --task "<desc>" --status <working|blocked|idle|done>
  $SCRIPT_DIR/rt-memory.sh get|set|search ...

Unread message ids: $*

For EACH message, in order:
1. Read it: rt-inbox.sh $agent read <id>
2. Act on it according to your role:
   - If the task MATCHES your capabilities: do the work, send a reply.
   - If the task DOES NOT MATCH your role: send a task-reject reply with
     {"reason": "not_my_role", "suggested_agent": "<who_should_handle_this>"}
     Use rt-send.sh --type task-reject to the original sender.
   Questions and task-offers expect a reply: send one with rt-send.sh
   (use --reply-to '<id>'). Findings/status updates may just need
   acknowledgment. Do real work when a task is actionable now; if it is
   too large for this session, reply with a plan and what you need.
3. Acknowledge it: rt-inbox.sh $agent ack <id>

When done: update your status card with rt-status.sh, and store any durable
findings with rt-memory.sh set. Be concise. Do not invent messages that are
not in the inbox.
PROMPT
}

dispatch_agent() {  # dispatch_agent <agent> -> spawn real profile session
  local agent="$1"
  local lock="$DISPATCH_DIR/$agent.lock"
  local agent_log="$DISPATCH_DIR/$agent.log"

  # Per-agent lock (atomic mkdir). Stale if owning pid is gone.
  if ! mkdir "$lock" 2>/dev/null; then
    local owner=""
    owner=$(cat "$lock/pid" 2>/dev/null || true)
    if [[ -n "$owner" ]] && kill -0 "$owner" 2>/dev/null; then
      log "$agent: dispatch already running (pid $owner), skipping"
      return 0
    fi
    rm -rf "$lock"
    mkdir "$lock" 2>/dev/null || return 0
  fi
  echo $$ > "$lock/pid"

  # shellcheck disable=SC2064
  trap "rm -rf '$lock'" RETURN

  park_exhausted "$agent" | while read -r line; do log "$agent: $line"; done

  local ids
  ids=$(unread_ids "$agent")
  if [[ -z "$ids" ]]; then
    return 0
  fi

  # Drop messages that exhausted their attempts
  local eligible
  # shellcheck disable=SC2086
  eligible=$(bump_attempts "$agent" $ids)
  if [[ -z "$eligible" ]]; then
    log "$agent: all unread messages exhausted retries"
    return 0
  fi

  if [[ ! -d "$_REAL_USER_HOME/.hermes/profiles/$agent" ]]; then
    log "$agent: ERROR no Hermes profile at $_REAL_USER_HOME/.hermes/profiles/$agent"
    return 1
  fi

  local prompt
  # shellcheck disable=SC2086
  prompt=$(build_prompt "$agent" $eligible)

  log "$agent: spawning profile session for messages: $eligible"
  local start rc=0
  start=$(date +%s)

  # Real agent session: own profile = own SOUL.md + own model.
  if command -v timeout >/dev/null 2>&1; then
    ROUND_TABLE_DIR="$ROUND_TABLE_DIR" timeout "$TIMEOUT_SECS" \
      "$HERMES_BIN" -p "$agent" -z "$prompt" >> "$agent_log" 2>&1 < /dev/null || rc=$?
  else
    ROUND_TABLE_DIR="$ROUND_TABLE_DIR" \
      "$HERMES_BIN" -p "$agent" -z "$prompt" >> "$agent_log" 2>&1 < /dev/null || rc=$?
  fi

  local dur=$(( $(date +%s) - start ))
  if [[ $rc -eq 0 ]]; then
    log "$agent: session finished in ${dur}s"
  else
    log "$agent: session FAILED (exit $rc) after ${dur}s — see $agent_log"
  fi

  # Check for task-reject messages in the agent's outbox and re-route
  handle_rejects "$agent"
  return 0
}

handle_rejects() {  # handle_rejects <agent> — scan outbox for task-reject, re-route
  local agent="$1"
  local outbox="$ROUND_TABLE_DIR/outbox/$agent"
  [[ ! -d "$outbox" ]] && return 0

  shopt -s nullglob
  local files=("$outbox"/*.json)
  shopt -u nullglob
  [[ ${#files[@]} -eq 0 ]] && return 0

  local f
  for f in "${files[@]+"${files[@]}"}"; do
    python3 -c '
import json, os, sys
try:
    msg = json.load(open(sys.argv[1]))
    if msg.get("type") == "task-reject":
        payload = msg.get("payload", {})
        suggested = payload.get("suggested_agent", "")
        original_to = msg.get("to", "")
        reason = payload.get("reason", "unknown")
        reply_to = msg.get("reply_to", "")
        print(f"REJECT|{suggested}|{original_to}|{reason}|{reply_to}")
except (ValueError, OSError):
    pass
' "$f" 2>/dev/null | while IFS='|' read -r _ suggested original_to reason reply_to; do
      [[ -z "$suggested" ]] && continue
      log "$agent: task-reject (reason: $reason) — re-routing to $suggested"
      # Re-send the original message to the suggested agent
      local orig_msg="$ROUND_TABLE_DIR/outbox/$original_to/$(basename "$f" .json).json"
      if [[ -f "$orig_msg" ]]; then
        local inbox_dir="$ROUND_TABLE_DIR/inbox/$suggested"
        mkdir -p "$inbox_dir"
        local tmp
        tmp=$(mktemp "$inbox_dir/.reroute.XXXXXX")
        cp "$orig_msg" "$tmp"
        mv "$tmp" "$inbox_dir/$(basename "$f" .json).json"
        log "$agent: re-routed message to $suggested inbox"
      fi
    done
  done
}

pass_once() {
  local only="${1:-}"
  local agent
  for agent in $(get_agents); do
    [[ -n "$only" && "$agent" != "$only" ]] && continue
    dispatch_agent "$agent"
  done
}

cmd_start() {
  if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "Dispatcher already running (PID: $(cat "$PIDFILE"))"
    return 1
  fi
  nohup "$0" run >> "$DISPATCH_DIR/dispatch.log" 2>&1 < /dev/null &
  local pid=$!
  disown "$pid" 2>/dev/null || true
  echo "$pid" > "$PIDFILE"
  echo "Dispatcher started (PID: $pid)"
  log "Dispatcher started with PID $pid"
}

cmd_stop() {
  if [[ ! -f "$PIDFILE" ]]; then
    echo "Dispatcher not running"
    return 1
  fi
  local pid
  pid=$(cat "$PIDFILE")
  if kill -0 "$pid" 2>/dev/null; then
    pkill -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
    rm -f "$PIDFILE"
    echo "Dispatcher stopped (PID: $pid)"
    log "Dispatcher stopped"
  else
    rm -f "$PIDFILE"
    echo "Dispatcher was not running (stale PID file removed)"
  fi
}

cmd_status() {
  local running=0
  if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "Dispatcher running (PID: $(cat "$PIDFILE"))"
    running=1
  else
    echo "Dispatcher not running"
  fi
  local agent count
  for agent in $(get_agents); do
    count=$(unread_ids "$agent" | wc -l | tr -d ' ')
    [[ "$count" -gt 0 ]] && echo "  $agent: $count unread"
  done
  [[ $running -eq 1 ]]
}

cmd_run() {
  log "Dispatcher loop started (interval ${POLL_INTERVAL}s)"
  while true; do
    pass_once
    sleep "$POLL_INTERVAL"
  done
}

case "${1:-}" in
  once)   pass_once "${2:-}" ;;
  start)  cmd_start ;;
  stop)   cmd_stop ;;
  status) cmd_status ;;
  run)    cmd_run ;;
  *)
    echo "Usage: rt-dispatch.sh once [agent] | start | stop | status"
    echo "  once [agent] — single dispatch pass (all agents, or one)"
    echo "  start/stop   — background polling daemon (${POLL_INTERVAL}s)"
    echo "  status       — daemon state + unread counts"
    exit 1
    ;;
esac
