---
name: round-table-protocol
description: "Peer-to-peer communication protocol for the Round Table multi-agent system. Enables direct agent-to-agent messaging, context snapshots, artifact sharing, and role-aware discovery — reducing reliance on the orchestrator as a message relay."
version: 1.2.0
author: round-table
license: MIT
metadata:
  hermes:
    tags:
      category: round-table
    related_skills:
      - handoff
      - subagent-driven-development
---

# Round Table Protocol

*A peer-to-peer communication layer for the Round Table multi-agent system.*

The Round Table works because its knights talk to each other — not just through the sovereign, but directly, with purpose and clarity.

## Overview

The Round Table Protocol (RTP) gives each agent a **direct communication channel** to every other agent. No more routing every handoff through ARTHUR. No more context loss at agent boundaries.

Built for **single-node operation** (filesystem-based) with a clear upgrade path to multi-node.

## Infrastructure

- **Inbox/Outbox**: `~/.hermes/round-table/inbox/<agent>/`, `~/.hermes/round-table/outbox/<agent>/`
- **Status cards**: `~/.hermes/round-table/status/<agent>.json`
- **Shared memory**: `~/.hermes/round-table/memory.jsonl`
- **Snapshots**: `~/.hermes/round-table/snapshots/`
- **Artifacts**: `~/.hermes/round-table/artifacts/`
- **Notifications**: `~/.hermes/round-table/notifications.jsonl` (daemon writes here)
- **Scripts**: `~/.hermes/profiles/<agent>/skills/round-table-protocol/scripts/`

## Quick Reference

### Messaging
```
rt-send.sh --from <agent> --to <agent|broadcast> --type <type> --priority <level> --payload '<json>'
rt-inbox.sh <agent> list|read <id>|ack <id>
```

### Status
```
rt-status.sh <agent> --task <desc> --status <working|blocked|idle|done> [--progress <desc>] [--blocker <desc>]
rt-checkin.sh <agent>
```

### Shared Memory
```
rt-memory.sh set <key> '<value>' --from <agent> [--tags <tags>] [--ttl <hours>]
rt-memory.sh get <key> | search <query> | list [--agent <name>] [--tag <tag>]
rt-memory.sh delete <key> | clear --agent <name>
```

### Snapshots & Artifacts
```
rt-snapshot.sh <agent> <session_id> <summary>
rt-artifact.sh <agent> --file <path> --desc <desc> [--for <agent>]
```

### Monitoring
```
rt-watch.sh [--follow]
rt-daemon.sh start|stop|status
rt-cleanup.sh --older-than <hours> [--dry-run]
```

## See Also

- `references/shell-scripting-patterns.md` — scripting patterns that prevent bugs in Hermes skill shell scripts