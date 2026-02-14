#!/usr/bin/env bash
#
# pagerduty-service-reader.sh - Fetch and format PagerDuty service details
#
# Calls PagerDuty REST API directly to fetch service info and recent incidents.
#
# Usage:
#   pagerduty-service-reader.sh <service_id>
#   pagerduty-service-reader.sh <service_id> --json    # Raw JSON output
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

fetch_service() {
    local service_id="$1"

    curl -s -X GET \
        -H "Authorization: Token token=${PAGERDUTY_API_TOKEN}" \
        -H "Content-Type: application/json" \
        "${PAGERDUTY_API_BASE}/services/${service_id}?include[]=escalation_policies&include[]=teams"
}

fetch_service_incidents() {
    local service_id="$1"

    # Get recent incidents for this service (last 30 days)
    local since
    since=$(date -u -v-30d +"%Y-%m-%dT00:00:00Z" 2>/dev/null || date -u -d "30 days ago" +"%Y-%m-%dT00:00:00Z" 2>/dev/null || echo "")

    local url="${PAGERDUTY_API_BASE}/incidents?service_ids[]=${service_id}&limit=10&sort_by=created_at:desc"
    [[ -n "$since" ]] && url="${url}&since=${since}"

    curl -s -X GET \
        -H "Authorization: Token token=${PAGERDUTY_API_TOKEN}" \
        -H "Content-Type: application/json" \
        "$url"
}

fetch_oncalls() {
    local service_id="$1"

    # Fetch on-call for escalation policies associated with this service
    curl -s -X GET \
        -H "Authorization: Token token=${PAGERDUTY_API_TOKEN}" \
        -H "Content-Type: application/json" \
        "${PAGERDUTY_API_BASE}/oncalls?include[]=users&escalation_policy_ids[]="
}

# --- Formatting ---

format_service() {
    local service_json="$1"
    local incidents_json="$2"

    # Check for API errors
    if echo "$service_json" | jq -e '.error' >/dev/null 2>&1; then
        local error_msg
        error_msg=$(echo "$service_json" | jq -r '.error.message // "Unknown error"')
        echo "ERROR: $error_msg"
        return 1
    fi

    # Extract service data
    local service
    service=$(echo "$service_json" | jq '.service')

    if [[ "$service" == "null" ]]; then
        echo "ERROR: Service not found"
        return 1
    fi

    # Basic fields
    local id name status description created_at
    local team_name escalation_policy

    id=$(echo "$service" | jq -r '.id // "unknown"')
    name=$(echo "$service" | jq -r '.name // "Unknown"')
    status=$(echo "$service" | jq -r '.status // "unknown"')
    description=$(echo "$service" | jq -r '.description // "No description"' | head -c 300)
    created_at=$(echo "$service" | jq -r '.created_at // ""' | cut -d'T' -f1)

    # Team info
    team_name=$(echo "$service" | jq -r '.teams[0].summary // "No team"')

    # Escalation policy
    escalation_policy=$(echo "$service" | jq -r '.escalation_policy.summary // "None"')

    # Recent incidents
    local incident_count incident_table
    incident_count=$(echo "$incidents_json" | jq -r '.incidents | length // 0')

    if [[ "$incident_count" -gt 0 ]]; then
        incident_table=$(echo "$incidents_json" | jq -r '
            .incidents[:5] | .[] |
            "| #\(.incident_number) | \(.status) | \(.urgency) | \(.title[:40]) | \(.created_at | split("T")[0]) |"
        ')
    else
        incident_table="No recent incidents"
    fi

    # Count by status
    local triggered_count ack_count resolved_count
    triggered_count=$(echo "$incidents_json" | jq -r '[.incidents[] | select(.status == "triggered")] | length')
    ack_count=$(echo "$incidents_json" | jq -r '[.incidents[] | select(.status == "acknowledged")] | length')
    resolved_count=$(echo "$incidents_json" | jq -r '[.incidents[] | select(.status == "resolved")] | length')

    # Output structured markdown
    cat <<EOF
## Service: ${name}

**ID**: ${id}
**Status**: ${status}
**Team**: ${team_name}
**Escalation Policy**: ${escalation_policy}
**Created**: ${created_at}

### Description
${description}

### Recent Incidents (${incident_count} in last 30 days)
- Triggered: ${triggered_count}
- Acknowledged: ${ack_count}
- Resolved: ${resolved_count}

| # | Status | Urgency | Title | Created |
|---|--------|---------|-------|---------|
${incident_table}
EOF
}

# --- Main ---

usage() {
    cat <<EOF
PagerDuty Service Reader - Fetch and format PagerDuty service details

Usage:
  pagerduty-service-reader.sh <service_id>
  pagerduty-service-reader.sh <service_id> --json    # Raw JSON output

Environment:
  PAGERDUTY_API_TOKEN  - PagerDuty API token (v2)

Examples:
  pagerduty-service-reader.sh PG7CZUT
  pagerduty-service-reader.sh PABC123 --json

Note:
  Service IDs are typically ~7 chars and start with P (e.g., PG7CZUT)
  Incident IDs are typically ~14 chars and start with Q (e.g., Q0RIJJZL24RC6W)

  If you have an incident ID, use pagerduty-incident-reader.sh instead.
EOF
}

main() {
    local service_id=""
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
                if [[ -z "$service_id" ]]; then
                    service_id="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$service_id" ]]; then
        echo -e "${RED}Error: service_id required${NC}" >&2
        usage >&2
        exit 1
    fi

    check_env

    # Check ID format
    local id_type
    id_type=$(detect_id_type "$service_id")

    if [[ "$id_type" == "incident" ]]; then
        cat >&2 <<EOF
${RED}ERROR: ID format mismatch${NC}

The ID "${service_id}" appears to be an INCIDENT ID, not a service ID.
- Service IDs: ~7 chars, start with P (e.g., PG7CZUT)
- Incident IDs: ~14 chars, start with Q (e.g., Q0RIJJZL24RC6W)

To read incident details, use:
  pagerduty-incident-reader.sh ${service_id}

Or use the skill:
  /dataops-assistant:pagerduty-incident-reader ${service_id} | {context}
EOF
        exit 1
    fi

    echo -e "${YELLOW}Fetching service ${service_id}...${NC}" >&2

    # Fetch service data
    local service_response incidents_response
    service_response=$(fetch_service "$service_id")

    # Check for 404 or error before continuing
    if echo "$service_response" | jq -e '.error' >/dev/null 2>&1; then
        local error_code
        error_code=$(echo "$service_response" | jq -r '.error.code // 0')
        if [[ "$error_code" == "2100" ]]; then
            echo -e "${RED}ERROR: Service not found: ${service_id}${NC}" >&2
            echo "The service ID may be incorrect or the service may have been deleted." >&2
            exit 1
        fi
    fi

    # Fetch recent incidents
    incidents_response=$(fetch_service_incidents "$service_id")

    if [[ "$output_json" == "true" ]]; then
        jq -n \
            --argjson service "$service_response" \
            --argjson incidents "$incidents_response" \
            '{service: $service, incidents: $incidents}'
    else
        format_service "$service_response" "$incidents_response"
    fi
}

main "$@"
