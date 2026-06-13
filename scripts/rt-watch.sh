#!/usr/bin/env bash
# rt-watch.sh — Monitor Round Table Protocol activity in real-time
# Usage: rt-watch.sh [--follow] [--agent <agent>]
#
# Without --follow: shows a snapshot of current activity
# With --follow:    tail -f style monitoring (checks every 2s)
set -euo pipefail

ROUND_TABLE_DIR="${ROUND_TABLE_DIR:-$HOME/.hermes/round-table}"
CONFIG="$ROUND_TABLE_DIR/config.json"
FOLLOW=0
AGENT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --follow) FOLLOW=1; shift ;;
    --agent) AGENT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

show_snapshot() {
  echo "=== Round Table Pulse Check ==="
  echo "  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""

  # Single python3 invocation for all snapshot data
  _RTW_RT_DIR="$ROUND_TABLE_DIR" _RTW_CFG="$CONFIG" _RTW_AGENT="$AGENT" python3 -c '
import json, os, glob

rt_dir = os.environ["_RTW_RT_DIR"]
config = os.environ["_RTW_CFG"]
agent_filter = os.environ.get("_RTW_AGENT", "")

# Load agents
try:
    agents = json.load(open(config))["agents"]
except Exception:
    agents = ["arthur", "merlin", "percival", "bedivere", "lancelot"]

# Load status cards
status = {}
for a in agents:
    try:
        status[a] = json.load(open(os.path.join(rt_dir, "status", a + ".json")))
    except (OSError, ValueError):
        pass

# Load pending messages + count urgents
pending = {}
for a in agents:
    inbox = os.path.join(rt_dir, "inbox", a)
    files = glob.glob(os.path.join(inbox, "*.json"))
    urgent = 0
    for f in files:
        try:
            msg = json.load(open(f))
            if msg.get("priority") == "urgent":
                urgent += 1
        except (ValueError, OSError):
            pass
    if files:
        pending[a] = (len(files), urgent)

# Load memory
mem_file = os.path.join(rt_dir, "memory.jsonl")
mem_entries = []
if os.path.exists(mem_file):
    seen = set()
    for line in reversed(open(mem_file).readlines()):
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if entry.get("key") in seen:
            continue
        seen.add(entry["key"])
        if not entry.get("deleted"):
            mem_entries.append(entry)

# Load recent notifications
notif_file = os.path.join(rt_dir, "notifications.jsonl")
recent_notifs = []
if os.path.exists(notif_file):
    lines = open(notif_file).readlines()
    for line in lines[-3:]:
        line = line.strip()
        if not line:
            continue
        try:
            recent_notifs.append(json.loads(line))
        except ValueError:
            pass

# --- Render ---
print("--- Agents ---")
for a in agents:
    s = status.get(a, {})
    st = s.get("status", "idle")
    task = s.get("current_task", "")[:50]
    icons = {"working": "\U0001f7e2", "blocked": "\U0001f534", "done": "\u2705", "idle": "\u26aa"}
    icon = icons.get(st, "\u26aa")
    print(f"  {icon} {a:<12s} {st:<10s} {task}")

print()
print("--- Pending Messages ---")
for a in agents:
    if agent_filter and a != agent_filter:
        continue
    if a in pending:
        cnt, urg = pending[a]
        print(f"  {a}: {cnt} messages ({urg} urgent)")

print()
print("--- Shared Memory ---")
active = [e for e in mem_entries if not e.get("deleted")]
print(f"  {len(active)} active entries")
for entry in active[-3:]:
    k = entry.get("key", "")
    f = entry.get("from", "")
    t = entry.get("tags", [])
    print(f"  {k:40s} | from: {f:10s} | tags: {t}")

print()
print("--- Recent Notifications ---")
if recent_notifs:
    for n in recent_notifs:
        frm = n.get("from", "?")
        to = n.get("notified_agent", "?")
        typ = n.get("type", "")
        ts = n.get("timestamp", "")[:16]
        print(f"  {frm:>6} -> {to:<10s} | {typ:20s} | {ts}")
else:
    print("  (none)")
'
}

if [[ $FOLLOW -eq 1 ]]; then
  echo "Watching Round Table activity (Ctrl+C to stop)..."
  while true; do
    tput clear 2>/dev/null || printf '\033[2J\033[H'
    show_snapshot
    sleep 2
  done
else
  show_snapshot
fi
