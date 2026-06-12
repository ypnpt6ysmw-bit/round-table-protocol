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
# All user-supplied values reach Python via argv/env — never via source interpolation.
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

    export RTP_KEY="$KEY" RTP_VALUE="$VALUE" RTP_FROM="$FROM" RTP_TAGS="$TAGS" RTP_TTL="$TTL" RTP_TIMESTAMP="$TIMESTAMP"

    python3 << 'PYEOF' >> "$MEMORY_FILE"
import json, os, uuid
from datetime import datetime, timezone, timedelta

ttl = os.environ.get('RTP_TTL', '')
expires = None
if ttl:
    try:
        expires = (datetime.now(timezone.utc) + timedelta(hours=float(ttl))).strftime('%Y-%m-%dT%H:%M:%SZ')
    except ValueError:
        pass

entry = {
    'id': str(uuid.uuid4()),
    'key': os.environ['RTP_KEY'],
    'value': os.environ['RTP_VALUE'],
    'from': os.environ['RTP_FROM'],
    'tags': os.environ.get('RTP_TAGS', '').split(',') if os.environ.get('RTP_TAGS') else [],
    'timestamp': os.environ['RTP_TIMESTAMP'],
    'expires': expires,
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
mem_file, key = sys.argv[1], sys.argv[2]
for line in reversed(open(mem_file).readlines()):
    line = line.strip()
    if not line:
        continue
    try:
        entry = json.loads(line)
    except ValueError:
        continue
    if entry.get('key') == key:
        # Latest entry wins: a tombstone hides all older revisions
        if entry.get('deleted'):
            break
        print(json.dumps(entry, indent=2, ensure_ascii=False))
        sys.exit(0)
print('Key not found: ' + key, file=sys.stderr)
sys.exit(1)
" "$MEMORY_FILE" "$KEY"
    ;;

  search)
    QUERY="${1:?Usage: rt-memory.sh search <query>}"
    python3 -c "
import json, sys
mem_file, query = sys.argv[1], sys.argv[2]
seen = set()
results = []
for line in reversed(open(mem_file).readlines()):
    line = line.strip()
    if not line:
        continue
    try:
        entry = json.loads(line)
    except ValueError:
        continue
    if entry.get('key') in seen:
        continue
    seen.add(entry['key'])
    # Latest entry wins: a tombstone hides all older revisions of the key
    if entry.get('deleted'):
        continue
    haystack = entry['key'] + ' ' + str(entry.get('value', '')) + ' ' + ' '.join(entry.get('tags', []))
    if query.lower() in haystack.lower():
        results.append(entry)
for r in results:
    print(json.dumps(r, indent=2, ensure_ascii=False))
    print('---')
if not results:
    print('No results for: ' + query, file=sys.stderr)
    sys.exit(1)
" "$MEMORY_FILE" "$QUERY"
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

mem_file, agent, tag, recent = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
seen = set()
results = []
cutoff = None
if recent:
    try:
        cutoff = datetime.now(timezone.utc) - timedelta(hours=float(recent))
    except ValueError:
        pass

for line in reversed(open(mem_file).readlines()):
    line = line.strip()
    if not line:
        continue
    try:
        entry = json.loads(line)
    except ValueError:
        continue
    if entry.get('key') in seen:
        continue
    seen.add(entry['key'])
    # Latest entry wins: a tombstone hides all older revisions of the key
    if entry.get('deleted'):
        continue
    if agent and entry.get('from') != agent:
        continue
    if tag and tag not in entry.get('tags', []):
        continue
    if cutoff:
        try:
            ts = datetime.fromisoformat(entry['timestamp'].replace('Z', '+00:00'))
            if ts < cutoff:
                continue
        except (KeyError, ValueError):
            pass
    if entry.get('expires'):
        try:
            exp = datetime.fromisoformat(entry['expires'].replace('Z', '+00:00'))
            if exp < datetime.now(timezone.utc):
                continue
        except ValueError:
            pass
    results.append(entry)

for r in results:
    print('{:40s} | from: {:10s} | {}'.format(r['key'], r['from'], r['timestamp'][:16]))
if not results:
    print('(empty)')
" "$MEMORY_FILE" "$AGENT" "$TAG" "$RECENT"
    ;;

  delete)
    KEY="${1:?Usage: rt-memory.sh delete <key>}"
    TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    python3 -c "
import json, sys, uuid
entry = {
    'id': str(uuid.uuid4()),
    'key': sys.argv[1],
    'value': '__DELETED__',
    'from': 'system',
    'tags': [],
    'timestamp': sys.argv[2],
    'expires': None,
    'deleted': True
}
print(json.dumps(entry, ensure_ascii=False))
" "$KEY" "$TIMESTAMP" >> "$MEMORY_FILE"
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
import json, os, sys, tempfile
from datetime import datetime, timezone, timedelta

mem_file, agent, older = sys.argv[1], sys.argv[2], sys.argv[3]
count = 0
new_lines = []
for line in open(mem_file):
    line = line.strip()
    if not line:
        continue
    try:
        entry = json.loads(line)
    except ValueError:
        new_lines.append(line)
        continue
    should_delete = False
    if agent and entry.get('from') == agent and not entry.get('deleted'):
        should_delete = True
    if older:
        try:
            ts = datetime.fromisoformat(entry['timestamp'].replace('Z', '+00:00'))
            cutoff = datetime.now(timezone.utc) - timedelta(hours=float(older))
            if ts < cutoff and not entry.get('deleted'):
                should_delete = True
        except (KeyError, ValueError):
            pass
    if should_delete:
        entry['deleted'] = True
        count += 1
    new_lines.append(json.dumps(entry, ensure_ascii=False))

# Atomic rewrite: temp file in same dir, then rename
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(mem_file), prefix='.memory.tmp.')
with os.fdopen(fd, 'w') as f:
    for line in new_lines:
        f.write(line + '\n')
os.replace(tmp, mem_file)
print(f'Marked {count} entries as deleted')
" "$MEMORY_FILE" "$AGENT" "$OLDER"
    ;;

  *)
    echo "Usage: rt-memory.sh set|get|search|list|delete|clear" >&2
    exit 1
    ;;
esac
