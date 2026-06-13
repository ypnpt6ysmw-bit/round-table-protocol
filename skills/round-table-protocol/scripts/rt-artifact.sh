#!/usr/bin/env bash
# rt-artifact.sh — Register an artifact via Round Table Protocol
# Usage: rt-artifact.sh <agent> --file <path> --description <desc> [--for <agent>] [--context <ctx>] [--status <draft|complete|superseded>]
set -euo pipefail

ROUND_TABLE_DIR="${ROUND_TABLE_DIR:-$(eval echo ~"$(whoami)")/.hermes/round-table}"

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

# Atomic write: temp file then rename
ART_DIR="$ROUND_TABLE_DIR/artifacts"
mkdir -p "$ART_DIR"
TMP_FILE=$(mktemp "$ART_DIR/.${ARTIFACT_ID}.tmp.XXXXXX")
cleanup_tmp() { rm -f "$TMP_FILE"; }
trap cleanup_tmp EXIT

python3 << 'PYEOF' > "$TMP_FILE"
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

mv "$TMP_FILE" "$ART_DIR/${ARTIFACT_ID}.json"

echo "Artifact registered: $ARTIFACT_ID"
echo "  File: $FILE_PATH | Status: $STATUS"

if [[ -n "$FOR_AGENT" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  # Build payload with json.dumps so quotes in description can't break the JSON
  NOTIFY_PAYLOAD=$(python3 -c "
import json, sys
print(json.dumps({'artifact_id': sys.argv[1], 'file': sys.argv[2], 'description': sys.argv[3]}))
" "$ARTIFACT_ID" "$FILE_PATH" "$DESCRIPTION")
  if ROUND_TABLE_DIR="$ROUND_TABLE_DIR" "$SCRIPT_DIR/rt-send.sh" \
    --from "$AGENT" --to "$FOR_AGENT" --type artifact --priority normal \
    --payload "$NOTIFY_PAYLOAD" >/dev/null; then
    echo "  Notification sent to $FOR_AGENT"
  else
    echo "  Warning: notification to $FOR_AGENT failed" >&2
  fi
fi
