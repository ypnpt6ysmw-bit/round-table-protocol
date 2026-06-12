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

INBOX_DIR="$ROUND_TABLE_DIR/inbox/$AGENT"
mkdir -p "$INBOX_DIR"

case "$ACTION" in
  list)
    echo "=== Inbox: $AGENT ==="
    if [[ -z "$(ls -A "$INBOX_DIR" 2>/dev/null)" ]]; then
      echo "(empty)"
      exit 0
    fi
    for f in "$INBOX_DIR"/*.json; do
      [[ ! -f "$f" ]] && continue
      python3 -c "
import json
d = json.load(open('$f'))
print('  {}... | {:20s} | from: {:10s} | prio: {}'.format(d['id'][:12], d['type'], d['from'], d['priority']))
" 2>/dev/null
    done
    ;;
  read)
    MSG_ID="${1:-}"
    [[ -z "$MSG_ID" ]] && { echo "Error: message ID required" >&2; exit 1; }
    FILE="$INBOX_DIR/${MSG_ID}.json"
    [[ ! -f "$FILE" ]] && { echo "Message $MSG_ID not found" >&2; exit 1; }
    python3 -c "
import json
msg = json.load(open('$FILE'))
print('From:', msg['from'], '  To:', msg['to'], '  Type:', msg['type'], '  Priority:', msg['priority'])
print('Time:', msg['timestamp'], '  ID:', msg['id'])
print()
print(json.dumps(msg['payload'], indent=2, ensure_ascii=False))
"
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
