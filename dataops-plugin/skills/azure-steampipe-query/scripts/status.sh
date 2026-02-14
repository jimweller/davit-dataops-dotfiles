#!/usr/bin/env bash
set -uo pipefail

# azure-steampipe-query status check
# Output: stderr = human-readable, stdout = JSON

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(dirname "$SCRIPT_DIR")"
SKILL_NAME="azure-steampipe-query"

# Paths (match bootstrap.sh and steampipe-query.sh)
DATAOPS_DIR="${DATAOPS_ASSISTANT_DIR:-$HOME/.dataops-assistant}"
STEAMPIPE_DIR="${DATAOPS_ASSISTANT_AZURE_STEAMPIPE_DIR:-$DATAOPS_DIR/steampipe-azure}"

errors=()

# Check steampipe CLI
if ! command -v steampipe &>/dev/null; then
    printf "  ✗ steampipe CLI not installed\n" >&2
    errors+=("steampipe CLI missing")
else
    printf "  ✓ steampipe CLI\n" >&2
fi

# Check az CLI
if ! command -v az &>/dev/null; then
    printf "  ✗ az CLI not installed\n" >&2
    errors+=("az CLI missing")
else
    printf "  ✓ az CLI\n" >&2
fi

# Check az login
if ! az account show &>/dev/null 2>&1; then
    printf "  ✗ az not authenticated (run: az login)\n" >&2
    errors+=("az not authenticated")
else
    printf "  ✓ az authenticated\n" >&2
fi

# Check bootstrap
if [[ -d "$STEAMPIPE_DIR/internal" ]] && [[ -d "$STEAMPIPE_DIR/plugins" ]]; then
    printf "  ✓ bootstrapped\n" >&2
else
    printf "  ✗ not bootstrapped (run: ./skills/azure-steampipe-query/scripts/bootstrap.sh)\n" >&2
    errors+=("not bootstrapped")
fi

# Output JSON
if [[ ${#errors[@]} -eq 0 ]]; then
    jq -n --arg name "$SKILL_NAME" '{"available": true, "name": $name, "details": "ready"}'
else
    details=$(IFS=', '; echo "${errors[*]}")
    jq -n --arg name "$SKILL_NAME" --arg details "$details" '{"available": false, "name": $name, "details": $details}'
fi
