#!/usr/bin/env bash
# rt-dashboard-text.sh — Render the Round Table dashboard as a chat-friendly
# text status board, so it can be posted inside a Hermes conversation.
# Reads the same live data the web dashboard uses (.dashboard/*.json),
# refreshing it first. Prints to stdout. Never opens a browser.
set -euo pipefail

RT_DIR="${ROUND_TABLE_DIR:-$HOME/.hermes/round-table}"
DASH="$RT_DIR/.dashboard"

# Refresh live data (best-effort; show whatever exists if it fails)
if [[ -x "$RT_DIR/generate-dashboard-data.sh" ]]; then
  "$RT_DIR/generate-dashboard-data.sh" >/dev/null 2>&1 || true
fi

RTP_DASH="$DASH" python3 << 'PYEOF'
import json, os

dash = os.environ["RTP_DASH"]

def load(name, default):
    path = os.path.join(dash, name)
    try:
        with open(path) as f:
            return json.load(f)
    except (ValueError, OSError):
        return default

status = load("status.json", [])
messages = load("messages.json", [])
memory = load("memory.json", [])

ICON = {"working": "🟢", "blocked": "🔴", "done": "✅", "idle": "⚪"}

active = sum(1 for s in status if s.get("status") == "working")
print("♔ ROUND TABLE")
print(f"   {len(status)} agents · {active} active · {len(messages)} messages · {len(memory)} memory")
print()

if status:
    print("AGENTS")
    for s in status:
        name = (s.get("agent") or "?").upper()
        st = s.get("status") or "idle"
        icon = ICON.get(st, "⚪")
        task = s.get("current_task") or "Standing by"
        prog = s.get("progress") or ""
        line = f"  {icon} {name:<9} {st:<8} {task}"
        if prog:
            line += f"  [{prog}]"
        print(line)
        for b in s.get("blockers") or []:
            print(f"        ⚠ {b}")
    print()


def payload_text(p):
    if p is None:
        return ""
    if isinstance(p, str):
        return p
    if isinstance(p, dict):
        parts = [str(v) for v in p.values() if isinstance(v, (str, int, float))]
        return " · ".join(parts) if parts else json.dumps(p, ensure_ascii=False)
    return str(p)


if messages:
    print(f"RECENT MESSAGES (last {min(10, len(messages))})")
    for m in messages[-10:]:
        ts = (m.get("timestamp") or "")[11:16]
        frm = (m.get("from") or "?")[:6]
        to = (m.get("to") or "?")[:6]
        typ = m.get("type") or ""
        prio = m.get("priority") or "normal"
        txt = payload_text(m.get("payload"))
        if len(txt) > 60:
            txt = txt[:57] + "…"
        flag = " ‼" if prio in ("high", "urgent") else ""
        print(f"  {ts}  {frm:>6} → {to:<6} {typ}{flag}: {txt}")
    print()

if memory:
    print("MEMORY")
    for e in memory:
        k = e.get("key", "")
        v = e.get("value", "")
        if not isinstance(v, str):
            v = json.dumps(v, ensure_ascii=False)
        if len(v) > 60:
            v = v[:57] + "…"
        print(f"  • {k}: {v}")
    print()

print("Live web view (browser): http://localhost:8101/dashboard.html")
PYEOF
