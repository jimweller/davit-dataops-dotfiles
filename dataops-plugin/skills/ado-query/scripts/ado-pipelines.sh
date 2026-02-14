#!/usr/bin/env bash
# ado-pipelines.sh - List pipelines in a project
# Usage: ado-pipelines.sh <project> [filter]
# Output: JSON array of {id, name, folder, queueStatus, revision}

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ado-common.sh"

ado::init

project="${1:-}"
filter="${2:-}"

if [[ -z "$project" ]]; then
    ado::error "Usage: ado-pipelines.sh <project> [filter]"
fi

# List pipelines (build definitions)
result=$(az pipelines list --organization "$AZURE_DEVOPS_ORG" --project "$project" --output json 2>/dev/null) || ado::error "Failed to list pipelines in project '$project'"

# Apply filter if provided
if [[ -n "$filter" ]]; then
    result=$(echo "$result" | ado::filter_ilike "name" "$filter")
fi

# Select relevant fields
echo "$result" | jq '[.[] | {id, name, folder: .path, queueStatus, revision}]'
