#!/usr/bin/env bash
# rt-cleanup.sh — Message lifecycle management for Round Table Protocol
# Usage: rt-cleanup.sh [--dry-run] [--older-than <hours>] [--keep-last <n>]
#
# --older-than N : archive inbox messages / delete outbox+snapshots+artifacts older than N hours
# --keep-last N  : per inbox, archive everything except the N newest messages
# Both filters may be combined (a message is archived if either matches).
# Memory vacuum (drop tombstoned entries) always runs unless --dry-run.
set -euo pipefail

ROUND_TABLE_DIR="${ROUND_TABLE_DIR:-$(eval echo ~"$(whoami)")/.hermes/round-table}"
DRY_RUN=0
OLDER_THAN=""
KEEP_LAST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --older-than) OLDER_THAN="$2"; shift 2 ;;
    --keep-last) KEEP_LAST="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Read retention defaults from config.json when --older-than is not passed
CONFIG_FILE="$ROUND_TABLE_DIR/config.json"
if [[ -z "$OLDER_THAN" && -f "$CONFIG_FILE" ]]; then
  RETENTION_DAYS=$(python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(d.get('message_retention_days', ''))
except Exception:
    print('')
" "$CONFIG_FILE" 2>/dev/null)
  if [[ -n "$RETENTION_DAYS" && "$RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
    OLDER_THAN=$((RETENTION_DAYS * 24))
  fi
fi

if [[ -n "$OLDER_THAN" && ! "$OLDER_THAN" =~ ^[0-9]+$ ]]; then
  echo "Error: --older-than must be an integer (hours)" >&2; exit 1
fi
if [[ -n "$KEEP_LAST" && ! "$KEEP_LAST" =~ ^[0-9]+$ ]]; then
  echo "Error: --keep-last must be an integer" >&2; exit 1
fi

file_age_secs() {
  if [[ ! -e "$1" ]]; then
    echo -1
    return
  fi
  if [[ "$(uname)" == "Darwin" ]]; then
    echo $(( $(date +%s) - $(stat -f %m "$1") ))
  else
    echo $(( $(date +%s) - $(stat -c %Y "$1") ))
  fi
}

is_old() {
  [[ -z "$OLDER_THAN" ]] && return 1
  age
  age=$(file_age_secs "$1")
  [[ $age -gt $((OLDER_THAN * 3600)) ]]
}

echo "=== Round Table Protocol Cleanup ==="
echo ""

# 1. Archive old inbox messages
echo "--- Inbox Cleanup ---"
for agent_dir in "$ROUND_TABLE_DIR"/inbox/*/; do
  [[ ! -d "$agent_dir" ]] && continue
  agent=$(basename "$agent_dir")
  [[ "$agent" == "archived" ]] && continue

  shopt -s nullglob
  files=("$agent_dir"*.json)
  shopt -u nullglob
  total=${#files[@]}
  count=0

  # Newest-first list for --keep-last
  keep_set=""
  if [[ -n "$KEEP_LAST" && "$KEEP_LAST" -gt 0 && $total -gt 0 ]]; then
    if [[ "$(uname)" == "Darwin" ]]; then
      keep_set=$(for f in "$agent_dir"*.json; do [[ -f "$f" ]] && stat -f "%m %N" "$f"; done 2>/dev/null \
        | sort -rn | head -n "$KEEP_LAST" | cut -d' ' -f2-)
    else
      keep_set=$(for f in "$agent_dir"*.json; do [[ -f "$f" ]] && stat -c "%Y %n" "$f"; done 2>/dev/null \
        | sort -rn | head -n "$KEEP_LAST" | cut -d' ' -f2-)
    fi
  fi

  for f in "${files[@]+"${files[@]}"}"; do
    should_archive=0
    if is_old "$f"; then
      should_archive=1
    fi
    if [[ -n "$KEEP_LAST" ]]; then
      if ! grep -qxF "$f" <<< "$keep_set"; then
        should_archive=1
      fi
    fi

    if [[ $should_archive -eq 1 ]]; then
      if [[ $DRY_RUN -eq 0 ]]; then
        archive_dir="$agent_dir/archived"
        mkdir -p "$archive_dir"
        mv "$f" "$archive_dir/"
      fi
      count=$((count+1))
    fi
  done

  echo "  $agent: $total messages, $count archived"
done

# 2. Clean up old outbox messages
echo ""
echo "--- Outbox Cleanup ---"
for agent_dir in "$ROUND_TABLE_DIR"/outbox/*/; do
  [[ ! -d "$agent_dir" ]] && continue
  agent=$(basename "$agent_dir")
  count=0

  shopt -s nullglob
  for f in "$agent_dir"*.json; do
    if is_old "$f"; then
      [[ $DRY_RUN -eq 0 ]] && rm "$f"
      count=$((count+1))
    fi
  done
  shopt -u nullglob

  echo "  $agent: $count messages cleaned"
done

# 3. Clean up old snapshots
echo ""
echo "--- Snapshot Cleanup ---"
snap_count=0
shopt -s nullglob
for f in "$ROUND_TABLE_DIR"/snapshots/*.json; do
  if is_old "$f"; then
    [[ $DRY_RUN -eq 0 ]] && rm "$f"
    snap_count=$((snap_count+1))
  fi
done
shopt -u nullglob
echo "  Snapshots: $snap_count cleaned"

# 4. Clean up old artifacts
echo ""
echo "--- Artifact Cleanup ---"
art_count=0
shopt -s nullglob
for f in "$ROUND_TABLE_DIR"/artifacts/*.json; do
  if is_old "$f"; then
    [[ $DRY_RUN -eq 0 ]] && rm "$f"
    art_count=$((art_count+1))
  fi
done
shopt -u nullglob
echo "  Artifacts: $art_count cleaned"

# 6. Trim notifications.jsonl to prevent unbounded growth
echo ""
echo "--- Notification Cleanup ---"
NOTIF_FILE="$ROUND_TABLE_DIR/notifications.jsonl"
NOTIF_MAX_LINES=1000
if [[ -f "$NOTIF_FILE" ]]; then
  NOTIF_LINES=$(wc -l < "$NOTIF_FILE" 2>/dev/null | tr -d ' ' || echo 0)
  if [[ "$NOTIF_LINES" -gt "$NOTIF_MAX_LINES" ]]; then
    if [[ $DRY_RUN -eq 0 ]]; then
      # Atomic trim: write last N lines to temp, then move
      tmp=$(mktemp "$ROUND_TABLE_DIR/.notifications.tmp.XXXXXX")
      tail -n "$NOTIF_MAX_LINES" "$NOTIF_FILE" > "$tmp"
      mv "$tmp" "$NOTIF_FILE"
    fi
    TRIMMED=$((NOTIF_LINES - NOTIF_MAX_LINES))
    echo "  Notifications: trimmed $TRIMMED old lines (kept last $NOTIF_MAX_LINES of $NOTIF_LINES)"
  else
    echo "  Notifications: $NOTIF_LINES lines (under limit of $NOTIF_MAX_LINES)"
  fi
else
  echo "  (no notifications file)"
fi

# 5. Clean up dispatch logs and stale lock files
echo ""
echo "--- Dispatch Cleanup ---"
DISPATCH_DIR="$ROUND_TABLE_DIR/.dispatch"
DISPATCH_LOG_MAX_LINES=5000
if [[ -f "$DISPATCH_DIR/dispatch.log" ]]; then
  DISPATCH_LOG_LINES=$(wc -l < "$DISPATCH_DIR/dispatch.log" 2>/dev/null | tr -d ' ' || echo 0)
  if [[ "$DISPATCH_LOG_LINES" -gt "$DISPATCH_LOG_MAX_LINES" ]]; then
    if [[ $DRY_RUN -eq 0 ]]; then
      tmp=$(mktemp "$DISPATCH_DIR/.dispatch.log.tmp.XXXXXX")
      tail -n "$DISPATCH_LOG_MAX_LINES" "$DISPATCH_DIR/dispatch.log" > "$tmp"
      mv "$tmp" "$DISPATCH_DIR/dispatch.log"
    fi
    echo "  Dispatch log: trimmed to $DISPATCH_LOG_MAX_LINES lines (was $DISPATCH_LOG_LINES)"
  else
    echo "  Dispatch log: $DISPATCH_LOG_LINES lines (under limit)"
  fi
fi
# Remove stale lock files (owner process gone)
if [[ -d "$DISPATCH_DIR" ]]; then
  lock_pid=""
  for lock in "$DISPATCH_DIR"/*.lock; do
    [[ ! -d "$lock" ]] && continue
    lock_pid=$(cat "$lock/pid" 2>/dev/null || true)
    if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
      [[ $DRY_RUN -eq 0 ]] && rm -rf "$lock"
      echo "  Removed stale lock: $(basename "$lock") (pid $lock_pid)"
    fi
  done
fi
# Clean up agent dispatch logs older than retention period
if [[ -d "$DISPATCH_DIR" ]]; then
  shopt -s nullglob
  for agent_log in "$DISPATCH_DIR"/[a-z]*.log; do
    [[ "$(basename "$agent_log")" == "dispatch.log" ]] && continue
    if is_old "$agent_log"; then
      [[ $DRY_RUN -eq 0 ]] && rm "$agent_log"
      echo "  Removed old agent log: $(basename "$agent_log")"
    fi
  done
  shopt -u nullglob
fi

echo ""
echo "--- Memory Vacuum ---"
MEM_FILE="$ROUND_TABLE_DIR/memory.jsonl"
if [[ -f "$MEM_FILE" ]]; then
  python3 -c "
import json, os, sys, tempfile

mem_file = sys.argv[1]
dry_run = sys.argv[2] == '1'
kept, removed, bad = [], 0, 0
for line in open(mem_file):
    line = line.strip()
    if not line:
        continue
    try:
        entry = json.loads(line)
    except ValueError:
        bad += 1
        kept.append(line)  # never drop lines we can't parse
        continue
    if entry.get('deleted'):
        removed += 1
    else:
        kept.append(json.dumps(entry, ensure_ascii=False))

if dry_run:
    print(f'  Would remove {removed} deleted entries (dry run)')
else:
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(mem_file), prefix='.memory.tmp.')
    with os.fdopen(fd, 'w') as f:
        for line in kept:
            f.write(line + '\n')
    os.replace(tmp, mem_file)
    print(f'  Removed {removed} deleted entries, kept {len(kept)}')
if bad:
    print(f'  Warning: {bad} unparseable lines preserved', file=sys.stderr)
" "$MEM_FILE" "$DRY_RUN"
else
  echo "  (no memory file)"
fi

echo ""
if [[ $DRY_RUN -eq 1 ]]; then
  echo "DRY RUN — no changes made"
else
  echo "Cleanup complete."
fi
