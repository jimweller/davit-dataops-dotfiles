#!/usr/bin/env bash
# sonarqube-issues.sh - Search SonarQube issues for a project
# Usage: sonarqube-issues.sh <project-key> [options]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/sonarqube-common.sh"

show_usage() {
    cat <<EOF
Usage: $(basename "$0") <project-key> [options]

Search issues for a SonarQube project.

Arguments:
  project-key    Project key (required)

Options:
  --branch <name>       Filter by branch name
  --pr <id>             Filter by pull request ID
  --status <list>       Filter by status: OPEN,CONFIRMED,REOPENED,RESOLVED,CLOSED
  --severity <list>     Filter by severity: BLOCKER,CRITICAL,MAJOR,MINOR,INFO
  --type <list>         Filter by type: BUG,VULNERABILITY,CODE_SMELL
  --top <N>             Limit results (default: 100, max: 500)
  -h, --help            Show this help

Examples:
  $(basename "$0") my-project
  $(basename "$0") my-project --branch develop --status OPEN
  $(basename "$0") my-project --severity BLOCKER,CRITICAL
  $(basename "$0") my-project --pr 123
EOF
    exit 1
}

main() {
    local project=""
    local branch=""
    local pr=""
    local status=""
    local severity=""
    local type=""
    local top="100"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) show_usage ;;
            --branch) branch="$2"; shift 2 ;;
            --pr) pr="$2"; shift 2 ;;
            --status) status="$2"; shift 2 ;;
            --severity) severity="$2"; shift 2 ;;
            --type) type="$2"; shift 2 ;;
            --top) top="$2"; shift 2 ;;
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
    local params="componentKeys=${project}&ps=${top}&additionalFields=_all"
    [[ -n "$branch" ]] && params="${params}&branch=${branch}"
    [[ -n "$pr" ]] && params="${params}&pullRequest=${pr}"
    [[ -n "$status" ]] && params="${params}&statuses=${status}"
    [[ -n "$severity" ]] && params="${params}&severities=${severity}"
    [[ -n "$type" ]] && params="${params}&types=${type}"

    # Fetch issues
    local response
    response=$(sonar::api GET "/api/issues/search" "$params")

    local total
    total=$(echo "$response" | jq '.total')

    # Format output with UI URLs
    local issues
    issues=$(echo "$response" | jq --arg base "$(sonar::base_url)" --arg project "$project" --arg branch "$branch" '
        [.issues[] | {
            key,
            severity,
            status: .issueStatus,
            type,
            message,
            component: (.component | split(":") | .[-1]),
            line,
            rule,
            effort,
            tags,
            transitions,
            createdAt: .creationDate,
            uiUrl: ($base + "/project/issues?id=" + $project + "&open=" + .key + (if $branch != "" then "&branch=" + $branch else "" end))
        }]
    ')

    jq -n --argjson total "$total" --argjson issues "$issues" --arg project "$project" '{
        project: $project,
        total: $total,
        returned: ($issues | length),
        issues: $issues
    }'
}

main "$@"
