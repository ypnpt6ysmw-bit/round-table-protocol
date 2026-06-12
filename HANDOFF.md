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

1. ~~**Dashboard data is static**~~ — RESOLVED 2026-06-12: dashboard now fetches `.dashboard/{messages,memory,status}.json` every 5s with demo fallback (header pill shows Live/Demo). `generate-dashboard-data.sh` also emits `status.json` now.
2. ~~**Daemon needs manual start**~~ — RESOLVED 2026-06-12: Cron jobs installed (`*/2 * * * *` auto-start + `*/5 * * * *` data refresh). Daemon running at PID tracked in `.dashboard/daemon.pid`. Logs at `.dashboard/httpd.log` and `.dashboard/cron.log`.
3. **No real agent sessions yet** — The protocol works via scripts but no actual Hermes sessions have been spawned to use it yet.
4. **Merge with existing codebase** — This was built outside the main Ari repo. Need to decide where it lives.

## QA Pass 2026-06-12

Full test/review/fix cycle completed. `tests/run_tests.sh` added (74 assertions, sandboxed via `ROUND_TABLE_DIR`); all pass, shellcheck clean. Fixed:

- **rt-daemon start hung any caller capturing output** (child inherited stdout) — now `nohup … < /dev/null >> log &` + disown; stop also kills watcher children
- **Shell→Python injection** in rt-memory/rt-inbox/rt-checkin/rt-watch/rt-daemon (keys/queries/paths interpolated into Python source) — all values now passed via argv/env
- **No agent validation in rt-send** — `--to ../evil` created directories outside inbox/; now validated against config registry + `^[a-z0-9_-]+$`
- **Memory tombstones didn't shadow older revisions** — get/search/list returned pre-delete values; latest-entry-wins now
- **rt-status/snapshot/artifact** wrote into possibly missing dirs and truncated before write — now mkdir -p + atomic temp+rename (rt-send delivery also atomic)
- **rt-cleanup**: `--keep-last` was parsed but unimplemented — now works; grep-based memory vacuum (ate values containing `"deleted": true`, crashed on empty file) replaced with JSON-aware atomic vacuum
- **rt-artifact** notification payload built by string interpolation — quotes in `--desc` broke JSON; now built with `json.dumps`; send failures surface a warning instead of silent `|| true`
- **generate-dashboard-data.sh / populate-demo.sh** hardcoded `/Users/arielkurek` — now honor `ROUND_TABLE_DIR`
- **rt-status** validates status enum; **rt-watch** dead `--recent` flag removed, agent list from config; dashboard HTML-escapes all dynamic strings (XSS)
- `skills/round-table-protocol/scripts/` copies re-synced (test suite enforces parity)
