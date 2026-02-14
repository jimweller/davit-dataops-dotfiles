#!/usr/bin/env bash
# ado-repos.sh - List repos in a project
# Usage: ado-repos.sh <project> [filter]
# Output: JSON array of {id, name, defaultBranch, webUrl, size}

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ado-common.sh"

ado::init

project="${1:-}"
filter="${2:-}"

if [[ -z "$project" ]]; then
    ado::error "Usage: ado-repos.sh <project> [filter]"
fi

# List repos in project
result=$(az repos list --organization "$AZURE_DEVOPS_ORG" --project "$project" --output json 2>/dev/null) || ado::error "Failed to list repos in project '$project'"

# Apply filter if provided
if [[ -n "$filter" ]]; then
    result=$(echo "$result" | ado::filter_ilike "name" "$filter")
fi

# Select relevant fields
echo "$result" | jq '[.[] | {id, name, defaultBranch, webUrl, size}]'
