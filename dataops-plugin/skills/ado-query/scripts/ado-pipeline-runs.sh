#!/usr/bin/env bash
# ado-pipeline-runs.sh - Get pipeline runs
# Usage: ado-pipeline-runs.sh <project> <pipeline-id> [--top N] [--since <date>] [--until <date>] [--status <status>]
# Output: JSON array of {id, buildNumber, status, result, startTime, finishTime, requestedFor, sourceBranch}
#
# Date format: YYYY-MM-DD
# Status: completed, inProgress, cancelling, postponed, notStarted, none

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ado-common.sh"

ado::init

# Parse arguments
project=""
pipeline_id=""
top="20"
since=""
until_date=""
status=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --top)
            top="$2"
            shift 2
            ;;
        --since)
            since="$2"
            shift 2
            ;;
        --until)
            until_date="$2"
            shift 2
            ;;
        --status)
            status="$2"
            shift 2
            ;;
        *)
            if [[ -z "$project" ]]; then
                project="$1"
            elif [[ -z "$pipeline_id" ]]; then
                pipeline_id="$1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$project" ]] || [[ -z "$pipeline_id" ]]; then
    ado::error "Usage: ado-pipeline-runs.sh <project> <pipeline-id> [--top N] [--since <date>] [--until <date>] [--status <status>]"
fi

# Build az pipelines runs list command
cmd_args=(--organization "$AZURE_DEVOPS_ORG" --project "$project" --pipeline-ids "$pipeline_id" --top "$top" --output json)

if [[ -n "$status" ]]; then
    cmd_args+=(--status "$status")
fi

# Note: az pipelines runs list doesn't support date filters directly
# We'll filter in post-processing

result=$(az pipelines runs list "${cmd_args[@]}" 2>/dev/null) || ado::error "Failed to list runs for pipeline '$pipeline_id'"

# Post-process date filters if provided
if [[ -n "$since" ]] || [[ -n "$until_date" ]]; then
    result=$(echo "$result" | jq --arg since "$since" --arg until "$until_date" '
        [.[] | select(
            (if $since != "" then (.startTime >= $since) else true end) and
            (if $until != "" then (.startTime <= $until) else true end)
        )]
    ')
fi

# Select relevant fields
echo "$result" | jq '[.[] | {
    id,
    buildNumber,
    status,
    result,
    startTime: .startTime,
    finishTime: .finishTime,
    requestedFor: .requestedFor.displayName,
    sourceBranch
}]'
