#!/usr/bin/env bash
set -uo pipefail

# openai-research status check
# Output: stderr = human-readable, stdout = JSON

SKILL_NAME="openai-research"

errors=()

# Check OPENAI_API_KEY
if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    printf "  ✓ OPENAI_API_KEY set\n" >&2
else
    printf "  ✗ OPENAI_API_KEY not set\n" >&2
    errors+=("OPENAI_API_KEY not set")
fi

# Output JSON
if [[ ${#errors[@]} -eq 0 ]]; then
    jq -n --arg name "$SKILL_NAME" '{"available": true, "name": $name, "details": "ready"}'
else
    details=$(IFS=', '; echo "${errors[*]}")
    jq -n --arg name "$SKILL_NAME" --arg details "$details" '{"available": false, "name": $name, "details": $details}'
fi
