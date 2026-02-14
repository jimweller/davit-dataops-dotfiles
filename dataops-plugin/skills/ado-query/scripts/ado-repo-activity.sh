#!/usr/bin/env bash
# ado-repo-activity.sh - Get repo activity stats
# Usage: ado-repo-activity.sh <project> <repo> [--author <email>] [--since <date>] [--top <N>]
# Output: JSON with {commitCount, recentCommits[], contributors[]}
#
# Date format: YYYY-MM-DD (e.g., 2025-01-01)
# Note: Author filter may require REST API for full support

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ado-common.sh"

ado::init

# Parse arguments
project=""
repo=""
author=""
since=""
top="20"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --author)
            author="$2"
            shift 2
            ;;
        --since)
            since="$2"
            shift 2
            ;;
        --top)
            top="$2"
            shift 2
            ;;
        *)
            if [[ -z "$project" ]]; then
                project="$1"
            elif [[ -z "$repo" ]]; then
                repo="$1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$project" ]] || [[ -z "$repo" ]]; then
    ado::error "Usage: ado-repo-activity.sh <project> <repo> [--author <email>] [--since <date>] [--top <N>]"
fi

# Build the az repos ref list command to get commits
# Note: az repos doesn't have a direct commit list, we use git log via REST API workaround
# For now, use az repos show to get basic stats

# Get repo info
repo_info=$(az repos show --organization "$AZURE_DEVOPS_ORG" --project "$project" --repository "$repo" --output json 2>/dev/null) || ado::error "Repo '$repo' not found in project '$project'"
repo_id=$(echo "$repo_info" | jq -r '.id')
default_branch=$(echo "$repo_info" | jq -r '.defaultBranch // "refs/heads/main"')

# Use az devops invoke to call commits API
# Build query parameters
query_params="searchCriteria.\$top=$top"

if [[ -n "$since" ]]; then
    query_params+="&searchCriteria.fromDate=$since"
fi

if [[ -n "$author" ]]; then
    query_params+="&searchCriteria.author=$author"
fi

# Get commits using REST API via az devops invoke
commits_result=$(az devops invoke \
    --organization "$AZURE_DEVOPS_ORG" \
    --area git \
    --resource commits \
    --route-parameters project="$project" repositoryId="$repo_id" \
    --query-parameters "$query_params" \
    --output json 2>/dev/null) || {
    # Fallback: return basic repo info without commits
    echo "{\"commitCount\": 0, \"recentCommits\": [], \"contributors\": [], \"error\": \"Could not fetch commits\"}"
    exit 0
}

# Extract commits
commits=$(echo "$commits_result" | jq '.value // []')
commit_count=$(echo "$commits" | jq 'length')

# Format recent commits
recent_commits=$(echo "$commits" | jq '[.[] | {
    commitId: .commitId[0:8],
    author: .author.name,
    email: .author.email,
    date: .author.date,
    comment: .comment
}]')

# Extract unique contributors
contributors=$(echo "$commits" | jq '[.[].author | {name, email}] | unique_by(.email)')

# Output combined result
jq -n \
    --argjson count "$commit_count" \
    --argjson commits "$recent_commits" \
    --argjson contributors "$contributors" \
    '{commitCount: $count, recentCommits: $commits, contributors: $contributors}'
