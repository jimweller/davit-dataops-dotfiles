#!/usr/bin/env bash
set -uo pipefail

# read-macos-outlook-calendar status check
# Output: stderr = human-readable, stdout = JSON

SKILL_NAME="read-macos-outlook-calendar"

errors=()

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
    printf "  - macOS only (skipped on this platform)\n" >&2
    jq -n --arg name "$SKILL_NAME" '{"available": false, "name": $name, "details": "macOS only"}'
    exit 0
fi

printf "  ✓ macOS detected\n" >&2

# Check Outlook running
if ! pgrep -x "Microsoft Outlook" >/dev/null 2>&1; then
    printf "  ✗ Outlook not running\n" >&2
    errors+=("Outlook not running")
else
    printf "  ✓ Outlook running\n" >&2

    # Check if running New Outlook (incompatible with AppleScript)
    is_new_outlook=$(defaults read com.microsoft.Outlook IsRunningNewOutlook 2>/dev/null || echo "")

    if [[ "$is_new_outlook" == "1" ]] || [[ "$is_new_outlook" == "true" ]] || [[ "$is_new_outlook" == "YES" ]]; then
        printf "  ✗ New Outlook detected (requires Legacy Outlook)\n" >&2
        printf "    Switch via: Outlook menu > Legacy Outlook\n" >&2
        errors+=("New Outlook (need Legacy)")
    else
        printf "  ✓ Legacy Outlook\n" >&2
    fi
fi

# Output JSON
if [[ ${#errors[@]} -eq 0 ]]; then
    jq -n --arg name "$SKILL_NAME" '{"available": true, "name": $name, "details": "ready"}'
else
    details=$(IFS=', '; echo "${errors[*]}")
    jq -n --arg name "$SKILL_NAME" --arg details "$details" '{"available": false, "name": $name, "details": $details}'
fi
