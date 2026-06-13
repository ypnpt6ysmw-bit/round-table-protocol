#!/usr/bin/env bash
# ensure-dashboard.sh — keep the Round Table dashboard served headlessly.
# Starts the HTTP server on :8101 if absent and refreshes dashboard data.
# Intentionally NEVER opens a browser — view at http://localhost:8101/dashboard.html
# from inside Hermes (or any browser) when wanted.
set -euo pipefail

RT_DIR="${ROUND_TABLE_DIR:-$HOME/.hermes/round-table}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Copy dashboard HTML from the skill package to the served directory
SKILL_DASHBOARD="$SCRIPT_DIR/../dashboard.html"
if [[ -f "$SKILL_DASHBOARD" ]]; then
  cp "$SKILL_DASHBOARD" "$RT_DIR/dashboard.html"
fi

if ! lsof -ti tcp:8101 >/dev/null 2>&1; then
  nohup python3 -m http.server 8101 --directory "$RT_DIR" \
    >> "$RT_DIR/.dashboard/httpd.log" 2>&1 < /dev/null &
  disown 2>/dev/null || true
fi

"$RT_DIR/generate-dashboard-data.sh" >> "$RT_DIR/.dashboard/cron.log" 2>&1
