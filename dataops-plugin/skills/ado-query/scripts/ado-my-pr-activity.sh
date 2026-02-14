#!/usr/bin/env bash
# ado-my-pr-activity.sh - List PRs where user has activity (created or reviewing)
# Usage: ado-my-pr-activity.sh [user] [--status active|completed|all] [--project <project>] [--all-projects] [--since YYYY-MM-DD]
# Output: JSON array of PRs with project context and activity type
#
# Activity includes:
# - PRs created by the user
# - PRs where the user is a reviewer
#
# Note: This does NOT include PRs where user only commented (would require expensive per-PR queries)
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

query_pr_activity() {
    local project="$1"
    local output_file="$2"

    # Query PRs created by user
    created_prs=$(az repos pr list \
        --organization "$AZURE_DEVOPS_ORG" \
        --project "$project" \
        --creator "$user" \
        --status "$status" \
        --output json 2>/dev/null) || created_prs="[]"
    [[ -z "$created_prs" ]] && created_prs="[]"

    # Query PRs where user is reviewer
    reviewed_prs=$(az repos pr list \
        --organization "$AZURE_DEVOPS_ORG" \
        --project "$project" \
        --reviewer "$user" \
        --status "$status" \
        --output json 2>/dev/null) || reviewed_prs="[]"
    [[ -z "$reviewed_prs" ]] && reviewed_prs="[]"

    # Combine and deduplicate, tag with activity type
    jq -n \
        --argjson created "$created_prs" \
        --argjson reviewed "$reviewed_prs" \
        --arg proj "$project" \
        --arg org "$org_base" \
        '
        ($created | map({
            project: $proj,
            pullRequestId,
            title,
            status,
            createdBy: .createdBy.displayName,
            creationDate,
            sourceRefName,
            targetRefName,
            repository: .repository.name,
            repositoryId: .repository.id,
            webUrl: ($org + "/" + $proj + "/_git/" + .repository.name + "/pullrequest/" + (.pullRequestId | tostring)),
            activityType: "creator"
        })) +
        ($reviewed | map({
            project: $proj,
            pullRequestId,
            title,
            status,
            createdBy: .createdBy.displayName,
            creationDate,
            sourceRefName,
            targetRefName,
            repository: .repository.name,
            repositoryId: .repository.id,
            webUrl: ($org + "/" + $proj + "/_git/" + .repository.name + "/pullrequest/" + (.pullRequestId | tostring)),
            activityType: "reviewer"
        })) |
        group_by(.pullRequestId) |
        map({
            project: .[0].project,
            pullRequestId: .[0].pullRequestId,
            title: .[0].title,
            status: .[0].status,
            createdBy: .[0].createdBy,
            creationDate: .[0].creationDate,
            sourceRefName: .[0].sourceRefName,
            targetRefName: .[0].targetRefName,
            repository: .[0].repository,
            repositoryId: .[0].repositoryId,
            webUrl: .[0].webUrl,
            activityTypes: (map(.activityType) | unique)
        })
        ' > "$output_file"
}

ado::for_each_project_parallel query_pr_activity "$projects"
