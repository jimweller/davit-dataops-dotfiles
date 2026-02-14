#!/usr/bin/env bash
# sonarqube-quality-gate.sh - Get quality gate status for a project
# Usage: sonarqube-quality-gate.sh <project-key> [options]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/sonarqube-common.sh"

show_usage() {
    cat <<EOF
Usage: $(basename "$0") <project-key> [options]

Get quality gate status for a SonarQube project.

Arguments:
  project-key    Project key (required)

Options:
  --branch <name>    Check specific branch
  --pr <id>          Check specific pull request
  -h, --help         Show this help

Examples:
  $(basename "$0") my-project
  $(basename "$0") my-project --branch develop
  $(basename "$0") my-project --pr 123
EOF
    exit 1
}

main() {
    local project=""
    local branch=""
    local pr=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) show_usage ;;
            --branch) branch="$2"; shift 2 ;;
            --pr) pr="$2"; shift 2 ;;
            -*) sonar::error "Unknown option: $1" ;;
            *)
                if [[ -z "$project" ]]; then
                    project="$1"
                else
                    sonar::error "Unexpected argument: $1"
                fi
                shift
                ;;
        esac
    done

    [[ -z "$project" ]] && show_usage

    sonar::init

    # Build query parameters
    local params="projectKey=${project}"
    [[ -n "$branch" ]] && params="${params}&branch=${branch}"
    [[ -n "$pr" ]] && params="${params}&pullRequest=${pr}"

    # Fetch quality gate status
    local response
    response=$(sonar::api GET "/api/qualitygates/project_status" "$params")

    local status
    status=$(echo "$response" | jq -r '.projectStatus.status')

    # Format conditions
    local conditions
    conditions=$(echo "$response" | jq '[.projectStatus.conditions[] | {
        metric: .metricKey,
        status,
        threshold: .errorThreshold,
        actual: .actualValue,
        comparator
    }]')

    local failed_count
    failed_count=$(echo "$conditions" | jq '[.[] | select(.status == "ERROR")] | length')

    jq -n \
        --arg project "$project" \
        --arg branch "$branch" \
        --arg pr "$pr" \
        --arg status "$status" \
        --argjson failedCount "$failed_count" \
        --argjson conditions "$conditions" \
        --arg uiUrl "$(sonar::project_issues_url "$project" "$branch")" \
        '{
            project: $project,
            branch: (if $branch != "" then $branch else null end),
            pullRequest: (if $pr != "" then $pr else null end),
            status: $status,
            failedConditions: $failedCount,
            conditions: $conditions,
            uiUrl: $uiUrl
        }'
}

main "$@"
