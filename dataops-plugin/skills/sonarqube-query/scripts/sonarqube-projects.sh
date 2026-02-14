#!/usr/bin/env bash
# sonarqube-projects.sh - List SonarQube projects
# Usage: sonarqube-projects.sh [filter]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/sonarqube-common.sh"

show_usage() {
    cat <<EOF
Usage: $(basename "$0") [filter]

List SonarQube projects, optionally filtered by name.

Arguments:
  filter    Optional case-insensitive name filter

Examples:
  $(basename "$0")                  # List all projects
  $(basename "$0") payment          # Filter by name containing "payment"
  $(basename "$0") clinical         # Filter by name containing "clinical"
EOF
    exit 1
}

main() {
    local filter="${1:-}"

    # Handle help
    [[ "$filter" == "-h" || "$filter" == "--help" ]] && show_usage

    sonar::init

    # Fetch projects (using components/search which works with analysis tokens too)
    local response
    response=$(sonar::api GET "/api/components/search" "qualifiers=TRK&ps=500")

    local projects
    projects=$(echo "$response" | jq '[.components[] | {key, name, qualifier}]')

    # Apply filter if provided
    if [[ -n "$filter" ]]; then
        projects=$(echo "$projects" | sonar::filter_ilike "name" "$filter")
    fi

    # Add count and output
    local count
    count=$(echo "$projects" | jq 'length')

    jq -n --argjson projects "$projects" --argjson count "$count" '{
        count: $count,
        projects: $projects
    }'
}

main "$@"
