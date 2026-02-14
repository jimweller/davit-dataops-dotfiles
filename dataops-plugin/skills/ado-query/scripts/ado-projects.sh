#!/usr/bin/env bash
# ado-projects.sh - List all ADO projects
# Usage: ado-projects.sh [filter]
# Output: JSON array of {id, name, description, state}

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ado-common.sh"

ado::init

filter="${1:-}"

# List all projects
result=$(az devops project list --organization "$AZURE_DEVOPS_ORG" --output json 2>/dev/null) || ado::error "Failed to list projects"

# Extract the value array (az devops project list returns {value: [...], count: N})
projects=$(echo "$result" | jq '.value // []')

# Apply filter if provided
if [[ -n "$filter" ]]; then
    projects=$(echo "$projects" | ado::filter_ilike "name" "$filter")
fi

# Select relevant fields
echo "$projects" | jq '[.[] | {id, name, description, state}]'
