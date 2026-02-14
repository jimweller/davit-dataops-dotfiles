#!/usr/bin/env bash
set -uo pipefail

# ado-query status check
# Output: stderr = human-readable, stdout = JSON

SKILL_NAME="ado-query"

errors=()

# Check az CLI
if ! command -v az &>/dev/null; then
    printf "  ✗ az CLI not installed\n" >&2
    errors+=("az CLI missing")
else
    printf "  ✓ az CLI\n" >&2

    # Check azure-devops extension (only if az is installed)
    if az extension show --name azure-devops &>/dev/null 2>&1; then
        printf "  ✓ az devops extension\n" >&2
    else
        printf "  ✗ az devops extension (run: az extension add --name azure-devops)\n" >&2
        errors+=("az devops extension missing")
    fi
fi

# Check AZURE_DEVOPS_ORG environment variable
if [[ -n "${AZURE_DEVOPS_ORG:-}" ]]; then
    printf "  ✓ AZURE_DEVOPS_ORG set\n" >&2
else
    printf "  ✗ AZURE_DEVOPS_ORG not set\n" >&2
    errors+=("AZURE_DEVOPS_ORG not set")
fi

# Output JSON
if [[ ${#errors[@]} -eq 0 ]]; then
    jq -n --arg name "$SKILL_NAME" '{"available": true, "name": $name, "details": "ready"}'
else
    details=$(IFS=', '; echo "${errors[*]}")
    jq -n --arg name "$SKILL_NAME" --arg details "$details" '{"available": false, "name": $name, "details": $details}'
fi
