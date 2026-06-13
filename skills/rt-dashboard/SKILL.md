---
name: rt-dashboard
description: "Display the Round Table dashboard — agent status, messages, and shared memory. Use to check the current state of the Round Table multi-agent system."
metadata:
  hermes:
    tags:
      - round-table
      - dashboard
      - monitoring
---

# RT Dashboard — Round Table Status Board

Display the current state of the Round Table multi-agent system.

## Usage

Run the text dashboard and post the output:

```bash
~/.hermes/profiles/<agent>/skills/round-table-protocol/scripts/rt-dashboard-text.sh
```

This prints a compact status board showing:
- All 5 agents with status icons (🟢 working, 🔴 blocked, ✅ done, ⚪ idle)
- Recent messages (last 10)
- Shared memory entries
- Recent notifications

## Web Dashboard

For the full visual dashboard, ensure the HTTP server is running:

```bash
~/.hermes/profiles/<agent>/skills/round-table-protocol/scripts/ensure-dashboard.sh
```

Then open in the Hermes desktop app preview rail or browser:
**http://localhost:8101/dashboard.html**

The web dashboard refreshes every 5 seconds and shows agent cards, message feed, memory table, and stats.

## Data Refresh

The dashboard reads from `~/.hermes/round-table/.dashboard/*.json`. To refresh data:

```bash
~/.hermes/profiles/<agent>/skills/round-table-protocol/scripts/generate-dashboard-data.sh
```

Or use `ensure-dashboard.sh` which both refreshes data and ensures the HTTP server is running.
