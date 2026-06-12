# Round Table Protocol

A peer-to-peer communication layer for multi-agent AI systems. Enables direct agent-to-agent messaging, shared memory, context snapshots, and artifact provenance — reducing reliance on the orchestrator as a message relay.

## Architecture

```
~/.hermes/round-table/
├── config.json              # Global configuration
├── inbox/{agent}/           # Per-agent message inboxes
├── outbox/{agent}/          # Per-agent sent messages
├── snapshots/               # Shared context snapshots
├── artifacts/               # Shared artifact registry
├── memory.jsonl             # Shared knowledge base (append-only log)
├── status/{agent}.json      # Per-agent status cards
└── notifications.jsonl      # Push notification stream
```

## Agents

| Agent | Name | Role | Model |
|-------|------|------|-------|
| **ARTHUR** | Sovereign | Strategy & Architecture | Claude Opus 4.8 |
| **MERLIN** | Wizard | Research & Domain Expert | Gemini 3.1 Pro |
| **PERCIVAL** | Builder | Creative Builder & Designer | Laguna M.1 (free) |
| **BEDIVERE** | Chronicler | Writer & Communicator | gpt-oss-120b (free) |
| **LANCELOT** | Guardian | Project Manager & QA | Nemotron 3 Super (free) |

## Quick Start

```bash
# Send a message
scripts/rt-send.sh --from arthur --to merlin --type task-offer --priority high --payload '{"task":"research"}'

# Check inbox
scripts/rt-inbox.sh merlin list

# Update status
scripts/rt-status.sh merlin --task "Researching" --status working --progress "3/5"

# Store shared knowledge
scripts/rt-memory.sh set "key" "value" --from arthur --tags "tag1" --ttl 24

# View dashboard
open dashboard/dashboard.html
```

## Scripts

| Script | Purpose |
|--------|---------|
| `rt-send.sh` | Send messages (direct + broadcast) |
| `rt-inbox.sh` | Check/read/acknowledge messages |
| `rt-checkin.sh` | Full Round Table status overview |
| `rt-status.sh` | Update status card |
| `rt-snapshot.sh` | Save context snapshots |
| `rt-artifact.sh` | Register produced artifacts |
| `rt-memory.sh` | Shared memory (set/get/search/delete) |
| `rt-cleanup.sh` | Archive old messages, vacuum deleted |
| `rt-watch.sh` | Real-time monitoring |
| `rt-daemon.sh` | Background inbox watcher |
| `generate-dashboard-data.sh` | Regenerate dashboard JSON data |

## Dashboard

Open `dashboard/dashboard.html` in a browser. Features:
- 5 agent cards with status, progress bars
- Message feed with from→to, type, priority
- Shared memory table
- Stats row (agents, active, messages, memory)
- Auto-refreshes every 5 seconds

## Skill

Installs to `~/.hermes/profiles/{agent}/skills/round-table-protocol/` for each agent. Contains `SKILL.md` (full protocol spec) and all scripts.

## Handoff

See [HANDOFF.md](HANDOFF.md) for full session context and next steps.
