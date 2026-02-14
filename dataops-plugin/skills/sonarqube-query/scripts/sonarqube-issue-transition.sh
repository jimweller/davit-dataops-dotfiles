#!/usr/bin/env bash
# sonarqube-issue-transition.sh - Transition a SonarQube issue status
# Usage: sonarqube-issue-transition.sh <issue-key> <transition>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/sonarqube-common.sh"

show_usage() {
    cat <<EOF
Usage: $(basename "$0") <issue-key> <transition>

Change the status of a SonarQube issue.

Arguments:
  issue-key     Issue key (UUID)
  transition    One of: accept, wontfix, falsepositive, confirm, resolve, reopen

Transitions:
  accept         Mark as accepted (won't fix, by design)
  wontfix        Mark as won't fix
  falsepositive  Mark as false positive
  confirm        Confirm the issue exists
  resolve        Mark as resolved
  reopen         Reopen a resolved/accepted issue

Notes:
  - 'accept', 'wontfix', 'falsepositive' require "Administer Issues" permission
  - Available transitions depend on current issue status

Examples:
  $(basename "$0") abc-123-def accept
  $(basename "$0") abc-123-def falsepositive
  $(basename "$0") abc-123-def reopen
EOF
    exit 1
}

main() {
    local issue="${1:-}"
    local transition="${2:-}"

    [[ -z "$issue" || -z "$transition" ]] && show_usage
    [[ "$issue" == "-h" || "$issue" == "--help" ]] && show_usage

    # Validate transition name
    local valid_transitions="accept wontfix falsepositive confirm resolve reopen"
    if [[ ! " $valid_transitions " =~ " $transition " ]]; then
        sonar::error "Invalid transition: $transition. Must be one of: $valid_transitions"
    fi

    sonar::init

    # Get current issue state and available transitions
    local current
    current=$(sonar::api GET "/api/issues/search" "issues=${issue}&additionalFields=transitions")

    local issue_count
    issue_count=$(echo "$current" | jq '.issues | length')
    if [[ "$issue_count" -eq 0 ]]; then
        sonar::error "Issue not found: $issue"
    fi

    local current_status available_transitions project
    current_status=$(echo "$current" | jq -r '.issues[0].issueStatus')
    available_transitions=$(echo "$current" | jq -r '.issues[0].transitions | join(", ")')
    project=$(echo "$current" | jq -r '.issues[0].project')

    # Check if transition is available
    local is_available
    is_available=$(echo "$current" | jq --arg t "$transition" '.issues[0].transitions | contains([$t])')
    if [[ "$is_available" != "true" ]]; then
        sonar::error "Transition '$transition' not available. Current status: $current_status. Available: $available_transitions"
    fi

    # Perform transition
    local response
    response=$(sonar::api POST "/api/issues/do_transition" "issue=${issue}&transition=${transition}")

    # Extract result
    local new_status new_transitions
    new_status=$(echo "$response" | jq -r '.issue.issueStatus')
    new_transitions=$(echo "$response" | jq -r '.issue.transitions | join(", ")')

    jq -n \
        --arg issue "$issue" \
        --arg transition "$transition" \
        --arg previousStatus "$current_status" \
        --arg newStatus "$new_status" \
        --arg availableTransitions "$new_transitions" \
        --arg project "$project" \
        --arg uiUrl "$(sonar::issue_url "$project" "$issue")" \
        '{
            issue: $issue,
            transition: $transition,
            previousStatus: $previousStatus,
            newStatus: $newStatus,
            availableTransitions: $availableTransitions,
            project: $project,
            uiUrl: $uiUrl
        }'
}

main "$@"
