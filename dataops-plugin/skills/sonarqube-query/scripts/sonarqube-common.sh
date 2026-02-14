#!/usr/bin/env bash
# sonarqube-common.sh - Shared functions for SonarQube query scripts
# Source this file: source "$(dirname "$0")/sonarqube-common.sh"

set -euo pipefail

# --- Configuration ---
# Required environment variables:
#   SONARQUBE_BASE_URL  - SonarQube instance URL (e.g., https://sonar.example.com/)
#   SONARQUBE_USER_TOKEN - User token for API access (not analysis token)
#
# Generate a user token at: ${SONARQUBE_BASE_URL}account/security

# --- Utility Functions ---

# Output JSON error to stderr and exit
# Usage: sonar::error "message"
sonar::error() {
    local msg="$1"
    echo "{\"error\": \"$msg\"}" >&2
    exit 1
}

# Check that required env vars are set
sonar::require_config() {
    if [[ -z "${SONARQUBE_BASE_URL:-}" ]]; then
        sonar::error "SONARQUBE_BASE_URL environment variable not set"
    fi
    if [[ -z "${SONARQUBE_USER_TOKEN:-}" ]]; then
        sonar::error "SONARQUBE_USER_TOKEN environment variable not set. Generate at ${SONARQUBE_BASE_URL}account/security"
    fi
}

# Get normalized base URL (without trailing slash)
sonar::base_url() {
    echo "${SONARQUBE_BASE_URL%/}"
}

# Check API connectivity and authentication
sonar::check_auth() {
    local base
    base=$(sonar::base_url)

    local response
    response=$(curl -sS -w "\n%{http_code}" -u "${SONARQUBE_USER_TOKEN}:" "${base}/api/authentication/validate" 2>&1) || {
        sonar::error "Failed to connect to SonarQube at ${base}"
    }

    local http_code body
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" != "200" ]]; then
        sonar::error "SonarQube authentication failed (HTTP $http_code)"
    fi

    local valid
    valid=$(echo "$body" | jq -r '.valid // false')
    if [[ "$valid" != "true" ]]; then
        sonar::error "SonarQube token is invalid"
    fi
}

# Initialize: check config and auth
# Call this at the start of each script
sonar::init() {
    sonar::require_config
    sonar::check_auth
}

# Make an API request with authentication
# Usage: sonar::api GET "/api/issues/search" "param1=value1&param2=value2"
# Usage: sonar::api POST "/api/issues/do_transition" "issue=KEY&transition=accept"
sonar::api() {
    local method="$1"
    local endpoint="$2"
    local params="${3:-}"
    local base
    base=$(sonar::base_url)

    local url="${base}${endpoint}"
    local response http_code body

    if [[ "$method" == "GET" ]]; then
        [[ -n "$params" ]] && url="${url}?${params}"
        response=$(curl -sS -w "\n%{http_code}" -u "${SONARQUBE_USER_TOKEN}:" "$url" 2>&1)
    else
        response=$(curl -sS -w "\n%{http_code}" -X "$method" -u "${SONARQUBE_USER_TOKEN}:" "$url" -d "$params" 2>&1)
    fi

    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    # Check for API errors
    if [[ "$http_code" -ge 400 ]]; then
        local error_msg
        error_msg=$(echo "$body" | jq -r '.errors[0].msg // "Unknown error"' 2>/dev/null || echo "HTTP $http_code")
        sonar::error "API error: $error_msg"
    fi

    echo "$body"
}

# Filter JSON array by field value (case-insensitive)
# Usage: echo "$json" | sonar::filter_ilike "field" "pattern"
sonar::filter_ilike() {
    local field="$1"
    local pattern="$2"
    jq --arg f "$field" --arg p "$pattern" '[.[] | select(.[$f] | ascii_downcase | contains($p | ascii_downcase))]'
}

# Build direct UI URL for an issue
# Usage: sonar::issue_url "project-key" "issue-key" ["branch"]
sonar::issue_url() {
    local project="$1"
    local issue="$2"
    local branch="${3:-}"
    local base
    base=$(sonar::base_url)

    local url="${base}/project/issues?id=${project}&open=${issue}"
    [[ -n "$branch" ]] && url="${url}&branch=${branch}"
    echo "$url"
}

# Build direct UI URL for a security hotspot
# Usage: sonar::hotspot_url "project-key" "hotspot-key" ["branch"]
sonar::hotspot_url() {
    local project="$1"
    local hotspot="$2"
    local branch="${3:-}"
    local base
    base=$(sonar::base_url)

    local url="${base}/security_hotspots?id=${project}&hotspots=${hotspot}"
    [[ -n "$branch" ]] && url="${url}&branch=${branch}"
    echo "$url"
}

# Build direct UI URL for project issues list
# Usage: sonar::project_issues_url "project-key" ["branch"]
sonar::project_issues_url() {
    local project="$1"
    local branch="${2:-}"
    local base
    base=$(sonar::base_url)

    local url="${base}/project/issues?id=${project}"
    [[ -n "$branch" ]] && url="${url}&branch=${branch}"
    echo "$url"
}

# Extract specific fields from JSON array
# Usage: echo "$json" | sonar::select_fields "field1" "field2" ...
sonar::select_fields() {
    local fields=("$@")
    local jq_expr="{"
    local first=true

    for field in "${fields[@]}"; do
        if $first; then
            first=false
        else
            jq_expr+=", "
        fi
        jq_expr+="\"$field\": .$field"
    done
    jq_expr+="}"

    jq "[.[] | $jq_expr]"
}
