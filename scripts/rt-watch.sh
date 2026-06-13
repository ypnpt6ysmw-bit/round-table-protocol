#!/usr/bin/env bash
# rt-watch.sh — Monitor Round Table Protocol activity in real-time
# Usage: rt-watch.sh [--follow] [--agent <agent>]
#
# Without --follow: shows a snapshot of current activity
# With --follow:    tail -f style monitoring (checks every 2s)
set -euo pipefail

ROUND_TABLE_DIR="${ROUND_TABLE_DIR:-$HOME/.hermes/round-table}"
CONFIG="$ROUND_TABLE_DIR/config.json"
FOLLOW=0
AGENT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --follow) FOLLOW=1; shift ;;
    --agent) AGENT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

AGENTS=$(python3 -c "import json,sys; print(' '.join(json.load(open(sys.argv[1]))['agents']))" "$CONFIG" 2>/dev/null \
  || echo "arthur merlin percival bedivere lancelot")

show_snapshot() {
  echo "=== Round Table Pulse Check ==="
  echo "  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""

  # Status cards
  echo "--- Agents ---"
  for agent in $AGENTS; do
    status_file="$ROUND_TABLE_DIR/status/${agent}.json"
    if [[ -f "$status_file" ]]; then
      python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print('  {:12s} | {:10s} | {:50s}'.format(d['agent'], d['status'], d.get('current_task', '')[:50]))
" "$status_file"
    else
      echo "  $agent: (no status)"
    fi
  done

  # Pending messages
  echo ""
  echo "--- Pending Messages ---"
  for agent in $AGENTS; do
    [[ -n "$AGENT" ]] && [[ "$agent" != "$AGENT" ]] && continue
    inbox="$ROUND_TABLE_DIR/inbox/$agent"
    if [[ -d "$inbox" ]]; then
      shopt -s nullglob
      files=("$inbox"/*.json)
      shopt -u nullglob
      pending=${#files[@]}
      if [[ $pending -gt 0 ]]; then
        urgent=$(python3 -c '
import json, sys
count = 0
for path in sys.argv[1:]:
    try:
        with open(path) as f:
            if json.load(f).get("priority") == "urgent":
                count += 1
    except Exception:
        pass
print(count)
' "${files[@]}")
        echo "  $agent: $pending messages ($urgent urgent)"
      fi
    fi
  done

  # Shared memory
  echo ""
  echo "--- Shared Memory ---"
  mem_file="$ROUND_TABLE_DIR/memory.jsonl"
  if [[ -f "$mem_file" ]]; then
    python3 -c "
import json, sys
total = active = 0
recent = []
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    total += 1
    try:
        entry = json.loads(line)
    except ValueError:
        continue
    if not entry.get('deleted'):
        active += 1
        recent.append(entry)
print('  {} active entries (of {} total)'.format(active, total))
for entry in recent[-3:]:
    print('  {:40s} | from: {:10s} | tags: {}'.format(entry.get('key',''), entry.get('from',''), entry.get('tags', [])))
" "$mem_file"
  fi

  # Recent notifications
  echo ""
  echo "--- Recent Notifications ---"
  notif_file="$ROUND_TABLE_DIR/notifications.jsonl"
  if [[ -f "$notif_file" ]]; then
    tail -3 "$notif_file" 2>/dev/null | python3 -c "
import json, sys
shown = False
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        n = json.loads(line)
    except ValueError:
        continue
    shown = True
    print('  {} -> {:10s} | {:20s} | {}'.format(n.get('from','?'), n.get('notified_agent','?'), n.get('type',''), n.get('timestamp','')[:16]))
if not shown:
    print('  (none)')
" || echo "  (none)"
  fi
}

if [[ $FOLLOW -eq 1 ]]; then
  echo "Watching Round Table activity (Ctrl+C to stop)..."
  while true; do
    tput clear 2>/dev/null || printf '\033[2J\033[H'
    show_snapshot
    sleep 2
  done
else
  show_snapshot
fi
