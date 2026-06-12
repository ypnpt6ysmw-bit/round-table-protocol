#!/usr/bin/env bash
# rt-daemon.sh — Round Table Protocol background daemon
# Watches all inboxes for new messages and writes notifications to a shared notification stream.
# Usage: rt-daemon.sh start|stop|status|run
#
# Single-node mode: uses fswatch (macOS) / inotifywait (Linux) to watch inbox directories.
# Falls back to polling if no file watcher is available.
set -euo pipefail

ROUND_TABLE_DIR="${ROUND_TABLE_DIR:-$HOME/.hermes/round-table}"
PIDFILE="$ROUND_TABLE_DIR/.daemon.pid"
NOTIFICATIONS="$ROUND_TABLE_DIR/notifications.jsonl"
LOGFILE="$ROUND_TABLE_DIR/.daemon.log"
CONFIG="$ROUND_TABLE_DIR/config.json"

mkdir -p "$ROUND_TABLE_DIR"
touch "$NOTIFICATIONS"

get_agents() {
  python3 -c "import json,sys; print(' '.join(json.load(open(sys.argv[1]))['agents']))" "$CONFIG" 2>/dev/null \
    || echo "arthur merlin percival bedivere lancelot"
}

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >> "$LOGFILE"
}

check_new_messages() {
  local agent="$1"
  local inbox="$ROUND_TABLE_DIR/inbox/$agent"
  [[ ! -d "$inbox" ]] && return 0

  shopt -s nullglob
  local files=("$inbox"/*.json)
  shopt -u nullglob

  local f msg_id ts
  for f in "${files[@]}"; do
    msg_id=$(basename "$f" .json)

    # Check if already notified
    if grep -qF "$msg_id" "$NOTIFICATIONS" 2>/dev/null; then
      continue
    fi

    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if python3 -c '
import json, sys
msg = json.load(open(sys.argv[1]))
notif = {
    "timestamp": sys.argv[2],
    "msg_id": msg["id"],
    "from": msg["from"],
    "to": msg["to"],
    "type": msg["type"],
    "priority": msg["priority"],
    "notified_agent": sys.argv[3]
}
print(json.dumps(notif))
' "$f" "$ts" "$agent" >> "$NOTIFICATIONS" 2>/dev/null; then
      log "Notified $agent about $msg_id"
    else
      log "WARN: unreadable message $f"
    fi
  done
}

cmd_start() {
  if [[ -f "$PIDFILE" ]]; then
    local old_pid
    old_pid=$(cat "$PIDFILE")
    if kill -0 "$old_pid" 2>/dev/null; then
      echo "Daemon already running (PID: $old_pid)"
      return 1
    fi
  fi

  log "Starting daemon"
  echo "Starting Round Table Daemon..."

  # Fully detach: redirect stdio so callers capturing our output are not
  # held open by the child, and disown so shell teardown doesn't signal it.
  nohup "$0" run >> "$LOGFILE" 2>&1 < /dev/null &
  local pid=$!
  disown "$pid" 2>/dev/null || true
  echo "$pid" > "$PIDFILE"
  echo "Daemon started (PID: $pid)"
  log "Daemon started with PID $pid"
}

cmd_stop() {
  if [[ ! -f "$PIDFILE" ]]; then
    echo "Daemon not running"
    return 1
  fi
  local pid
  pid=$(cat "$PIDFILE")
  if kill -0 "$pid" 2>/dev/null; then
    # Kill watcher/sleep children first, then the daemon itself
    pkill -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
    rm -f "$PIDFILE"
    echo "Daemon stopped (PID: $pid)"
    log "Daemon stopped"
  else
    rm -f "$PIDFILE"
    echo "Daemon was not running (stale PID file removed)"
  fi
}

cmd_status() {
  if [[ -f "$PIDFILE" ]]; then
    local pid
    pid=$(cat "$PIDFILE")
    if kill -0 "$pid" 2>/dev/null; then
      echo "Daemon running (PID: $pid)"
      local count
      count=$(wc -l < "$NOTIFICATIONS" 2>/dev/null | tr -d ' ' || echo 0)
      echo "Notifications delivered: $count"
      return 0
    fi
  fi
  echo "Daemon not running"
  return 1
}

cmd_run() {
  # Main daemon loop
  log "Daemon loop started"

  # Detect file watcher
  local watcher=""
  if command -v fswatch &>/dev/null; then
    watcher="fswatch"
  elif command -v inotifywait &>/dev/null; then
    watcher="inotifywait"
  fi

  if [[ -n "$watcher" ]]; then
    log "Using file watcher: $watcher"
    cmd_watch_loop "$watcher"
  else
    log "No file watcher available, using polling (5s interval)"
    cmd_poll_loop
  fi
}

cmd_poll_loop() {
  while true; do
    for agent in $(get_agents); do
      check_new_messages "$agent"
    done
    sleep 5
  done
}

cmd_watch_loop() {
  local watcher="$1"
  local watch_dirs=()
  for agent in $(get_agents); do
    mkdir -p "$ROUND_TABLE_DIR/inbox/$agent"
    watch_dirs+=("$ROUND_TABLE_DIR/inbox/$agent")
  done

  local agent
  if [[ "$watcher" == "fswatch" ]]; then
    fswatch -0 "${watch_dirs[@]}" 2>/dev/null | while read -r -d "" event; do
      agent=$(sed -E 's|.*/inbox/([^/]+)/.*|\1|' <<< "$event")
      [[ -n "$agent" ]] && check_new_messages "$agent"
    done
  elif [[ "$watcher" == "inotifywait" ]]; then
    inotifywait -m -r -e create -e moved_to --format '%w%f' "${watch_dirs[@]}" 2>/dev/null | while read -r event; do
      agent=$(sed -E 's|.*/inbox/([^/]+)/.*|\1|' <<< "$event")
      [[ -n "$agent" ]] && check_new_messages "$agent"
    done
  fi
}

# Handle signals
trap 'log "Daemon interrupted"; exit 0' INT TERM

case "${1:-}" in
  start)  cmd_start ;;
  stop)   cmd_stop ;;
  status) cmd_status ;;
  run)    cmd_run ;;
  *)
    echo "Usage: rt-daemon.sh start|stop|status"
    echo "  start  — Start daemon in background"
    echo "  stop   — Stop daemon"
    echo "  status — Check daemon status"
    exit 1
    ;;
esac
