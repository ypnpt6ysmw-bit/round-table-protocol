#!/usr/bin/env bash
# rt-snapshot.sh — Save a context snapshot via Round Table Protocol
# Usage: rt-snapshot.sh <agent> <session_id> <summary>
set -euo pipefail

ROUND_TABLE_DIR="${ROUND_TABLE_DIR:-$HOME/.hermes/round-table}"

AGENT="${1:?Usage: rt-snapshot.sh <agent> <session_id> <summary>}"
SESSION_ID="${2:?Usage: rt-snapshot.sh <agent> <session_id> <summary>}"
SUMMARY="${3:-}"

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SNAPSHOT_ID="snap-$(date +%Y%m%d_%H%M%S)"

if [[ -z "$SUMMARY" ]]; then
  echo "Enter snapshot summary (Ctrl+D to finish):"
  SUMMARY=$(cat)
fi

export RTP_AGENT="$AGENT"
export RTP_SESSION="$SESSION_ID"
export RTP_SUMMARY="$SUMMARY"
export RTP_SNAPSHOT_ID="$SNAPSHOT_ID"
export RTP_TIMESTAMP="$TIMESTAMP"

python3 << 'PYEOF' > "$ROUND_TABLE_DIR/snapshots/${SNAPSHOT_ID}.json"
import json, os

snapshot = {
    'protocol': 'rtp/1.0',
    'type': 'context-snapshot',
    'id': os.environ['RTP_SNAPSHOT_ID'],
    'session_id': os.environ['RTP_SESSION'],
    'agent': os.environ['RTP_AGENT'],
    'timestamp': os.environ['RTP_TIMESTAMP'],
    'summary': os.environ['RTP_SUMMARY'],
    'state': {
        'decisions': [],
        'pending_work': [],
        'open_questions': [],
        'blockers': [],
        'key_findings': [],
        'files_produced': [],
        'next_steps': []
    }
}
print(json.dumps(snapshot, indent=2, ensure_ascii=False))
PYEOF

echo "Snapshot saved: $SNAPSHOT_ID"
echo "  Agent: $AGENT | Session: $SESSION_ID"
echo "  Edit: $ROUND_TABLE_DIR/snapshots/${SNAPSHOT_ID}.json"
