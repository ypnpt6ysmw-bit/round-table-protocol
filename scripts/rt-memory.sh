#!/usr/bin/env bash
# rt-memory.sh — Shared memory layer for Round Table Protocol
# Provides a common knowledge base that all agents can read from and write to.
#
# Usage:
#   rt-memory.sh set <key> <value> [--from <agent>] [--tags <tag1,tag2>] [--ttl <hours>]
#   rt-memory.sh get <key>
#   rt-memory.sh search <query>
#   rt-memory.sh list [--agent <agent>] [--tag <tag>] [--recent <hours>]
#   rt-memory.sh delete <key>
#   rt-memory.sh clear [--agent <agent>] [--older-than <hours>]
#
# Storage: ~/.hermes/round-table/memory.jsonl (append-only log)
set -euo pipefail

ROUND_TABLE_DIR="${ROUND_TABLE_DIR:-$HOME/.hermes/round-table}"
MEMORY_FILE="$ROUND_TABLE_DIR/memory.jsonl"

mkdir -p "$ROUND_TABLE_DIR"
touch "$MEMORY_FILE"

ACTION="${1:-list}"
shift || true

case "$ACTION" in
  set)
    KEY=""
    VALUE=""
    FROM=""
    TAGS=""
    TTL=""

    # First positional arg is key
    KEY="${1:-}"
    shift || true

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --from) FROM="$2"; shift 2 ;;
        --tags) TAGS="$2"; shift 2 ;;
        --ttl) TTL="$2"; shift 2 ;;
        --payload) VALUE="$2"; shift 2 ;;
        *)
          if [[ -z "$VALUE" ]]; then
            VALUE="$1"
          fi
          shift
          ;;
      esac
    done

    [[ -z "$KEY" ]] && { echo "Error: key required" >&2; exit 1; }
    [[ -z "$VALUE" ]] && { echo "Error: value required (use --payload '<json>' or positional arg)" >&2; exit 1; }

    FROM="${FROM:-$(hostname -s | tr '[:upper:]' '[:lower:]')}"
    TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    EXPIRES=""
    if [[ -n "$TTL" ]]; then
      EXPIRES=$(date -u -v+"${TTL}H" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || python3 -c "from datetime import datetime,timezone,timedelta; print((datetime.now(timezone.utc)+timedelta(hours=int('$TTL'))).strftime('%Y-%m-%dT%H:%M:%SZ'))" 2>/dev/null || echo "")
    fi

    export RTP_KEY="$KEY" RTP_VALUE="$VALUE" RTP_FROM="$FROM" RTP_TAGS="$TAGS" RTP_TTL="$TTL" RTP_TIMESTAMP="$TIMESTAMP" RTP_EXPIRES="$EXPIRES"

    python3 << 'PYEOF' >> "$MEMORY_FILE"
import json, os, uuid

entry = {
    'id': str(uuid.uuid4()),
    'key': os.environ['RTP_KEY'],
    'value': os.environ['RTP_VALUE'],
    'from': os.environ['RTP_FROM'],
    'tags': os.environ.get('RTP_TAGS', '').split(',') if os.environ.get('RTP_TAGS') else [],
    'timestamp': os.environ['RTP_TIMESTAMP'],
    'expires': os.environ.get('RTP_EXPIRES') or None,
    'deleted': False
}
print(json.dumps(entry, ensure_ascii=False))
PYEOF

    echo "Stored: $KEY (from $FROM)"
    ;;

  get)
    KEY="${1:?Usage: rt-memory.sh get <key>}"
    python3 -c "
import json, sys
lines = open('$MEMORY_FILE').readlines()
for line in reversed(lines):
    entry = json.loads(line)
    if entry['key'] == '$KEY' and not entry['deleted']:
        print(json.dumps(entry, indent=2, ensure_ascii=False))
        sys.exit(0)
print('Key not found: $KEY', file=sys.stderr)
sys.exit(1)
"
    ;;

  search)
    QUERY="${1:?Usage: rt-memory.sh search <query>}"
    python3 -c "
import json, sys
lines = open('$MEMORY_FILE').readlines()
seen = set()
results = []
for line in reversed(lines):
    entry = json.loads(line)
    if entry['deleted'] or entry['key'] in seen:
        continue
    seen.add(entry['key'])
    haystack = entry['key'] + ' ' + str(entry.get('value', '')) + ' ' + ' '.join(entry.get('tags', []))
    if '$QUERY'.lower() in haystack.lower():
        results.append(entry)
for r in results:
    print(json.dumps(r, indent=2, ensure_ascii=False))
    print('---')
if not results:
    print('No results for: $QUERY', file=sys.stderr)
    sys.exit(1)
"
    ;;

  list)
    AGENT="" TAG="" RECENT=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --agent) AGENT="$2"; shift 2 ;;
        --tag) TAG="$2"; shift 2 ;;
        --recent) RECENT="$2"; shift 2 ;;
        *) shift ;;
      esac
    done

    python3 -c "
import json, sys
from datetime import datetime, timezone, timedelta

lines = open('$MEMORY_FILE').readlines()
seen = set()
results = []
cutoff = None
if '$RECENT':
    try:
        cutoff = datetime.now(timezone.utc) - timedelta(hours=int('$RECENT'))
    except: pass

for line in reversed(lines):
    entry = json.loads(line)
    if entry['deleted'] or entry['key'] in seen:
        continue
    seen.add(entry['key'])
    if '$AGENT' and entry['from'] != '$AGENT':
        continue
    if '$TAG' and '$TAG' not in entry.get('tags', []):
        continue
    if cutoff:
        try:
            ts = datetime.fromisoformat(entry['timestamp'].replace('Z', '+00:00'))
            if ts < cutoff:
                continue
        except: pass
    if entry.get('expires'):
        try:
            exp = datetime.fromisoformat(entry['expires'].replace('Z', '+00:00'))
            if exp < datetime.now(timezone.utc):
                continue
        except: pass
    results.append(entry)

for r in results:
    print('{:40s} | from: {:10s} | {}'.format(r['key'], r['from'], r['timestamp'][:16]))
if not results:
    print('(empty)')
"
    ;;

  delete)
    KEY="${1:?Usage: rt-memory.sh delete <key>}"
    python3 -c "
import json, uuid
entry = {
    'id': str(uuid.uuid4()),
    'key': '$KEY',
    'value': '__DELETED__',
    'from': 'system',
    'tags': [],
    'timestamp': '$(date -u +%Y-%m-%dT%H:%M:%SZ)',
    'expires': None,
    'deleted': True
}
print(json.dumps(entry, ensure_ascii=False))
" >> "$MEMORY_FILE"
    echo "Deleted: $KEY"
    ;;

  clear)
    AGENT="" OLDER=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --agent) AGENT="$2"; shift 2 ;;
        --older-than) OLDER="$2"; shift 2 ;;
        *) shift ;;
      esac
    done

    if [[ -z "$AGENT" && -z "$OLDER" ]]; then
      echo "Usage: rt-memory.sh clear --agent <name> | --older-than <hours>" >&2
      exit 1
    fi

    python3 -c "
import json, sys
from datetime import datetime, timezone, timedelta

lines = open('$MEMORY_FILE').readlines()
count = 0
new_lines = []
for line in lines:
    entry = json.loads(line)
    should_delete = False
    if '$AGENT' and entry['from'] == '$AGENT' and not entry['deleted']:
        should_delete = True
    if '$OLDER':
        try:
            ts = datetime.fromisoformat(entry['timestamp'].replace('Z', '+00:00'))
            cutoff = datetime.now(timezone.utc) - timedelta(hours=int('$OLDER'))
            if ts < cutoff and not entry['deleted']:
                should_delete = True
        except: pass
    if should_delete:
        entry['deleted'] = True
        count += 1
    new_lines.append(json.dumps(entry, ensure_ascii=False))

with open('$MEMORY_FILE', 'w') as f:
    for line in new_lines:
        f.write(line + '\n')
print(f'Marked {count} entries as deleted')
"
    ;;

  *)
    echo "Usage: rt-memory.sh set|get|search|list|delete|clear" >&2
    exit 1
    ;;
esac
