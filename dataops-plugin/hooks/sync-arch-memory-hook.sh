#!/usr/bin/env bash
# SessionStart hook - sync architectural memory repos (quiet, non-blocking)
#
# This hook syncs memory repos from ADO at session start.
# Runs quietly and never fails the session - worst case, agents use stale cache.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="${SCRIPT_DIR}/../skills/sync-arch-memory/scripts/sync-arch-memory.sh"

if [[ -x "$SYNC_SCRIPT" ]]; then
  # Run quietly, capture output for debugging but don't show it
  result=$("$SYNC_SCRIPT" --quiet 2>&1) || true

  # Only report if there were actual sync operations (not just "fresh" status)
  if echo "$result" | grep -q '"action":"clone"\|"action":"pull"'; then
    echo "Architectural memory synced from ADO"
  fi
fi

# Always succeed - don't block session start
exit 0
