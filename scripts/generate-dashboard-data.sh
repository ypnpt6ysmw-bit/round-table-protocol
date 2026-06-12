#!/usr/bin/env bash
# Generate JSON data files for the Round Table dashboard
set -euo pipefail

ROUND_TABLE_DIR="${ROUND_TABLE_DIR:-$HOME/.hermes/round-table}"
mkdir -p "$ROUND_TABLE_DIR/.dashboard"

RTP_DIR="$ROUND_TABLE_DIR" python3 << 'PYEOF'
import json, os, glob

rt_dir = os.environ['RTP_DIR']
dash_dir = os.path.join(rt_dir, ".dashboard")

# Messages (current inbox contents, newest last)
messages = []
for agent_dir in glob.glob(os.path.join(rt_dir, "inbox", "*")):
    if not os.path.isdir(agent_dir):
        continue
    for f in glob.glob(os.path.join(agent_dir, "*.json")):
        try:
            with open(f) as fh:
                messages.append(json.load(fh))
        except (ValueError, OSError):
            pass

messages.sort(key=lambda m: m.get("timestamp", ""))

with open(os.path.join(dash_dir, "messages.json"), "w") as f:
    json.dump(messages, f, indent=2)

# Memory (active entries only)
memory = []
mem_file = os.path.join(rt_dir, "memory.jsonl")
if os.path.exists(mem_file):
    for line in open(mem_file):
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
            if not entry.get("deleted"):
                memory.append(entry)
        except ValueError:
            pass

with open(os.path.join(dash_dir, "memory.json"), "w") as f:
    json.dump(memory, f, indent=2)

# Status cards
status = []
for f in sorted(glob.glob(os.path.join(rt_dir, "status", "*.json"))):
    try:
        with open(f) as fh:
            status.append(json.load(fh))
    except (ValueError, OSError):
        pass

with open(os.path.join(dash_dir, "status.json"), "w") as f:
    json.dump(status, f, indent=2)

print(f"Dashboard data: {len(messages)} messages, {len(memory)} memory entries, {len(status)} status cards")
PYEOF
