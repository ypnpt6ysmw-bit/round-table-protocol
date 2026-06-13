#!/usr/bin/env bash
# rt-common.sh — Shared functions for Round Table Protocol scripts
# Source this file in other scripts: SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" && source "$SCRIPT_DIR/rt-common.sh"
set -uo pipefail

# Resolve real user home (Hermes profile may override $HOME)
_RT_REAL_USER_HOME="$(eval echo ~"$(whoami)")"

# Default ROUND_TABLE_DIR — can be overridden by caller before sourcing
ROUND_TABLE_DIR="${ROUND_TABLE_DIR:-$_RT_REAL_USER_HOME/.hermes/round-table}"
CONFIG="$ROUND_TABLE_DIR/config.json"

# get_agents — print space-separated agent names from config.json
get_agents() {
  python3 -c "import json,sys; print(' '.join(json.load(open(sys.argv[1]))['agents']))" "$CONFIG" 2>/dev/null \
    || echo "arthur merlin percival bedivere lancelot"
}

# log <message> — append timestamped message to round-table log
rt_log() {
  local logfile="$ROUND_TABLE_DIR/.round-table.log"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >> "$logfile" 2>/dev/null || true
}

# dispatch_log <message> — append to dispatch-specific log
dispatch_log() {
  local logfile="$ROUND_TABLE_DIR/.dispatch/dispatch.log"
  mkdir -p "$(dirname "$logfile")"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >> "$logfile" 2>/dev/null || true
}

# validate_agent <name> <role> — validate agent name is known and safe
validate_agent() {
  local name="$1" role="$2"
  if [[ ! "$name" =~ ^[a-z0-9_-]+$ ]]; then
    echo "Error: invalid $role agent name: $name" >&2
    return 1
  fi
  local a
  for a in $(get_agents); do
    [[ "$a" == "$name" ]] && return 0
  done
  echo "Error: unknown $role agent: $name (known: $(get_agents))" >&2
  return 1
}

# file_age_secs <path> — print file age in seconds, -1 if missing
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

# atomic_write <path> <content> — write file atomically via temp+rename
atomic_write() {
  local path="$1" content="$2"
  local tmp
  tmp=$(mktemp "$(dirname "$path")/.$(basename "$path").tmp.XXXXXX")
  printf '%s\n' "$content" > "$tmp"
  mv "$tmp" "$path"
}
