#!/usr/bin/env bash
# ado-reviewed-prs-fast.sh - List PRs where a user is a reviewer across projects (PARALLEL)
# Usage: ado-reviewed-prs-fast.sh [user] [--status active|completed|all] [--project <project>] [--all-projects] [--since YYYY-MM-DD]
# Output: JSON array of PRs with project context
#
# IMPORTANT: --project is required by default to avoid excessive API calls.
# Use --all-projects to query every project (slow, may trigger rate limiting).
# Or configure default projects in ~/.dataops-assistant/ado-query/projects.yaml

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ado-common.sh"

ado::init
ado::parse_pr_args "$@"

projects=$(ado::project_list "$project_filter" "$all_projects")
org_base="${AZURE_DEVOPS_ORG%/}"
pr_jq=$(ado::pr_fields)

query_reviewed_prs() {
    local project="$1"
    local output_file="$2"

    prs=$(az repos pr list \
        --organization "$AZURE_DEVOPS_ORG" \
        --project "$project" \
        --reviewer "$user" \
        --status "$status" \
        --output json 2>/dev/null) || prs="[]"

    if [[ -z "$prs" ]] || [[ "$prs" == "[]" ]]; then
        echo "[]" > "$output_file"
        return 0
    fi

    echo "$prs" | jq --arg proj "$project" --arg org "$org_base" "$pr_jq" > "$output_file"
}

ado::for_each_project_parallel query_reviewed_prs "$projects"
