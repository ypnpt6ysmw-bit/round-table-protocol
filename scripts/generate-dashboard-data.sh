#!/usr/bin/env bash
# Generate JSON data files for the Round Table dashboard
set -euo pipefail

RT_DIR="/Users/arielkurek/.hermes/round-table"
mkdir -p "$RT_DIR/.dashboard"

python3 << 'PYEOF'
import json, os, glob

rt_dir = "/Users/arielkurek/.hermes/round-table"
messages = []

for agent_dir in glob.glob(os.path.join(rt_dir, "inbox", "*")):
    if not os.path.isdir(agent_dir):
        continue
    for f in glob.glob(os.path.join(agent_dir, "*.json")):
        try:
            with open(f) as fh:
                msg = json.load(fh)
                messages.append(msg)
        except:
            pass

messages.sort(key=lambda m: m.get("timestamp", ""))

with open(os.path.join(rt_dir, ".dashboard", "messages.json"), "w") as f:
    json.dump(messages, f, indent=2)

# Memory
memory = []
mem_file = os.path.join(rt_dir, "memory.jsonl")
if os.path.exists(mem_file):
    for line in open(mem_file):
        try:
            entry = json.loads(line.strip())
            if not entry.get("deleted"):
                memory.append(entry)
        except:
            pass

with open(os.path.join(rt_dir, ".dashboard", "memory.json"), "w") as f:
    json.dump(memory, f, indent=2)

print(f"Dashboard data: {len(messages)} messages, {len(memory)} memory entries")
PYEOF