#!/usr/bin/env bash
# ado-service-endpoints.sh - List service connections
# Usage: ado-service-endpoints.sh <project> [filter]
# Output: JSON array of {id, name, type, url, isShared, isReady}

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ado-common.sh"

ado::init

project="${1:-}"
filter="${2:-}"

if [[ -z "$project" ]]; then
    ado::error "Usage: ado-service-endpoints.sh <project> [filter]"
fi

# List service endpoints
result=$(az devops service-endpoint list --organization "$AZURE_DEVOPS_ORG" --project "$project" --output json 2>/dev/null) || ado::error "Failed to list service endpoints in project '$project'"

# Apply filter if provided
if [[ -n "$filter" ]]; then
    result=$(echo "$result" | ado::filter_ilike "name" "$filter")
fi

# Select relevant fields
echo "$result" | jq '[.[] | {
    id,
    name,
    type,
    url,
    isShared,
    isReady
}]'
