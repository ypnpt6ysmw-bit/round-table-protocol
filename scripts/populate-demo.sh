#!/usr/bin/env bash
# Populate Round Table with demo data for dashboard visualization
set -euo pipefail

RT_DIR="${ROUND_TABLE_DIR:-$(eval echo ~"$(whoami)")/.hermes/round-table}"
mkdir -p "$RT_DIR/status"

# Status files
cat > "$RT_DIR/status/arthur.json" << 'EOF'
{"agent":"arthur","timestamp":"2026-06-12T13:00:00Z","current_task":"Strategic planning for Round Table v2","status":"working","progress":"2 of 4 phases","blockers":[],"offering":["architecture","strategy"],"seeking":[],"last_active":"2026-06-12T13:00:00Z"}
EOF

cat > "$RT_DIR/status/merlin.json" << 'EOF'
{"agent":"merlin","timestamp":"2026-06-12T13:00:00Z","current_task":"Researching AI agent frameworks","status":"working","progress":"3 of 5 sources","blockers":[],"offering":["domain expertise","source verification"],"seeking":[],"last_active":"2026-06-12T13:00:00Z"}
EOF

cat > "$RT_DIR/status/percival.json" << 'EOF'
{"agent":"percival","timestamp":"2026-06-12T13:00:00Z","current_task":"Building CrewAI POC","status":"blocked","progress":"","blockers":["Need API credentials"],"offering":["build","design"],"seeking":["API keys"],"last_active":"2026-06-12T13:00:00Z"}
EOF

cat > "$RT_DIR/status/bedivere.json" << 'EOF'
{"agent":"bedivere","timestamp":"2026-06-12T13:00:00Z","current_task":"Writing API documentation","status":"done","progress":"Complete","blockers":[],"offering":["writing","editing"],"seeking":[],"last_active":"2026-06-12T13:00:00Z"}
EOF

cat > "$RT_DIR/status/lancelot.json" << 'EOF'
{"agent":"lancelot","timestamp":"2026-06-12T13:00:00Z","current_task":"Running QA test suite","status":"working","progress":"4 of 7 tests","blockers":[],"offering":["QA","testing"],"seeking":[],"last_active":"2026-06-12T13:00:00Z"}
EOF

echo "Status files written to $RT_DIR/status"
