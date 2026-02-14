#!/usr/bin/env bash
#
# pagerduty-incident-reader.sh - Fetch and format PagerDuty incidents
#
# Calls PagerDuty REST API directly to fetch incident details.
#
# Usage:
#   pagerduty-incident-reader.sh <incident_id>
#   pagerduty-incident-reader.sh <incident_id> --json    # Raw JSON output
#
# Environment:
#   PAGERDUTY_API_TOKEN  - PagerDuty API token (v2)
#
# Output:
#   Structured markdown with key fields, ~500 tokens max

set -euo pipefail

# Colors for stderr output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# --- Configuration ---

PAGERDUTY_API_BASE="https://api.pagerduty.com"

check_env() {
    if [[ -z "${PAGERDUTY_API_TOKEN:-}" ]]; then
        echo -e "${RED}Error: PAGERDUTY_API_TOKEN environment variable not set${NC}" >&2
        exit 1
    fi
}

# --- ID Format Detection ---
# Service IDs: ~7 chars, start with P (e.g., PG7CZUT)
# Incident IDs: ~14 chars, start with Q (e.g., Q0RIJJZL24RC6W)

detect_id_type() {
    local id="$1"
    local len=${#id}

    # Short IDs (5-8 chars) starting with P are likely services
    if [[ $len -ge 5 && $len -le 8 && "$id" == P* ]]; then
        echo "service"
        return
    fi

    # Long IDs (12-16 chars) starting with Q are likely incidents
    if [[ $len -ge 12 && $len -le 16 && "$id" == Q* ]]; then
        echo "incident"
        return
    fi

    # Short IDs without P - likely service
    if [[ $len -ge 5 && $len -le 8 ]]; then
        echo "service"
        return
    fi

    # Long IDs without Q - likely incident
    if [[ $len -ge 12 && $len -le 16 ]]; then
        echo "incident"
        return
    fi

    echo "unknown"
}

# --- API Functions ---

fetch_incident() {
    local incident_id="$1"

    curl -s -X GET \
        -H "Authorization: Token token=${PAGERDUTY_API_TOKEN}" \
        -H "Content-Type: application/json" \
        "${PAGERDUTY_API_BASE}/incidents/${incident_id}"
}

fetch_incident_notes() {
    local incident_id="$1"

    curl -s -X GET \
        -H "Authorization: Token token=${PAGERDUTY_API_TOKEN}" \
        -H "Content-Type: application/json" \
        "${PAGERDUTY_API_BASE}/incidents/${incident_id}/notes"
}

fetch_incident_log_entries() {
    local incident_id="$1"

    curl -s -X GET \
        -H "Authorization: Token token=${PAGERDUTY_API_TOKEN}" \
        -H "Content-Type: application/json" \
        "${PAGERDUTY_API_BASE}/incidents/${incident_id}/log_entries?limit=10"
}

# --- Formatting ---

format_incident() {
    local incident_json="$1"
    local notes_json="$2"
    local logs_json="$3"

    # Check for API errors
    if echo "$incident_json" | jq -e '.error' >/dev/null 2>&1; then
        local error_msg
        error_msg=$(echo "$incident_json" | jq -r '.error.message // "Unknown error"')
        echo "ERROR: $error_msg"
        return 1
    fi

    # Extract incident data
    local incident
    incident=$(echo "$incident_json" | jq '.incident')

    if [[ "$incident" == "null" ]]; then
        echo "ERROR: Incident not found"
        return 1
    fi

    # Basic fields
    local id number title status urgency created_at resolved_at
    local service_name service_id assignee_name

    id=$(echo "$incident" | jq -r '.id // "unknown"')
    number=$(echo "$incident" | jq -r '.incident_number // "?"')
    title=$(echo "$incident" | jq -r '.title // "No title"')
    status=$(echo "$incident" | jq -r '.status // "unknown"')
    urgency=$(echo "$incident" | jq -r '.urgency // "unknown"')
    created_at=$(echo "$incident" | jq -r '.created_at // ""' | cut -d'T' -f1,2 | tr 'T' ' ' | cut -d':' -f1,2)
    resolved_at=$(echo "$incident" | jq -r '.resolved_at // ""')

    if [[ -n "$resolved_at" && "$resolved_at" != "null" ]]; then
        resolved_at=$(echo "$resolved_at" | cut -d'T' -f1,2 | tr 'T' ' ' | cut -d':' -f1,2)
    else
        resolved_at="ongoing"
    fi

    # Service info
    service_name=$(echo "$incident" | jq -r '.service.summary // "unknown"')
    service_id=$(echo "$incident" | jq -r '.service.id // "unknown"')

    # Assignees
    local assignees
    assignees=$(echo "$incident" | jq -r '[.assignments[]?.assignee.summary // empty] | join(", ")')
    [[ -z "$assignees" ]] && assignees="Unassigned"

    # Description/body (if available)
    local description
    description=$(echo "$incident" | jq -r '.body.details // .description // "No description"' | head -c 500)

    # Notes count and recent
    local notes_count recent_note
    notes_count=$(echo "$notes_json" | jq -r '.notes | length // 0')
    recent_note=$(echo "$notes_json" | jq -r '.notes[0].content // "None"' | head -c 200)

    # Timeline from log entries
    local timeline
    timeline=$(echo "$logs_json" | jq -r '
        [.log_entries[:5]? // [] | .[] |
            "\(.created_at | split("T")[0]) \(.created_at | split("T")[1] | split(":")[0:2] | join(":")): \(.summary // "Event")"
        ] | join("\n")
    ')
    [[ -z "$timeline" ]] && timeline="No timeline available"

    # Output structured markdown
    cat <<EOF
## Incident #${number}: ${title}

**ID**: ${id}
**Status**: ${status} | **Urgency**: ${urgency}
**Service**: ${service_name} (${service_id})
**Created**: ${created_at} | **Resolved**: ${resolved_at}
**Assignees**: ${assignees}

### Description
${description}

### Timeline (recent)
${timeline}

### Notes (${notes_count} total)
${recent_note}
EOF
}

# --- Main ---

usage() {
    cat <<EOF
PagerDuty Incident Reader - Fetch and format PagerDuty incidents

Usage:
  pagerduty-incident-reader.sh <incident_id>
  pagerduty-incident-reader.sh <incident_id> --json    # Raw JSON output

Environment:
  PAGERDUTY_API_TOKEN  - PagerDuty API token (v2)

Examples:
  pagerduty-incident-reader.sh Q0RIJJZL24RC6W
  pagerduty-incident-reader.sh Q0RIJJZL24RC6W --json

Note:
  Incident IDs are typically ~14 chars and start with Q (e.g., Q0RIJJZL24RC6W)
  Service IDs are typically ~7 chars and start with P (e.g., PG7CZUT)

  If you have a service ID, use pagerduty-service-reader.sh instead.
EOF
}

main() {
    local incident_id=""
    local output_json="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                output_json="true"
                shift
                ;;
            -h|--help|help)
                usage
                exit 0
                ;;
            *)
                if [[ -z "$incident_id" ]]; then
                    incident_id="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$incident_id" ]]; then
        echo -e "${RED}Error: incident_id required${NC}" >&2
        usage >&2
        exit 1
    fi

    check_env

    # Check ID format
    local id_type
    id_type=$(detect_id_type "$incident_id")

    if [[ "$id_type" == "service" ]]; then
        cat >&2 <<EOF
${RED}ERROR: ID format mismatch${NC}

The ID "${incident_id}" appears to be a SERVICE ID, not an incident ID.
- Service IDs: ~7 chars, start with P (e.g., PG7CZUT)
- Incident IDs: ~14 chars, start with Q (e.g., Q0RIJJZL24RC6W)

To read service details, use:
  pagerduty-service-reader.sh ${incident_id}

Or use the skill:
  /dataops-assistant:pagerduty-service-reader ${incident_id} | {context}
EOF
        exit 1
    fi

    echo -e "${YELLOW}Fetching incident ${incident_id}...${NC}" >&2

    # Fetch incident data
    local incident_response notes_response logs_response
    incident_response=$(fetch_incident "$incident_id")

    # Check for 404 or error before continuing
    if echo "$incident_response" | jq -e '.error' >/dev/null 2>&1; then
        local error_code
        error_code=$(echo "$incident_response" | jq -r '.error.code // 0')
        if [[ "$error_code" == "2001" ]]; then
            echo -e "${RED}ERROR: Incident not found: ${incident_id}${NC}" >&2
            echo "The incident ID may be incorrect or the incident may have been deleted." >&2
            exit 1
        fi
    fi

    # Fetch additional data
    notes_response=$(fetch_incident_notes "$incident_id")
    logs_response=$(fetch_incident_log_entries "$incident_id")

    if [[ "$output_json" == "true" ]]; then
        jq -n \
            --argjson incident "$incident_response" \
            --argjson notes "$notes_response" \
            --argjson logs "$logs_response" \
            '{incident: $incident, notes: $notes, logs: $logs}'
    else
        format_incident "$incident_response" "$notes_response" "$logs_response"
    fi
}

main "$@"
