#!/usr/bin/env bash
# rt-watch.sh — Monitor Round Table Protocol activity in real-time
# Usage: rt-watch.sh [--follow] [--agent <agent>] [--recent <seconds>]
#
# Without --follow: shows a snapshot of current activity
# With --follow:    tail -f style monitoring (checks every 2s)
set -euo pipefail

ROUND_TABLE_DIR="${ROUND_TABLE_DIR:-$HOME/.hermes/round-table}"
FOLLOW=0
AGENT=""
RECENT=300  # default: last 5 minutes

while [[ $# -gt 0 ]]; do
  case "$1" in
    --follow) FOLLOW=1; shift ;;
    --agent) AGENT="$2"; shift 2 ;;
    --recent) RECENT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

show_snapshot() {
  echo "=== Round Table Pulse Check ==="
  echo "  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""

  # Status cards
  echo "--- Agents ---"
  for agent in arthur merlin percival bedivere lancelot; do
    status_file="$ROUND_TABLE_DIR/status/${agent}.json"
    if [[ -f "$status_file" ]]; then
      python3 -c "
import json
d = json.load(open('$status_file'))
print('  {:12s} | {:10s} | {:50s}'.format(d['agent'], d['status'], d.get('current_task', '')[:50]))
"
    else
      echo "  $agent: (no status)"
    fi
  done

  # Pending messages
  echo ""
  echo "--- Pending Messages ---"
  for agent in arthur merlin percival bedivere lancelot; do
    [[ -n "$AGENT" ]] && [[ "$agent" != "$AGENT" ]] && continue
    inbox="$ROUND_TABLE_DIR/inbox/$agent"
    if [[ -d "$inbox" ]]; then
      pending=0
      urgent=0
      for f in "$inbox"/*.json; do
        [[ ! -f "$f" ]] && continue
        pending=$((pending+1))
        prio=$(python3 -c "import json; d=json.load(open('$f')); print(d.get('priority',''))" 2>/dev/null)
        [[ "$prio" == "urgent" ]] && urgent=$((urgent+1))
      done
      if [[ $pending -gt 0 ]]; then
        echo "  $agent: $pending messages ($urgent urgent)"
      fi
    fi
  done

  # Shared memory
  echo ""
  echo "--- Shared Memory ---"
  mem_file="$ROUND_TABLE_DIR/memory.jsonl"
  if [[ -f "$mem_file" ]]; then
    active=$(grep -cv '"deleted": true' "$mem_file" 2>/dev/null || echo 0)
    total=$(wc -l < "$mem_file" 2>/dev/null || echo 0)
    echo "  $active active entries (of $total total)"

    # Show recent entries
    tail -3 "$mem_file" 2>/dev/null | python3 -c "
import json, sys
for line in sys.stdin:
    entry = json.loads(line)
    if not entry['deleted']:
        print('  {:40s} | from: {:10s} | tags: {}'.format(entry['key'], entry['from'], entry.get('tags', [])))
" 2>/dev/null || true
  fi

  # Recent notifications
  echo ""
  echo "--- Recent Notifications ---"
  notif_file="$ROUND_TABLE_DIR/notifications.jsonl"
  if [[ -f "$notif_file" ]]; then
    tail -3 "$notif_file" 2>/dev/null | python3 -c "
import json, sys
for line in sys.stdin:
    n = json.loads(line)
    print('  {} -> {:10s} | {:20s} | {}'.format(n.get('from','?'), n.get('notified_agent','?'), n.get('type',''), n.get('timestamp','')[:16]))
" 2>/dev/null || echo "  (none)"
  fi
}

if [[ $FOLLOW -eq 1 ]]; then
  echo "Watching Round Table activity (Ctrl+C to stop)..."
  while true; do
    clear
    show_snapshot
    sleep 2
  done
else
  show_snapshot
fi
