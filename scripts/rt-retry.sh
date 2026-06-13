#!/usr/bin/env bash
# rt-retry.sh — Retry parked messages in the Round Table Protocol
# Moves messages from inbox/<agent>/failed/ back to inbox/<agent>/
# and resets their attempt counter so dispatch can try again.
#
# Usage:
#   rt-retry.sh [agent]        # retry all parked messages for one agent
#   rt-retry.sh               # retry all parked messages for all agents
set -euo pipefail

ROUND_TABLE_DIR="${ROUND_TABLE_DIR:-$(eval echo ~"$(whoami)")/.hermes/round-table}"
DISPATCH_DIR="$ROUND_TABLE_DIR/.dispatch"
ATTEMPTS_FILE="$DISPATCH_DIR/attempts.json"
CONFIG="$ROUND_TABLE_DIR/config.json"

get_agents() {
  python3 -c "import json,sys; print(' '.join(json.load(open(sys.argv[1]))['agents']))" "$CONFIG" 2>/dev/null \
    || echo "arthur merlin percival bedivere lancelot"
}

retry_agent() {
  agent="$1"
  failed_dir="$ROUND_TABLE_DIR/inbox/$agent/failed"
  [[ ! -d "$failed_dir" ]] && return 0

  shopt -s nullglob
  files=("$failed_dir"/*.json)
  shopt -u nullglob
  [[ ${#files[@]} -eq 0 ]] && return 0

  local f msg_id moved=0
  for f in "${files[@]+"${files[@]}"}"; do
    msg_id=$(basename "$f" .json)
    # Reset attempt counter
    if [[ -f "$ATTEMPTS_FILE" ]]; then
      python3 -c "
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    data.pop(sys.argv[2], None)
    tmp = sys.argv[1] + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(data, f)
    import os
    os.replace(tmp, sys.argv[1])
except Exception:
    pass
" "$ATTEMPTS_FILE" "$msg_id" 2>/dev/null || true
    fi
    # Move back to inbox
    mv "$f" "$ROUND_TABLE_DIR/inbox/$agent/${msg_id}.json"
    moved=$((moved + 1))
    echo "  $agent: retried $msg_id"
  done
  [[ $moved -gt 0 ]] && echo "  $agent: $moved messages retried"
}

if [[ $# -ge 1 ]]; then
  retry_agent "$1"
else
  for agent in $(get_agents); do
    retry_agent "$agent"
  done
fi
