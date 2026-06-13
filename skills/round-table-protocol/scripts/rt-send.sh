#!/usr/bin/env bash
# rt-send.sh — Send a message via Round Table Protocol
# Usage: rt-send.sh --from <agent> --to <agent|broadcast> --type <type> --priority <level> --payload '<json>'
set -euo pipefail

ROUND_TABLE_DIR="${ROUND_TABLE_DIR:-$(eval echo ~"$(whoami)")/.hermes/round-table}"
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

AGENTS=$(python3 -c "import json,sys; print(' '.join(json.load(open(sys.argv[1]))['agents']))" "$CONFIG" 2>/dev/null \
  || echo "arthur merlin percival bedivere lancelot")

# Agent names become path components — must be registry-known and traversal-safe
validate_agent() {
  local name="$1" role="$2"
  if [[ ! "$name" =~ ^[a-z0-9_-]+$ ]]; then
    echo "Error: invalid $role agent name: $name" >&2
    exit 1
  fi
  local a
  for a in $AGENTS; do
    [[ "$a" == "$name" ]] && return 0
  done
  echo "Error: unknown $role agent: $name (known: $AGENTS)" >&2
  exit 1
}

validate_agent "$FROM" "--from"
[[ "$TO" != "broadcast" ]] && validate_agent "$TO" "--to"

MSG_ID=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || echo "msg-$(date +%s)-$$")
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Write payload to temp file so Python can read it without stdin conflicts
PAYLOAD_FILE=$(mktemp "${TMPDIR:-/tmp}/rtp_payload.XXXXXX")
cleanup_payload() { rm -f "$PAYLOAD_FILE"; }
trap cleanup_payload EXIT
printf '%s' "$PAYLOAD" > "$PAYLOAD_FILE"

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
except ValueError:
    reply_obj = reply_to

try:
    payload = json.loads(payload_raw)
except ValueError:
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
# PAYLOAD_FILE cleaned up by EXIT trap

# Write to outbox
OUTBOX_DIR="$ROUND_TABLE_DIR/outbox/$FROM"
mkdir -p "$OUTBOX_DIR"
printf '%s\n' "$MSG" > "$OUTBOX_DIR/${MSG_ID}.json"

# Deliver atomically: temp file in target dir, then mv, so a polling reader
# never sees a partial message.
deliver() {
  local inbox_dir="$ROUND_TABLE_DIR/inbox/$1"
  mkdir -p "$inbox_dir"
  local tmp
  tmp=$(mktemp "$inbox_dir/.${MSG_ID}.tmp.XXXXXX")
  cp "$OUTBOX_DIR/${MSG_ID}.json" "$tmp"
  mv "$tmp" "$inbox_dir/${MSG_ID}.json"
}

if [[ "$TO" == "broadcast" ]]; then
  COUNT=0
  for agent in $AGENTS; do
    [[ "$agent" == "$FROM" ]] && continue
    deliver "$agent"
    COUNT=$((COUNT+1))
  done
  echo "Broadcast delivered to $COUNT agents"
else
  deliver "$TO"
  echo "Message delivered to $TO ($MSG_ID)"
fi
