#!/usr/bin/env bash
# rt-cleanup.sh — Message lifecycle management for Round Table Protocol
# Usage: rt-cleanup.sh [--dry-run] [--older-than <hours>] [--keep-last <n>]
set -euo pipefail

ROUND_TABLE_DIR="${ROUND_TABLE_DIR:-$HOME/.hermes/round-table}"
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

echo "=== Round Table Protocol Cleanup ==="
echo ""

# 1. Archive old inbox messages
echo "--- Inbox Cleanup ---"
for agent_dir in "$ROUND_TABLE_DIR"/inbox/*/; do
  [[ ! -d "$agent_dir" ]] && continue
  agent=$(basename "$agent_dir")
  count=0
  total=0

  for f in "$agent_dir"/*.json; do
    [[ ! -f "$f" ]] && continue
    total=$((total+1))

    should_archive=0
    if [[ -n "$OLDER_THAN" ]]; then
      # Check file age
      if [[ "$(uname)" == "Darwin" ]]; then
        age=$(( $(date +%s) - $(stat -f %m "$f") ))
      else
        age=$(( $(date +%s) - $(stat -c %Y "$f") ))
      fi
      if [[ $age -gt $((OLDER_THAN * 3600)) ]]; then
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

  archived=$total
  if [[ -n "$KEEP_LAST" ]]; then
    # Don't count the last N files
    archived=$((total - KEEP_LAST))
    [[ $archived -lt 0 ]] && archived=0
  fi

  echo "  $agent: $total messages, $count archived"
done

# 2. Clean up old outbox messages
echo ""
echo "--- Outbox Cleanup ---"
for agent_dir in "$ROUND_TABLE_DIR"/outbox/*/; do
  [[ ! -d "$agent_dir" ]] && continue
  agent=$(basename "$agent_dir")
  count=0

  for f in "$agent_dir"/*.json; do
    [[ ! -f "$f" ]] && continue
    if [[ -n "$OLDER_THAN" ]]; then
      if [[ "$(uname)" == "Darwin" ]]; then
        age=$(( $(date +%s) - $(stat -f %m "$f") ))
      else
        age=$(( $(date +%s) - $(stat -c %Y "$f") ))
      fi
      if [[ $age -gt $((OLDER_THAN * 3600)) ]]; then
        if [[ $DRY_RUN -eq 0 ]]; then
          rm "$f"
        fi
        count=$((count+1))
      fi
    fi
  done

  echo "  $agent: $count messages cleaned"
done

# 3. Clean up old snapshots
echo ""
echo "--- Snapshot Cleanup ---"
snap_count=0
for f in "$ROUND_TABLE_DIR"/snapshots/*.json; do
  [[ ! -f "$f" ]] && continue
  if [[ -n "$OLDER_THAN" ]]; then
    if [[ "$(uname)" == "Darwin" ]]; then
      age=$(( $(date +%s) - $(stat -f %m "$f") ))
    else
      age=$(( $(date +%s) - $(stat -c %Y "$f") ))
    fi
    if [[ $age -gt $((OLDER_THAN * 3600)) ]]; then
      if [[ $DRY_RUN -eq 0 ]]; then
        rm "$f"
      fi
      snap_count=$((snap_count+1))
    fi
  fi
done
echo "  Snapshots: $snap_count cleaned"

# 4. Clean up old artifacts
echo ""
echo "--- Artifact Cleanup ---"
art_count=0
for f in "$ROUND_TABLE_DIR"/artifacts/*.json; do
  [[ ! -f "$f" ]] && continue
  if [[ -n "$OLDER_THAN" ]]; then
    if [[ "$(uname)" == "Darwin" ]]; then
      age=$(( $(date +%s) - $(stat -f %m "$f") ))
    else
      age=$(( $(date +%s) - $(stat -c %Y "$f") ))
    fi
    if [[ $age -gt $((OLDER_THAN * 3600)) ]]; then
      if [[ $DRY_RUN -eq 0 ]]; then
        rm "$f"
      fi
      art_count=$((art_count+1))
    fi
  fi
done
echo "  Artifacts: $art_count cleaned"

# 5. Vacuum memory (remove deleted entries from jsonl)
echo ""
echo "--- Memory Vacuum ---"
if [[ $DRY_RUN -eq 0 ]]; then
  lines=$(wc -l < "$ROUND_TABLE_DIR/memory.jsonl" 2>/dev/null || echo 0)
  active=$(grep -cv '"deleted": true' "$ROUND_TABLE_DIR/memory.jsonl" 2>/dev/null || echo 0)
  deleted=$((lines - active))
  echo "  Before: $lines entries ($active active, $deleted deleted)"

  # Rewrite file without deleted entries
  grep -v '"deleted": true' "$ROUND_TABLE_DIR/memory.jsonl" > "$ROUND_TABLE_DIR/memory.jsonl.tmp" 2>/dev/null || true
  mv "$ROUND_TABLE_DIR/memory.jsonl.tmp" "$ROUND_TABLE_DIR/memory.jsonl"

  new_lines=$(wc -l < "$ROUND_TABLE_DIR/memory.jsonl" 2>/dev/null || echo 0)
  echo "  After: $new_lines entries (removed $deleted deleted)"
else
  deleted=$(grep -c '"deleted": true' "$ROUND_TABLE_DIR/memory.jsonl" 2>/dev/null || echo 0)
  echo "  Would remove $deleted deleted entries (dry run)"
fi

echo ""
if [[ $DRY_RUN -eq 1 ]]; then
  echo "DRY RUN — no changes made"
else
  echo "Cleanup complete."
fi
