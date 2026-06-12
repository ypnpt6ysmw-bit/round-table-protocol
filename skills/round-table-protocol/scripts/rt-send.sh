#!/usr/bin/env bash
# rt-send.sh — Send a message via Round Table Protocol
# Usage: rt-send.sh --from <agent> --to <agent|broadcast> --type <type> --priority <level> --payload '<json>'
set -euo pipefail

ROUND_TABLE_DIR="${ROUND_TABLE_DIR:-$HOME/.hermes/round-table}"
CONFIG="$ROUND_TABLE_DIR/config.json"

FROM=""
TO=""
TYPE=""
PRIORITY="normal"
PAYLOAD=""
REPLY_TO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) FROM="$2"; shift 2 ;;
    --to) TO="$2"; shift 2 ;;
    --type) TYPE="$2"; shift 2 ;;
    --priority) PRIORITY="$2"; shift 2 ;;
    --payload) PAYLOAD="$2"; shift 2 ;;
    --reply-to) REPLY_TO="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$FROM" ]] && { echo "Error: --from required" >&2; exit 1; }
[[ -z "$TO" ]] && { echo "Error: --to required" >&2; exit 1; }
[[ -z "$TYPE" ]] && { echo "Error: --type required" >&2; exit 1; }
[[ -z "$PAYLOAD" ]] && { echo "Error: --payload required" >&2; exit 1; }

MSG_ID=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || echo "msg-$(date +%s)-$$")
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Write payload to temp file so Python can read it without stdin conflicts
PAYLOAD_FILE=$(mktemp /tmp/rtp_payload.XXXXXX)
echo "$PAYLOAD" > "$PAYLOAD_FILE"

export RTP_MSG_ID="$MSG_ID"
export RTP_FROM="$FROM"
export RTP_TO="$TO"
export RTP_TYPE="$TYPE"
export RTP_PRIORITY="$PRIORITY"
export RTP_TIMESTAMP="$TIMESTAMP"
export RTP_REPLY_TO="$REPLY_TO"
export RTP_PAYLOAD_FILE="$PAYLOAD_FILE"

MSG=$(python3 << 'PYEOF'
import json, os

with open(os.environ['RTP_PAYLOAD_FILE']) as f:
    payload_raw = f.read()

reply_to = os.environ.get('RTP_REPLY_TO', '')

try:
    reply_obj = json.loads(reply_to) if reply_to else None
except:
    reply_obj = reply_to if reply_to else None

try:
    payload = json.loads(payload_raw)
except:
    payload = payload_raw

envelope = {
    'protocol': 'rtp/1.0',
    'id': os.environ['RTP_MSG_ID'],
    'from': os.environ['RTP_FROM'],
    'to': os.environ['RTP_TO'],
    'type': os.environ['RTP_TYPE'],
    'priority': os.environ['RTP_PRIORITY'],
    'timestamp': os.environ['RTP_TIMESTAMP'],
    'ttl': None,
    'reply_to': reply_obj,
    'payload': payload
}
print(json.dumps(envelope, indent=2, ensure_ascii=False))
PYEOF
)

rm -f "$PAYLOAD_FILE"

# Write to outbox
OUTBOX_DIR="$ROUND_TABLE_DIR/outbox/$FROM"
mkdir -p "$OUTBOX_DIR"
echo "$MSG" > "$OUTBOX_DIR/${MSG_ID}.json"

# Deliver to inbox
if [[ "$TO" == "broadcast" ]]; then
  AGENTS=$(python3 -c "import json; print(' '.join(json.load(open('$CONFIG'))['agents']))" 2>/dev/null || echo "arthur merlin percival bedivere lancelot")
  COUNT=0
  for agent in $AGENTS; do
    [[ "$agent" == "$FROM" ]] && continue
    INBOX_DIR="$ROUND_TABLE_DIR/inbox/$agent"
    mkdir -p "$INBOX_DIR"
    cp "$OUTBOX_DIR/${MSG_ID}.json" "$INBOX_DIR/${MSG_ID}.json"
    COUNT=$((COUNT+1))
  done
  echo "Broadcast delivered to $COUNT agents"
else
  INBOX_DIR="$ROUND_TABLE_DIR/inbox/$TO"
  mkdir -p "$INBOX_DIR"
  cp "$OUTBOX_DIR/${MSG_ID}.json" "$INBOX_DIR/${MSG_ID}.json"
  echo "Message delivered to $TO ($MSG_ID)"
fi
