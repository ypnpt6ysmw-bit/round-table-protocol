#!/usr/bin/env bash
# rt-checkin.sh — Check all agents' status cards and pending messages
# Usage: rt-checkin.sh <agent>
set -euo pipefail

ROUND_TABLE_DIR="${ROUND_TABLE_DIR:-$HOME/.hermes/round-table}"

AGENT="${1:?Usage: rt-checkin.sh <agent>}"
INBOX_DIR="$ROUND_TABLE_DIR/inbox/$AGENT"

echo "=== Round Table Check-in: $AGENT ==="
echo ""

# Count pending messages
PENDING=0
if [[ -d "$INBOX_DIR" ]]; then
  shopt -s nullglob
  files=("$INBOX_DIR"/*.json)
  shopt -u nullglob
  PENDING=${#files[@]}
fi
echo "Pending messages: $PENDING"
echo ""

# Show all agent status cards
echo "--- Agent Status ---"
CONFIG="$ROUND_TABLE_DIR/config.json"
AGENTS=$(python3 -c "import json,sys; print(' '.join(json.load(open(sys.argv[1]))['agents']))" "$CONFIG" 2>/dev/null || echo "arthur merlin percival bedivere lancelot")

for agent in $AGENTS; do
  STATUS_FILE="$ROUND_TABLE_DIR/status/${agent}.json"
  if [[ -f "$STATUS_FILE" ]]; then
    python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print("  {:12s} | {:10s} | {}".format(d["agent"], d["status"], d.get("current_task", "")[:50]))
' "$STATUS_FILE"
  else
    echo "  $agent: no status card"
  fi
done

# Show urgent messages
if [[ $PENDING -gt 0 ]]; then
  echo ""
  echo "--- Urgent Messages ---"
  shopt -s nullglob
  files=("$INBOX_DIR"/*.json)
  shopt -u nullglob
  python3 -c '
import json, sys
for path in sys.argv[1:]:
    try:
        d = json.load(open(path))
        if d.get("priority") in ("urgent", "high"):
            print("  [{}] {} -> {} | {}: {}".format(d["priority"], d["from"], d["to"], d["type"], str(d.get("payload", {}))[:80]))
    except Exception:
        pass
' "${files[@]}" 2>/dev/null
fi

echo ""
echo "Done. $AGENT is up to date."
