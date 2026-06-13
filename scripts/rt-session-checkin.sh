#!/usr/bin/env bash
# rt-session-checkin.sh — Run once per agent session
# Checks inbox and injects urgent messages into agent context
# Only outputs if there are new messages since last check
set -euo pipefail

AGENT="${1:?Usage: rt-session-checkin.sh <agent>}"
RT_DIR="${ROUND_TABLE_DIR:-$(eval echo ~"$(whoami)")/.hermes/round-table}"
INBOX_DIR="$RT_DIR/inbox/$AGENT"
STATE_FILE="$RT_DIR/.checkin-state-${AGENT}"

# Read last known message count from state file
# State file format: "timestamp\ncount\n" (two lines)
LAST_COUNT=0
if [[ -f "$STATE_FILE" ]]; then
  # Read both lines atomically
  state_content=$(cat "$STATE_FILE" 2>/dev/null || echo "")
  if [[ -n "$state_content" ]]; then
    # Extract first line (timestamp) and second line (count)
    saved_time=$(echo "$state_content" | sed -n '1p')
    saved_count=$(echo "$state_content" | sed -n '2p')
    # Only reuse state if less than 30 min old and both values present
    if [[ -n "$saved_time" && -n "$saved_count" ]]; then
      now=$(date +%s)
      age=$(( now - saved_time ))
      if [[ $age -lt 1800 ]]; then
        LAST_COUNT=$saved_count
      fi
    fi
  fi
fi

# Count current pending messages
PENDING=0
URGENT=0
URGENT_MSGS=""
if [[ -d "$INBOX_DIR" ]]; then
  shopt -s nullglob
  files=("$INBOX_DIR"/*.json)
  shopt -u nullglob
  PENDING=${#files[@]}
  if [[ $PENDING -gt 0 ]]; then
    python_out=$(python3 -c '
import json, sys
urgent = 0
urgent_msgs = []
for path in sys.argv[1:]:
    try:
        with open(path) as f:
            d = json.load(f)
            prio = d.get("priority", "")
            if prio in ("high", "urgent"):
                urgent += 1
                urgent_msgs.append("  FROM: {}  TYPE: {}".format(d.get("from", "?"), d.get("type", "?")))
    except Exception:
        pass
print(urgent)
for msg in urgent_msgs:
    print(msg)
' "${files[@]}")
    URGENT=$(echo "$python_out" | head -n 1)
    if [[ "$URGENT" -gt 0 ]]; then
      # Format urgent messages with leading newline to match original output
      URGENT_LINES=$(echo "$python_out" | tail -n +2)
      URGENT_MSGS=$(printf "\n%s" "$URGENT_LINES")
    fi
  fi
fi

# Save state (atomic write: temp file then mv to prevent race conditions)
tmp_state=$(mktemp "$RT_DIR/.checkin-state-${AGENT}.tmp.XXXXXX")
cleanup_tmp() { rm -f "$tmp_state"; }
trap cleanup_tmp EXIT
date +%s > "$tmp_state"
echo "$PENDING" >> "$tmp_state"
mv "$tmp_state" "$STATE_FILE"

# Only output if there are new messages or urgent ones
if [[ $PENDING -gt $LAST_COUNT ]] || [[ $URGENT -gt 0 ]]; then
  echo "[Round Table] $AGENT: $PENDING pending ($URGENT urgent)"
  if [[ $URGENT -gt 0 ]]; then
    printf "[Round Table] URGENT:%s\n" "$URGENT_MSGS"
  fi
fi
