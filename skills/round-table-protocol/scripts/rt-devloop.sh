#!/usr/bin/env bash
# rt-devloop.sh — Round Table development loop with REAL agents.
#
# Each phase runs as an actual Hermes session under that knight's own profile
# (hermes -p <agent>), so every phase uses that agent's SOUL.md, skills and
# configured model. No personas, no same-model subagents.
#
#   plan      ARTHUR   (its own profile/model)
#   research  MERLIN
#   build     PERCIVAL
#   write     BEDIVERE
#   qa        LANCELOT
#
# Output of each phase is saved under $ROUND_TABLE_DIR/devloop/<run-id>/ and
# chained as context into the next phase.
#
# Usage:
#   rt-devloop.sh "Build a REST API for user auth"
#   rt-devloop.sh --phase build "Add dark mode"     # single phase
#   rt-devloop.sh --dry-run "Refactor payments"     # print prompts only
#
# Env:
#   ROUND_TABLE_DIR   protocol root (default ~/.hermes/round-table)
#   HERMES_BIN        hermes binary (default: hermes) — tests stub this
#   RT_PHASE_TIMEOUT  seconds per phase session (default 900)
set -euo pipefail

# Resolve real user home (Hermes profile may override $HOME)
_REAL_USER_HOME="$(eval echo ~"$(whoami)")"

ROUND_TABLE_DIR="${ROUND_TABLE_DIR:-$HOME/.hermes/round-table}"
HERMES_BIN="${HERMES_BIN:-hermes}"
TIMEOUT_SECS="${RT_PHASE_TIMEOUT:-900}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# bash 3.2 compatible (macOS default): no associative arrays, no ${var^^}
PHASES="plan research build write qa"

phase_agent() {
  case "$1" in
    plan) echo arthur ;;
    research) echo merlin ;;
    build) echo percival ;;
    write) echo bedivere ;;
    qa) echo lancelot ;;
    *) return 1 ;;
  esac
}

phase_brief() {
  case "$1" in
    plan) echo "Scope the task, define deliverables, choose an architecture/approach, list trade-offs and risks. Output a structured markdown plan." ;;
    research) echo "Investigate options, libraries, best practices and pitfalls relevant to the plan. Output research notes in markdown with sources." ;;
    build) echo "Implement the solution following the plan and research. Write clean, working code and commit changes where a repo is involved. Output an implementation summary listing files touched." ;;
    write) echo "Document the work: README updates, API docs, key decisions and rationale. Output the documentation in markdown." ;;
    qa) echo "Review the implementation for correctness, security and test coverage. Run tests where available. Output a QA report ending with verdict PASS, FAIL or NEEDS_WORK plus specific findings." ;;
  esac
}

upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

TASK=""
PHASE_FILTER="all"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase) PHASE_FILTER="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h)
      sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) TASK="$1"; shift ;;
  esac
done

[[ -z "$TASK" ]] && { echo "Error: task description required" >&2; exit 1; }
if [[ "$PHASE_FILTER" != "all" ]]; then
  phase_agent "$PHASE_FILTER" >/dev/null || { echo "Error: unknown phase: $PHASE_FILTER (plan|research|build|write|qa)" >&2; exit 1; }
fi

RUN_ID="devloop-$(date +%Y%m%d_%H%M%S)"
RUN_DIR="$ROUND_TABLE_DIR/devloop/$RUN_ID"
mkdir -p "$RUN_DIR"
printf '%s\n' "$TASK" > "$RUN_DIR/task.txt"

build_phase_prompt() {  # build_phase_prompt <phase>
  local phase="$1" agent
  agent=$(phase_agent "$1")
  cat <<PROMPT
You are $(upper "$agent"), a knight of the Round Table (role per your SOUL.md).
You are running the $(upper "$phase") phase of a Round Table development loop.

## Task
$TASK

## Your phase
$(phase_brief "$phase")

## Context from previous phases
PROMPT
  local p
  for p in $PHASES; do
    [[ "$p" == "$phase" ]] && break
    if [[ -s "$RUN_DIR/$p.md" ]]; then
      echo ""
      echo "### $(upper "$p") output ($(upper "$(phase_agent "$p")"))"
      cat "$RUN_DIR/$p.md"
    fi
  done
  cat <<PROMPT

## Protocol
- Round Table scripts live in $SCRIPT_DIR (ROUND_TABLE_DIR=$ROUND_TABLE_DIR).
- Update your status when you start and finish:
  $SCRIPT_DIR/rt-status.sh $agent --task "devloop $RUN_ID: $phase" --status working
  $SCRIPT_DIR/rt-status.sh $agent --task "devloop $RUN_ID: $phase" --status done
- Store durable decisions with $SCRIPT_DIR/rt-memory.sh set <key> <value> --from $agent
- Your FINAL message must be the complete ${phase} output in markdown; it is
  saved verbatim and handed to the next knight.
PROMPT
}

run_phase() {  # run_phase <phase>
  local phase="$1" agent
  agent=$(phase_agent "$1")
  local out_file="$RUN_DIR/$phase.md"
  local prompt
  prompt=$(build_phase_prompt "$phase")

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "━━━ DRY RUN — $(upper "$phase") prompt (would run: $HERMES_BIN -p $agent -z ...) ━━━"
    echo "$prompt"
    echo ""
    return 0
  fi

  if [[ ! -d "$_REAL_USER_HOME/.hermes/profiles/$agent" ]]; then
    echo "Error: no Hermes profile for $agent at $_REAL_USER_HOME/.hermes/profiles/$agent" >&2
    return 1
  fi

  echo "━━━ $(upper "$phase") → $(upper "$agent") (profile: $agent) ━━━"
  "$SCRIPT_DIR/rt-status.sh" "$agent" --task "devloop $RUN_ID: $phase" --status "working"
  local rc=0
  if command -v timeout >/dev/null 2>&1; then
    ROUND_TABLE_DIR="$ROUND_TABLE_DIR" timeout "$TIMEOUT_SECS" \
      "$HERMES_BIN" -p "$agent" -z "$prompt" > "$out_file" 2>"$RUN_DIR/$phase.err" < /dev/null || rc=$?
  else
    ROUND_TABLE_DIR="$ROUND_TABLE_DIR" \
      "$HERMES_BIN" -p "$agent" -z "$prompt" > "$out_file" 2>"$RUN_DIR/$phase.err" < /dev/null || rc=$?
  fi

  if [[ $rc -eq 0 ]]; then
    "$SCRIPT_DIR/rt-status.sh" "$agent" --task "devloop $RUN_ID: $phase" --status "done"
    echo "  output: $out_file ($(wc -l < "$out_file" | tr -d ' ') lines)"
  else
    "$SCRIPT_DIR/rt-status.sh" "$agent" --task "devloop $RUN_ID: $phase" --status blocked --blocker "exit $rc"
  fi
  return $rc
}

echo "=== Round Table Dev Loop: $RUN_ID ==="
echo "Task: $TASK"
echo "Phases: $PHASE_FILTER"
echo "Run dir: $RUN_DIR"
echo ""

FAILED=0
for phase in $PHASES; do
  [[ "$PHASE_FILTER" != "all" && "$phase" != "$PHASE_FILTER" ]] && continue
  run_phase "$phase" || { FAILED=1; break; }
done

echo ""
if [[ $DRY_RUN -eq 1 ]]; then
  echo "DRY RUN complete — no sessions spawned."
elif [[ $FAILED -eq 1 ]]; then
  echo "Dev loop ABORTED at failed phase. Partial outputs in $RUN_DIR"
  exit 1
else
  echo "Dev loop complete. Outputs in $RUN_DIR"
  [[ -f "$RUN_DIR/qa.md" ]] && tail -5 "$RUN_DIR/qa.md"
fi
