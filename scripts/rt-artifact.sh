#!/usr/bin/env bash
# rt-artifact.sh — Register an artifact via Round Table Protocol
# Usage: rt-artifact.sh <agent> --file <path> --description <desc> [--for <agent>] [--context <ctx>] [--status <draft|complete|superseded>]
set -euo pipefail

ROUND_TABLE_DIR="${ROUND_TABLE_DIR:-$HOME/.hermes/round-table}"

AGENT="${1:?Usage: rt-artifact.sh <agent> --file <path> --description <desc>}"
shift

FILE_PATH=""
DESCRIPTION=""
FOR_AGENT=""
CONTEXT=""
STATUS="complete"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) FILE_PATH="$2"; shift 2 ;;
    --description|--desc) DESCRIPTION="$2"; shift 2 ;;
    --for) FOR_AGENT="$2"; shift 2 ;;
    --context) CONTEXT="$2"; shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$FILE_PATH" ]] && { echo "Error: --file required" >&2; exit 1; }
[[ -z "$DESCRIPTION" ]] && { echo "Error: --description required" >&2; exit 1; }

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ARTIFACT_ID="art-$(date +%Y%m%d_%H%M%S)"

export RTP_AGENT="$AGENT"
export RTP_FILE="$FILE_PATH"
export RTP_DESC="$DESCRIPTION"
export RTP_FOR="$FOR_AGENT"
export RTP_CONTEXT="$CONTEXT"
export RTP_STATUS="$STATUS"
export RTP_ARTIFACT_ID="$ARTIFACT_ID"
export RTP_TIMESTAMP="$TIMESTAMP"

python3 << 'PYEOF' > "$ROUND_TABLE_DIR/artifacts/${ARTIFACT_ID}.json"
import json, os

produced_for = os.environ.get('RTP_FOR', '') or None

artifact = {
    'protocol': 'rtp/1.0',
    'type': 'artifact',
    'id': os.environ['RTP_ARTIFACT_ID'],
    'agent': os.environ['RTP_AGENT'],
    'timestamp': os.environ['RTP_TIMESTAMP'],
    'file_path': os.environ['RTP_FILE'],
    'description': os.environ['RTP_DESC'],
    'produced_for': produced_for,
    'context': os.environ.get('RTP_CONTEXT', ''),
    'dependencies': [],
    'status': os.environ['RTP_STATUS']
}
print(json.dumps(artifact, indent=2, ensure_ascii=False))
PYEOF

echo "Artifact registered: $ARTIFACT_ID"
echo "  File: $FILE_PATH | Status: $STATUS"

if [[ -n "$FOR_AGENT" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  ROUND_TABLE_DIR="$ROUND_TABLE_DIR" "$SCRIPT_DIR/rt-send.sh" \
    --from "$AGENT" --to "$FOR_AGENT" --type artifact --priority normal \
    --payload "{\"artifact_id\": \"$ARTIFACT_ID\", \"file\": \"$FILE_PATH\", \"description\": \"$DESCRIPTION\"}" 2>/dev/null || true
  echo "  Notification sent to $FOR_AGENT"
fi
