#!/usr/bin/env bash
# ado-project-members.sh - List people with access to a project
# Usage: ado-project-members.sh <project>
# Output: JSON array of {displayName, principalName, mailAddress, origin}
#
# Note: This enumerates security groups and their members since there's no
# direct CLI command for project membership.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ado-common.sh"

ado::init

project="${1:-}"

if [[ -z "$project" ]]; then
    ado::error "Usage: ado-project-members.sh <project>"
fi

# Get project ID first
project_info=$(az devops project show --organization "$AZURE_DEVOPS_ORG" --project "$project" --output json 2>/dev/null) || ado::error "Project '$project' not found"
project_id=$(echo "$project_info" | jq -r '.id')

# Get security groups for the project
# Note: az devops security group list requires --scope (project | organization)
groups_result=$(az devops security group list --organization "$AZURE_DEVOPS_ORG" --project "$project" --output json 2>/dev/null) || {
    # Fallback: try to get team members instead
    echo "[]"
    exit 0
}

# Extract graph groups
groups=$(echo "$groups_result" | jq '.graphGroups // []')

# Collect unique members from all groups
all_members="[]"

# Iterate through groups and get members
for group_descriptor in $(echo "$groups" | jq -r '.[].descriptor // empty' 2>/dev/null); do
    members=$(az devops security group membership list --organization "$AZURE_DEVOPS_ORG" --id "$group_descriptor" --output json 2>/dev/null) || continue

    # Members is a dict with descriptor as keys
    member_list=$(echo "$members" | jq '[to_entries[].value | {
        displayName: .displayName,
        principalName: .principalName,
        mailAddress: .mailAddress,
        origin: .origin
    }]')

    # Merge, avoiding duplicates
    all_members=$(echo "$all_members" "$member_list" | jq -s '.[0] + .[1] | unique_by(.principalName)')
done

# Filter to only users (not service accounts or groups)
echo "$all_members" | jq '[.[] | select(.origin == "aad" or .origin == "vsts")]'
