#!/usr/bin/env bash
# rt-dashboard-refresh.sh — Refresh Round Table dashboard live data
# Intended to be run as a cron job or on a schedule.
# Uses absolute paths because $HOME may be overridden by Hermes profiles.
set -euo pipefail

_REAL_USER_HOME="$(eval echo ~"$(whoami)")"
RT_DIR="$_REAL_USER_HOME/.hermes/round-table"
SCRIPTS_SRC="$_REAL_USER_HOME/.hermes/profiles/arthur/skills/round-table-protocol/scripts"

mkdir -p "$RT_DIR/.dashboard"

# Copy dashboard.html from skill package if needed
SKILL_HTML="$SCRIPTS_SRC/../dashboard.html"
if [[ -f "$SKILL_HTML" ]] && [[ ! -f "$RT_DIR/dashboard.html" ]]; then
  cp "$SKILL_HTML" "$RT_DIR/dashboard.html"
fi

# Generate fresh dashboard data
export ROUND_TABLE_DIR="$RT_DIR"
if [[ -x "$RT_DIR/generate-dashboard-data.sh" ]]; then
  "$RT_DIR/generate-dashboard-data.sh"
elif [[ -x "$SCRIPTS_SRC/generate-dashboard-data.sh" ]]; then
  "$SCRIPTS_SRC/generate-dashboard-data.sh"
fi

# Ensure HTTP server is running
if ! lsof -ti tcp:8101 >/dev/null 2>&1; then
  cd "$RT_DIR" && nohup python3 -m http.server 8101 \
    >> "$RT_DIR/.dashboard/httpd.log" 2>&1 &
  disown 2>/dev/null || true
fi

# Verify dashboard
DASH_OK=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8101/dashboard.html 2>/dev/null || echo "0")
MSG_COUNT=$(python3 -c "import json; d=json.load(open('$RT_DIR/.dashboard/messages.json')); print(len(d))" 2>/dev/null || echo "0")
echo "Dashboard: $MSG_COUNT messages, HTTP $DASH_OK"