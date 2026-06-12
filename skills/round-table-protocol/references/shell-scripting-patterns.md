# Shell Scripting Patterns for Hermes Skills

Patterns that prevent common bugs in Hermes skill shell scripts.

## 1. Safe File Path Handling in Inline Python

**Never** interpolate shell variables directly into inline Python strings:

```bash
# BAD — single-quote in filename breaks the Python string
python3 -c "import json; d=json.load(open('$f'))"

# GOOD — pass filename via sys.argv
python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))' "$f"
```

## 2. Nullglob for File Loops

Always use `nullglob` when iterating over glob patterns to avoid literal glob strings when no files match:

```bash
shopt -s nullglob
files=( "$dir"/*.json )
shopt -u nullglob
```

## 3. set -euo Pipefail

Start every script with strict error handling:

```bash
set -euo pipefail
```

## 4. PIDFILE-based Process Checking

Use PIDFILE-based checks instead of `pgrep` to avoid matching unrelated processes:

```bash
if [[ -f "$PIDFILE" ]]; then
  pid=$(cat "$PIDFILE")
  if kill -0 "$pid" 2>/dev/null; then
    echo "Running (PID: $pid)"
  fi
fi
```

## 5. Sandboxed Testing

Always test against a temporary `ROUND_TABLE_DIR` to avoid polluting the real state:

```bash
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/rtp_test.XXXXXX")
export ROUND_TABLE_DIR="$SANDBOX/round-table"
trap 'rm -rf "$SANDBOX"' EXIT
```
