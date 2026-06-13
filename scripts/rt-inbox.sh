#!/usr/bin/env bash
# rt-inbox.sh — Check and read messages from Round Table Protocol inbox
# Usage: rt-inbox.sh <agent> list|read <id>|ack <id>
set -euo pipefail

ROUND_TABLE_DIR="${ROUND_TABLE_DIR:-$HOME/.hermes/round-table}"
ACTION="list"
AGENT=""
MSG_ID=""

# Parse arguments
if [[ $# -ge 1 ]]; then
  if [[ "$1" == "list" || "$1" == "read" || "$1" == "ack" ]]; then
    ACTION="$1"
    shift
  else
    AGENT="$1"
    shift
    if [[ $# -ge 1 ]]; then
      ACTION="$1"
      shift
    fi
  fi
fi

if [[ -z "$AGENT" ]]; then
  echo "Error: agent id required" >&2
  echo "Usage: rt-inbox.sh <agent> list|read <id>|ack <id>" >&2
  exit 1
fi

if [[ ! "$AGENT" =~ ^[a-z0-9_-]+$ ]]; then
  echo "Error: invalid agent name: $AGENT" >&2
  exit 1
fi

INBOX_DIR="$ROUND_TABLE_DIR/inbox/$AGENT"
mkdir -p "$INBOX_DIR"

case "$ACTION" in
  list)
    echo "=== Inbox: $AGENT ==="
    shopt -s nullglob
    FILES=("$INBOX_DIR"/*.json)
    shopt -u nullglob
    if [[ ${#FILES[@]} -eq 0 ]]; then
      echo "(empty)"
      exit 0
    fi
    python3 -c "
import json, sys
for path in sys.argv[1:]:
    try:
        d = json.load(open(path))
        print('  {}... | {:20s} | from: {:10s} | prio: {}'.format(d['id'][:12], d['type'], d['from'], d['priority']))
    except Exception as e:
        print('  [unreadable] {}: {}'.format(path, e), file=sys.stderr)
" "${FILES[@]}"
    ;;
  read)
    MSG_ID="${1:-}"
    [[ -z "$MSG_ID" ]] && { echo "Error: message ID required" >&2; exit 1; }
    FILE="$INBOX_DIR/${MSG_ID}.json"
    [[ ! -f "$FILE" ]] && { echo "Message $MSG_ID not found" >&2; exit 1; }
    python3 -c "
import json, sys
msg = json.load(open(sys.argv[1]))
print('From:', msg['from'], '  To:', msg['to'], '  Type:', msg['type'], '  Priority:', msg['priority'])
print('Time:', msg['timestamp'], '  ID:', msg['id'])
print()
print(json.dumps(msg['payload'], indent=2, ensure_ascii=False))
" "$FILE"
    ;;
  ack)
    MSG_ID="${1:-}"
    [[ -z "$MSG_ID" ]] && { echo "Error: message ID required" >&2; exit 1; }
    FILE="$INBOX_DIR/${MSG_ID}.json"
    [[ ! -f "$FILE" ]] && { echo "Message $MSG_ID not found" >&2; exit 1; }
    ARCHIVE_DIR="$INBOX_DIR/archived"
    mkdir -p "$ARCHIVE_DIR"
    mv "$FILE" "$ARCHIVE_DIR/${MSG_ID}.json"
    echo "Acknowledged: $MSG_ID"
    ;;
  *) echo "Usage: rt-inbox.sh <agent> list|read <id>|ack <id>" >&2; exit 1 ;;
esac
