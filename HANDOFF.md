# Handoff: Round Table Protocol v1.2

## What Was Built

A peer-to-peer communication layer for the 5-agent Round Table system (ARTHUR, MERLIN, PERCIVAL, BEDIVERE, LANCELOT).

## Files Created

```
~/.hermes/round-table/
├── dashboard.html                        # Live status dashboard (open in browser)
├── config.json                           # Agent registry config
├── generate-dashboard-data.sh            # Regenerates JSON data for dashboard
├── populate-demo.sh                      # Demo data for dashboard preview
├── .dashboard/
│   ├── messages.json                     # Cached inbox messages
│   └── memory.json                       # Cached shared memory entries
├── inbox/{arthur,merlin,percival,bedivere,lancelot}/  # Per-agent message dirs
├── outbox/{arthur,merlin,percival,bedivere,lancelot}/ # Sent messages
├── snapshots/                            # Context snapshots
├── artifacts/                            # Artifact registry
├── memory.jsonl                          # Shared knowledge base (append-only log)
├── status/{arthur,merlin,percival,bedivere,lancelot}.json  # Status cards
└── notifications.jsonl                   # Push notification stream
```

## Skills (installed in all 5 profiles)

```
~/.hermes/profiles/{agent}/skills/round-table-protocol/
├── SKILL.md                              # Full protocol specification
└── scripts/
    ├── rt-send.sh                        # Send messages (direct + broadcast)
    ├── rt-inbox.sh                       # Check/read/acknowledge messages
    ├── rt-checkin.sh                     # Full Round Table status overview
    ├── rt-snapshot.sh                    # Save context snapshots
    ├── rt-status.sh                      # Update status card
    ├── rt-artifact.sh                    # Register produced artifacts
    ├── rt-memory.sh                      # Shared memory (set/get/search/delete)
    ├── rt-cleanup.sh                     # Archive old messages, vacuum deleted
    ├── rt-watch.sh                       # Real-time monitoring
    └── rt-daemon.sh                      # Background inbox watcher
```

## Key Scripts

| Script | Purpose |
|--------|---------|
| `rt-send.sh --from X --to Y --type T --payload '{}'` | Send message |
| `rt-inbox.sh <agent> list\|read <id>\|ack <id>` | Check inbox |
| `rt-checkin.sh <agent>` | Overview of all agents + pending messages |
| `rt-status.sh <agent> --task "X" --status working` | Update status |
| `rt-memory.sh set <key> <value> --from <agent>` | Store knowledge |
| `rt-memory.sh get <key>` | Read latest value |
| `rt-memory.sh search <query>` | Search all memory |
| `rt-snapshot.sh <agent> <session_id> <summary>` | Save context |
| `rt-artifact.sh <agent> --file <path> --desc <desc> --for <agent>` | Register artifact |
| `rt-cleanup.sh --older-than <hours>` | Lifecycle cleanup |
| `rt-watch.sh [--follow]` | Monitor activity |
| `rt-daemon.sh start\|stop\|status` | Background push watcher |

## Cronjobs

| Job | Schedule | Purpose |
|-----|----------|---------|
| `Round Table dashboard auto-start` | Every 2 min | Ensures HTTP server (port 8101) is running, opens browser tab, refreshes data |
| `Round Table dashboard refresh` | Every 5 min | Regenerates messages.json and memory.json from inboxes |

## Dashboard

Access: `http://localhost:8101/dashboard.html`

Features:
- 5 agent cards with status (working/idle/blocked/done), progress bars
- Message feed with from→to, type, priority, timestamp
- Shared memory table
- Stats row (agents active, messages, memory keys)
- Auto-refreshes every 5 seconds
- Excalibur sword icon + Cinzel font for title

## SOUL.md Updates

All 5 agent profiles updated with `## Round Table Protocol` section containing:
- Node ID
- When to use RTP vs delegate_task
- Agent-specific communication rules
- Inbox path

## What Needs Attention

1. **Dashboard data is static** — The demo data is hardcoded in the HTML. Live data comes from the cronjob running `generate-dashboard-data.sh` which feeds `.dashboard/messages.json` and `.dashboard/memory.json`. The dashboard frontend needs to fetch these (currently uses embedded data).
2. **Daemon needs manual start** — `rt-daemon.sh` runs in background but doesn't survive sessions. Should be managed by the cronjob.
3. **No real agent sessions yet** — The protocol works via scripts but no actual Hermes sessions have been spawned to use it yet.
4. **Merge with existing codebase** — This was built outside the main Ari repo. Need to decide where it lives.
