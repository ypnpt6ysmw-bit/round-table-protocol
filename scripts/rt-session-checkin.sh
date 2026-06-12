#!/usr/bin/env bash
# rt-session-checkin.sh — Run once per agent session
# Checks inbox and injects urgent messages into agent context
# Only outputs if there are new messages since last check
set -euo pipefail

AGENT="${1:?Usage: rt-session-checkin.sh <agent>}"
RT_DIR="${ROUND_TABLE_DIR:-$HOME/.hermes/round-table}"
INBOX_DIR="$RT_DIR/inbox/$AGENT"
STATUS_FILE="$RT_DIR/status/${AGENT}.json"
STATE_FILE="$RT_DIR/.checkin-state-${AGENT}"

# Read last known message count
LAST_COUNT=0
if [[ -f "$STATE_FILE" ]]; then
  SAVED_TIME=$(head -1 "$STATE_FILE" 2>/dev/null || echo "")
  SAVED_COUNT=$(tail -1 "$STATE_FILE" 2>/dev/null || echo "0")
  # Only reuse state if less than 30 min old
  if [[ -n "$SAVED_TIME" ]]; then
    NOW=$(date +%s)
    AGE=$(( NOW - SAVED_TIME ))
    if [[ $AGE -lt 1800 ]]; then
      LAST_COUNT=$SAVED_COUNT
    fi
  fi
fi

# Count current pending messages
PENDING=0
URGENT=0
URGENT_MSGS=""
if [[ -d "$INBOX_DIR" ]]; then
  for f in "$INBOX_DIR"/*.json; do
    [[ ! -f "$f" ]] && continue
    PENDING=$((PENDING+1))
    prio=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("priority",""))' "$f" 2>/dev/null)
    if [[ "$prio" == "high" || "$prio" == "urgent" ]]; then
      URGENT=$((URGENT+1))
      FROM=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["from"])' "$f" 2>/dev/null)
      TYPE=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["type"])' "$f" 2>/dev/null)
      URGENT_MSGS="$URGENT_MSGS\n  FROM: $FROM  TYPE: $TYPE"
    fi
  done
fi

# Save state (atomic write: temp file then mv to prevent race conditions)
tmp_state=$(mktemp "$RT_DIR/.checkin-state-${AGENT}.tmp.XXXXXX")
echo "$(date +%s)" > "$tmp_state"
echo "$PENDING" >> "$tmp_state"
mv "$tmp_state" "$STATE_FILE"

# Only output if there are new messages or urgent ones
if [[ $PENDING -gt $LAST_COUNT ]] || [[ $URGENT -gt 0 ]]; then
  echo "[Round Table] $AGENT: $PENDING pending ($URGENT urgent)"
  if [[ $URGENT -gt 0 ]]; then
    echo -e "[Round Table] URGENT:$URGENT_MSGS"
  fi
fi
