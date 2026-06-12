#!/usr/bin/env bash
# rt-status.sh — Update your Round Table Protocol status card
# Usage: rt-status.sh <agent> --task <desc> --status <working|blocked|idle|done> [--progress <desc>] [--blocker <desc>]
set -euo pipefail

ROUND_TABLE_DIR="${ROUND_TABLE_DIR:-$HOME/.hermes/round-table}"

AGENT="${1:?Usage: rt-status.sh <agent> --task <desc> --status <working|blocked|idle|done>}"
shift

TASK=""
STATUS="working"
PROGRESS=""
BLOCKER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) TASK="$2"; shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    --progress) PROGRESS="$2"; shift 2 ;;
    --blocker) BLOCKER="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

export RTP_AGENT="$AGENT"
export RTP_TASK="$TASK"
export RTP_STATUS="$STATUS"
export RTP_PROGRESS="$PROGRESS"
export RTP_BLOCKER="$BLOCKER"
export RTP_TIMESTAMP="$TIMESTAMP"

python3 << 'PYEOF' > "$ROUND_TABLE_DIR/status/${AGENT}.json"
import json, os

blocker_raw = os.environ.get('RTP_BLOCKER', '')
try:
    blockers = json.loads(blocker_raw) if blocker_raw else []
except:
    blockers = [blocker_raw] if blocker_raw else []

status = {
    'agent': os.environ['RTP_AGENT'],
    'timestamp': os.environ['RTP_TIMESTAMP'],
    'current_task': os.environ.get('RTP_TASK', ''),
    'status': os.environ['RTP_STATUS'],
    'progress': os.environ.get('RTP_PROGRESS', ''),
    'blockers': blockers,
    'offering': [],
    'seeking': [],
    'last_active': os.environ['RTP_TIMESTAMP']
}
print(json.dumps(status, indent=2, ensure_ascii=False))
PYEOF

echo "Status: $AGENT → $STATUS"
[[ -n "$TASK" ]] && echo "  Task: $TASK" || true
[[ -n "$BLOCKER" ]] && echo "  Blocker: $BLOCKER" || true
