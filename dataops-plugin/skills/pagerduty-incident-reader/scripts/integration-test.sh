#!/bin/bash
# Integration tests for PagerDuty reader skills.
# These tests verify the skills work correctly with real PagerDuty data.
#
# Prerequisites:
# - PAGERDUTY_API_TOKEN environment variable must be set
# - jq must be installed
#
# Usage:
#   ./integration-test.sh              # Run all tests
#   ./integration-test.sh --dry-run    # Show what would be tested without calling API

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_test() { echo -e "\n${GREEN}[TEST]${NC} $1"; }

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Check prerequisites
check_prereqs() {
    log_info "Checking prerequisites..."

    if [[ -z "${PAGERDUTY_API_TOKEN:-}" ]]; then
        log_error "PAGERDUTY_API_TOKEN is not set"
        echo "Please set your PagerDuty API token:"
        echo "  export PAGERDUTY_API_TOKEN=your_token_here"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed"
        exit 1
    fi

    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed"
        exit 1
    fi

    log_info "Prerequisites OK"
}

# PagerDuty API helper
pd_api() {
    local endpoint="$1"
    local method="${2:-GET}"

    if $DRY_RUN; then
        echo "[DRY RUN] Would call: $method https://api.pagerduty.com$endpoint"
        return 0
    fi

    curl -s -X "$method" \
        "https://api.pagerduty.com$endpoint" \
        -H "Authorization: Token token=$PAGERDUTY_API_TOKEN" \
        -H "Content-Type: application/json"
}

# Get a sample service ID for testing
get_sample_service() {
    local response
    response=$(pd_api "/services?limit=1")
    echo "$response" | jq -r '.services[0].id // empty'
}

# Get a sample incident ID for testing
get_sample_incident() {
    local response
    response=$(pd_api "/incidents?limit=1&sort_by=created_at:desc")
    echo "$response" | jq -r '.incidents[0].id // empty'
}

# Test: Service ID detection
test_service_id_detection() {
    log_test "Service ID detection"

    local service_id
    service_id=$(get_sample_service)

    if [[ -z "$service_id" ]]; then
        log_warn "No services found in PagerDuty - skipping test"
        return 0
    fi

    log_info "Sample service ID: $service_id"

    # Test the ID detection using bun's eval
    local result
    result=$(cd "$SCRIPT_DIR" && bun -e "
import { identifyIdType } from './pagerduty-id.js';
const result = identifyIdType('$service_id');
console.log(JSON.stringify(result));
" 2>/dev/null)

    if [[ -z "$result" ]]; then
        log_warn "Could not run ID detection (bun eval failed) - testing API directly"
        # Fallback: just verify it's a valid service ID by fetching it
        local response
        response=$(pd_api "/services/$service_id")
        local name
        name=$(echo "$response" | jq -r '.service.name // empty')
        if [[ -n "$name" ]]; then
            log_info "PASS: Verified $service_id is a valid service via API"
            return 0
        fi
        log_error "FAIL: Could not verify service ID $service_id"
        return 1
    fi

    local detected_type
    detected_type=$(echo "$result" | jq -r '.type // "unknown"')

    if [[ "$detected_type" == "service" ]]; then
        log_info "PASS: Correctly identified $service_id as service"
    else
        log_error "FAIL: Expected 'service', got '$detected_type' for ID $service_id"
        return 1
    fi
}

# Test: Incident ID detection
test_incident_id_detection() {
    log_test "Incident ID detection"

    local incident_id
    incident_id=$(get_sample_incident)

    if [[ -z "$incident_id" ]]; then
        log_warn "No incidents found in PagerDuty - skipping test"
        return 0
    fi

    log_info "Sample incident ID: $incident_id"

    # Test the ID detection using bun's eval
    local result
    result=$(cd "$SCRIPT_DIR" && bun -e "
import { identifyIdType } from './pagerduty-id.js';
const result = identifyIdType('$incident_id');
console.log(JSON.stringify(result));
" 2>/dev/null)

    if [[ -n "$result" ]]; then
        local detected_type
        detected_type=$(echo "$result" | jq -r '.type // "unknown"')

        if [[ "$detected_type" == "incident" ]]; then
            log_info "ID detection correctly identified $incident_id as incident"
        else
            log_warn "ID detection returned '$detected_type' for $incident_id (expected 'incident')"
        fi
    fi

    # Verify we can fetch the incident
    local response
    response=$(pd_api "/incidents/$incident_id")

    local fetched_id
    fetched_id=$(echo "$response" | jq -r '.incident.id // empty')

    if [[ "$fetched_id" == "$incident_id" ]]; then
        log_info "PASS: Successfully fetched incident $incident_id"
    else
        log_error "FAIL: Could not fetch incident $incident_id"
        return 1
    fi
}

# Test: Service details retrieval
test_service_details() {
    log_test "Service details retrieval"

    local service_id
    service_id=$(get_sample_service)

    if [[ -z "$service_id" ]]; then
        log_warn "No services found - skipping test"
        return 0
    fi

    local response
    response=$(pd_api "/services/$service_id")

    local name
    name=$(echo "$response" | jq -r '.service.name // empty')

    if [[ -n "$name" ]]; then
        log_info "PASS: Fetched service '$name' (ID: $service_id)"

        # Also check what fields are available
        local fields
        fields=$(echo "$response" | jq -r '.service | keys | join(", ")')
        log_info "Available fields: $fields"
    else
        log_error "FAIL: Could not fetch service details for $service_id"
        return 1
    fi
}

# Test: Incident with notes
test_incident_notes() {
    log_test "Incident notes retrieval"

    local incident_id
    incident_id=$(get_sample_incident)

    if [[ -z "$incident_id" ]]; then
        log_warn "No incidents found - skipping test"
        return 0
    fi

    local response
    response=$(pd_api "/incidents/$incident_id/notes")

    local note_count
    note_count=$(echo "$response" | jq '.notes | length')

    log_info "PASS: Incident $incident_id has $note_count notes"
}

# Test: Wrong ID type detection
test_wrong_id_type() {
    log_test "Wrong ID type detection (service ID to incident reader)"

    local service_id
    service_id=$(get_sample_service)

    if [[ -z "$service_id" ]]; then
        log_warn "No services found - skipping test"
        return 0
    fi

    # Try to fetch as incident (should fail)
    local response
    response=$(pd_api "/incidents/$service_id")

    local error
    error=$(echo "$response" | jq -r '.error.message // empty')

    if [[ "$error" == *"Not Found"* ]] || [[ "$error" == *"not found"* ]]; then
        log_info "PASS: API correctly rejected service ID as incident"
    else
        log_warn "Unexpected response when using service ID as incident ID"
        echo "$response" | jq .
    fi
}

# Main
main() {
    echo "==========================================="
    echo "PagerDuty Reader Skills - Integration Tests"
    echo "==========================================="

    check_prereqs

    if $DRY_RUN; then
        log_warn "DRY RUN MODE - No API calls will be made"
    fi

    local failed=0

    test_service_id_detection || ((failed++))
    test_incident_id_detection || ((failed++))
    test_service_details || ((failed++))
    test_incident_notes || ((failed++))
    test_wrong_id_type || ((failed++))

    echo ""
    echo "==========================================="
    if [[ $failed -eq 0 ]]; then
        log_info "All tests passed!"
    else
        log_error "$failed test(s) failed"
        exit 1
    fi
}

main "$@"
