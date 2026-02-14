#!/usr/bin/env bash
#
# jira-api.sh - Jira REST API wrapper
#
# Usage:
#   jira-api.sh get <issue_key>
#   jira-api.sh create <project_key> <issue_type> <summary> <file|-> [options]
#   jira-api.sh update <issue_key> <file|-> [--md] [--fix-version <name>]
#   jira-api.sh comment <issue_key> <file|-> [--md] [--fix-version <name>]
#   jira-api.sh set-fix-version <issue_key> <version_name>
#   jira-api.sh link <from_issue> <link_type> <to_issue>
#   jira-api.sh version-list <project_key>
#   jira-api.sh version-get <project_key> <version_name>
#   jira-api.sh version-create <project_key> <name> [options]
#   jira-api.sh version-update <project_key> <version_name> [options]
#
# Create Options:
#   --md                  Input is styled markdown (converted to ADF automatically)
#   --assignee <id>       Assignee account ID (NOT email - must be resolved first)
#   --component <name>    Component name (can be specified multiple times)
#   --parent <key>        Parent issue key (for sub-tasks or stories under epics)
#   --dry-run             Print the request body JSON instead of calling API (for testing)
#
# Note: Use "-" as file to read from stdin (avoids temp files).
#
# Environment:
#   ATLASSIAN_EMAIL      - Atlassian account email
#   ATLASSIAN_API_TOKEN  - API token (NOT password)
#   ATLASSIAN_BASE_URL   - e.g., https://company.atlassian.net
#
# Markdown Style Guide (with --md):
#   :::context ... :::  - Context block with CONTEXT lozenge
#   ## H2               - Bold + grey heading
#   ### H3              - Bold + grey heading
#   #### H4             - Bold + blue heading
#   {status:TEXT:color} - Status lozenge
#   **bold**, *italic*, `code`, [link](url)
#   - bullets, 1. numbered
#   | tables |
#   PROJ-123            - Auto inline card
#
# Link types (case-insensitive):
#   Standard (all Jira versions):
#     blocks        - "PROJ-1 blocks PROJ-2" means PROJ-2 can't start until PROJ-1 is done
#     is-blocked-by - "PROJ-1 is-blocked-by PROJ-2" means PROJ-1 can't start until PROJ-2 is done
#     relates-to    - Related issues (no dependency)
#     duplicates    - "PROJ-1 duplicates PROJ-2" means PROJ-1 is a duplicate of PROJ-2
#     clones        - "PROJ-1 clones PROJ-2" means PROJ-1 is a clone of PROJ-2
#     is-cloned-by  - "PROJ-1 is-cloned-by PROJ-2" means PROJ-2 is a clone of PROJ-1
#   Extended (Jira Cloud only):
#     causes        - "PROJ-1 causes PROJ-2" means PROJ-1 directly results in PROJ-2
#     is-caused-by  - "PROJ-1 is-caused-by PROJ-2" means PROJ-2 directly results in PROJ-1
#
# Examples:
#   jira-api.sh get PROJ-123
#   jira-api.sh create PROJ Story "My Issue" description.md --md
#   echo 'markdown...' | jira-api.sh create PROJ Story "My Issue" - --md
#   jira-api.sh create PROJ Story "My Issue" - --md --assignee 5b10ac8d82e05b22cc7d4ef5
#   jira-api.sh create PROJ Story "My Issue" - --md --parent PROJ-100 --component "Backend"
#   jira-api.sh update PROJ-123 description.md --md
#   jira-api.sh update PROJ-123 description.md --md --fix-version "2024.01"
#   jira-api.sh comment PROJ-123 release-notes.md --md --fix-version "2024.01"
#   echo '{"version":1,...}' | jira-api.sh comment PROJ-123 -
#   jira-api.sh set-fix-version PROJ-123 "2024.01"
#   jira-api.sh link PROJ-123 blocks PROJ-456
#   jira-api.sh link PROJ-123 is-blocked-by PROJ-456
#   jira-api.sh link PROJ-123 relates-to PROJ-456
#   jira-api.sh link PROJ-123 clones PROJ-456

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# --- Configuration ---

check_env() {
    local missing=()
    [[ -z "${ATLASSIAN_EMAIL:-}" ]] && missing+=("ATLASSIAN_EMAIL")
    [[ -z "${ATLASSIAN_API_TOKEN:-}" ]] && missing+=("ATLASSIAN_API_TOKEN")
    [[ -z "${ATLASSIAN_BASE_URL:-}" ]] && missing+=("ATLASSIAN_BASE_URL")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}Error: Missing required environment variables:${NC}" >&2
        printf '  - %s\n' "${missing[@]}" >&2
        exit 1
    fi
}

normalize_base_url() {
    local url="$ATLASSIAN_BASE_URL"
    # Remove trailing slashes
    url="${url%/}"
    # Remove /jira or /wiki suffixes if present
    url="${url%/jira}"
    url="${url%/wiki}"
    echo "$url"
}

get_auth_header() {
    echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64
}

# --- API Functions ---

api_get() {
    local endpoint="$1"
    local base_url
    base_url=$(normalize_base_url)

    curl -s -X GET \
        -H "Authorization: Basic $(get_auth_header)" \
        -H "Content-Type: application/json" \
        "${base_url}${endpoint}"
}

api_post() {
    local endpoint="$1"
    local data="$2"
    local base_url
    base_url=$(normalize_base_url)

    curl -s -X POST \
        -H "Authorization: Basic $(get_auth_header)" \
        -H "Content-Type: application/json" \
        -d "$data" \
        "${base_url}${endpoint}"
}

api_put() {
    local endpoint="$1"
    local data="$2"
    local base_url
    base_url=$(normalize_base_url)

    curl -s -X PUT \
        -H "Authorization: Basic $(get_auth_header)" \
        -H "Content-Type: application/json" \
        -d "$data" \
        "${base_url}${endpoint}"
}

# --- Helper Functions ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Extract project key from issue key (e.g., PROJ-123 -> PROJ)
get_project_from_issue() {
    local issue_key="$1"
    echo "${issue_key%%-*}"
}

# Look up version ID by name for a project
# Returns version ID or empty string if not found
get_version_id() {
    local project_key="$1"
    local version_name="$2"

    local response
    response=$(api_get "/rest/api/3/project/${project_key}/versions")

    # Check for errors
    if echo "$response" | jq -e '.errorMessages' >/dev/null 2>&1; then
        echo -e "${RED}Error fetching versions:${NC}" >&2
        echo "$response" | jq -r '.errorMessages[]' >&2
        return 1
    fi

    # Find version by name (exact match)
    local version_id
    version_id=$(echo "$response" | jq -r --arg name "$version_name" '.[] | select(.name == $name) | .id')

    if [[ -z "$version_id" ]]; then
        echo -e "${RED}Error: Version '${version_name}' not found in project ${project_key}${NC}" >&2
        echo -e "${YELLOW}Available versions:${NC}" >&2
        echo "$response" | jq -r '.[].name' | head -10 >&2
        return 1
    fi

    echo "$version_id"
}

read_content() {
    local file="$1"
    local is_markdown="$2"

    local content
    if [[ "$file" == "-" ]]; then
        content=$(cat)
    elif [[ -f "$file" ]]; then
        content=$(cat "$file")
    else
        echo -e "${RED}Error: File not found: $file${NC}" >&2
        exit 1
    fi

    # Validate content is non-empty (catch silent upstream failures)
    local trimmed
    trimmed=$(echo "$content" | sed '/^[[:space:]]*$/d')
    if [[ -z "$trimmed" ]]; then
        echo -e "${RED}Error: Content is empty. Nothing was piped or the file has no content.${NC}" >&2
        echo "Hint: If piping a draft file, pass the whole file — md-to-adf.js strips frontmatter automatically." >&2
        exit 1
    fi

    if [[ "$is_markdown" == "true" ]]; then
        # Convert markdown to ADF using the converter
        local converter="${SCRIPT_DIR}/md-to-adf.js"
        if [[ ! -x "$converter" ]]; then
            echo -e "${RED}Error: Markdown converter not found: $converter${NC}" >&2
            exit 1
        fi
        echo "$content" | "$converter"
    else
        echo "$content"
    fi
}

# Legacy function for backwards compatibility
read_adf_content() {
    local adf_file="$1"
    read_content "$adf_file" "false"
}

# --- Commands ---

cmd_get() {
    local issue_key="${1:-}"

    if [[ -z "$issue_key" ]]; then
        echo -e "${RED}Error: issue_key required${NC}" >&2
        echo "Usage: jira-api.sh get <issue_key>" >&2
        exit 1
    fi

    local response
    response=$(api_get "/rest/api/3/issue/${issue_key}")

    # Check for errors
    if echo "$response" | jq -e '.errorMessages' >/dev/null 2>&1; then
        echo -e "${RED}Error fetching issue:${NC}" >&2
        echo "$response" | jq -r '.errorMessages[]' >&2
        exit 1
    fi

    echo "$response"
}

cmd_create() {
    local project_key=""
    local issue_type=""
    local summary=""
    local content_file=""
    local is_markdown="false"
    local assignee=""
    local parent=""
    local components=()
    local dry_run="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --md)
                is_markdown="true"
                shift
                ;;
            --assignee)
                assignee="$2"
                shift 2
                ;;
            --component)
                components+=("$2")
                shift 2
                ;;
            --parent)
                parent="$2"
                shift 2
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            *)
                if [[ -z "$project_key" ]]; then
                    project_key="$1"
                elif [[ -z "$issue_type" ]]; then
                    issue_type="$1"
                elif [[ -z "$summary" ]]; then
                    summary="$1"
                elif [[ -z "$content_file" ]]; then
                    content_file="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$project_key" ]] || [[ -z "$issue_type" ]] || [[ -z "$summary" ]] || [[ -z "$content_file" ]]; then
        echo -e "${RED}Error: project_key, issue_type, summary, and content_file required${NC}" >&2
        echo "Usage: jira-api.sh create <project_key> <issue_type> <summary> <file|-> [options]" >&2
        exit 1
    fi

    echo -e "${YELLOW}Creating issue in ${project_key}...${NC}" >&2

    # Read content (convert from markdown if --md flag)
    local adf_content
    adf_content=$(read_content "$content_file" "$is_markdown")

    # Build request body - start with required fields
    local body
    body=$(jq -n \
        --arg project "$project_key" \
        --arg issuetype "$issue_type" \
        --arg summary "$summary" \
        --argjson description "$adf_content" \
        '{
            fields: {
                project: { key: $project },
                issuetype: { name: $issuetype },
                summary: $summary,
                description: $description
            }
        }')

    # Add assignee if provided (must be account ID, not email)
    if [[ -n "$assignee" ]]; then
        body=$(echo "$body" | jq --arg assignee "$assignee" '.fields.assignee = { id: $assignee }')
    fi

    # Add parent if provided (for sub-tasks or stories under epics)
    if [[ -n "$parent" ]]; then
        body=$(echo "$body" | jq --arg parent "$parent" '.fields.parent = { key: $parent }')
    fi

    # Add components if provided
    if [[ ${#components[@]} -gt 0 ]]; then
        local components_json="[]"
        for comp in "${components[@]}"; do
            components_json=$(echo "$components_json" | jq --arg name "$comp" '. + [{ name: $name }]')
        done
        body=$(echo "$body" | jq --argjson components "$components_json" '.fields.components = $components')
    fi

    # Dry-run mode: output the request body and exit
    if [[ "$dry_run" == "true" ]]; then
        echo "$body"
        return 0
    fi

    local response
    response=$(api_post "/rest/api/3/issue" "$body")

    # Check for errors
    if echo "$response" | jq -e '.errorMessages' >/dev/null 2>&1; then
        echo -e "${RED}Error creating issue:${NC}" >&2
        echo "$response" | jq -r '.errorMessages[]' >&2
        if echo "$response" | jq -e '.errors' >/dev/null 2>&1; then
            echo "$response" | jq -r '.errors | to_entries[] | "\(.key): \(.value)"' >&2
        fi
        exit 1
    fi

    # Output success info
    local issue_key issue_id
    issue_key=$(echo "$response" | jq -r '.key')
    issue_id=$(echo "$response" | jq -r '.id')

    local base_url
    base_url=$(normalize_base_url)
    local issue_url="${base_url}/browse/${issue_key}"

    jq -n \
        --arg action "CREATE" \
        --arg status "success" \
        --arg issue_key "$issue_key" \
        --arg issue_id "$issue_id" \
        --arg issue_url "$issue_url" \
        --arg message "Issue created successfully" \
        '{
            action: $action,
            status: $status,
            issue_key: $issue_key,
            issue_id: $issue_id,
            issue_url: $issue_url,
            message: $message
        }'
}

cmd_update() {
    local issue_key=""
    local content_file=""
    local is_markdown="false"
    local fix_version=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --md)
                is_markdown="true"
                shift
                ;;
            --fix-version)
                fix_version="$2"
                shift 2
                ;;
            *)
                if [[ -z "$issue_key" ]]; then
                    issue_key="$1"
                elif [[ -z "$content_file" ]]; then
                    content_file="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$issue_key" ]] || [[ -z "$content_file" ]]; then
        echo -e "${RED}Error: issue_key and content_file required${NC}" >&2
        echo "Usage: jira-api.sh update <issue_key> <file|-> [--md] [--fix-version <name>]" >&2
        exit 1
    fi

    echo -e "${YELLOW}Updating ${issue_key}...${NC}" >&2

    # Read content (convert from markdown if --md flag)
    local adf_content
    adf_content=$(read_content "$content_file" "$is_markdown")

    # Build request body - start with description
    local body
    body=$(jq -n \
        --argjson description "$adf_content" \
        '{
            fields: {
                description: $description
            }
        }')

    # Add fix version if provided
    if [[ -n "$fix_version" ]]; then
        local project_key
        project_key=$(get_project_from_issue "$issue_key")

        local version_id
        if ! version_id=$(get_version_id "$project_key" "$fix_version"); then
            exit 1
        fi

        echo -e "${YELLOW}Setting fix version: ${fix_version} (ID: ${version_id})${NC}" >&2
        body=$(echo "$body" | jq --arg vid "$version_id" '.fields.fixVersions = [{ id: $vid }]')
    fi

    local response
    response=$(api_put "/rest/api/3/issue/${issue_key}" "$body")

    # Check for errors (PUT returns empty on success)
    if [[ -n "$response" ]] && echo "$response" | jq -e '.errorMessages' >/dev/null 2>&1; then
        echo -e "${RED}Error updating issue:${NC}" >&2
        echo "$response" | jq -r '.errorMessages[]' >&2
        exit 1
    fi

    local base_url
    base_url=$(normalize_base_url)
    local issue_url="${base_url}/browse/${issue_key}"

    # Build success message
    local message="Issue description updated successfully"
    if [[ -n "$fix_version" ]]; then
        message="Issue updated successfully (description + fix version: ${fix_version})"
    fi

    jq -n \
        --arg action "UPDATE" \
        --arg status "success" \
        --arg issue_key "$issue_key" \
        --arg issue_url "$issue_url" \
        --arg message "$message" \
        '{
            action: $action,
            status: $status,
            issue_key: $issue_key,
            issue_url: $issue_url,
            message: $message
        }'
}

cmd_comment() {
    local issue_key=""
    local content_file=""
    local is_markdown="false"
    local fix_version=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --md)
                is_markdown="true"
                shift
                ;;
            --fix-version)
                fix_version="$2"
                shift 2
                ;;
            *)
                if [[ -z "$issue_key" ]]; then
                    issue_key="$1"
                elif [[ -z "$content_file" ]]; then
                    content_file="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$issue_key" ]] || [[ -z "$content_file" ]]; then
        echo -e "${RED}Error: issue_key and content_file required${NC}" >&2
        echo "Usage: jira-api.sh comment <issue_key> <file|-> [--md] [--fix-version <name>]" >&2
        exit 1
    fi

    echo -e "${YELLOW}Adding comment to ${issue_key}...${NC}" >&2

    # Read content (convert from markdown if --md flag)
    local adf_content
    adf_content=$(read_content "$content_file" "$is_markdown")

    # Build request body
    local body
    body=$(jq -n \
        --argjson body "$adf_content" \
        '{
            body: $body
        }')

    local response
    response=$(api_post "/rest/api/3/issue/${issue_key}/comment" "$body")

    # Check for errors
    if echo "$response" | jq -e '.errorMessages' >/dev/null 2>&1; then
        echo -e "${RED}Error adding comment:${NC}" >&2
        echo "$response" | jq -r '.errorMessages[]' >&2
        exit 1
    fi

    local comment_id
    comment_id=$(echo "$response" | jq -r '.id')

    # Set fix version if requested (separate API call)
    if [[ -n "$fix_version" ]]; then
        local project_key
        project_key=$(get_project_from_issue "$issue_key")

        local version_id
        if ! version_id=$(get_version_id "$project_key" "$fix_version"); then
            echo -e "${RED}Warning: Comment added but fix version update failed${NC}" >&2
            exit 1
        fi

        echo -e "${YELLOW}Setting fix version: ${fix_version} (ID: ${version_id})${NC}" >&2

        local update_body
        update_body=$(jq -n --arg vid "$version_id" '{ fields: { fixVersions: [{ id: $vid }] } }')

        local update_response
        update_response=$(api_put "/rest/api/3/issue/${issue_key}" "$update_body")

        # Check for errors (PUT returns empty on success)
        if [[ -n "$update_response" ]] && echo "$update_response" | jq -e '.errorMessages' >/dev/null 2>&1; then
            echo -e "${RED}Warning: Comment added but fix version update failed:${NC}" >&2
            echo "$update_response" | jq -r '.errorMessages[]' >&2
            exit 1
        fi
    fi

    local base_url
    base_url=$(normalize_base_url)
    local issue_url="${base_url}/browse/${issue_key}"

    # Build success message
    local message="Comment added successfully"
    if [[ -n "$fix_version" ]]; then
        message="Comment added and fix version set to ${fix_version}"
    fi

    jq -n \
        --arg action "COMMENT" \
        --arg status "success" \
        --arg issue_key "$issue_key" \
        --arg comment_id "$comment_id" \
        --arg issue_url "$issue_url" \
        --arg message "$message" \
        '{
            action: $action,
            status: $status,
            issue_key: $issue_key,
            comment_id: $comment_id,
            issue_url: $issue_url,
            message: $message
        }'
}

# --- Version Commands ---

# Get project ID from project key (needed for version-create)
get_project_id() {
    local project_key="$1"
    local response
    response=$(api_get "/rest/api/3/project/${project_key}")

    # Check for errors
    if echo "$response" | jq -e '.errorMessages' >/dev/null 2>&1; then
        echo -e "${RED}Error fetching project:${NC}" >&2
        echo "$response" | jq -r '.errorMessages[]' >&2
        return 1
    fi

    echo "$response" | jq -r '.id'
}

# Get full version info by name
get_version_info() {
    local project_key="$1"
    local version_name="$2"

    local response
    response=$(api_get "/rest/api/3/project/${project_key}/versions")

    # Check for errors
    if echo "$response" | jq -e '.errorMessages' >/dev/null 2>&1; then
        echo -e "${RED}Error fetching versions:${NC}" >&2
        echo "$response" | jq -r '.errorMessages[]' >&2
        return 1
    fi

    # Find version by name (exact match)
    local version_info
    version_info=$(echo "$response" | jq --arg name "$version_name" '.[] | select(.name == $name)')

    if [[ -z "$version_info" || "$version_info" == "null" ]]; then
        echo -e "${RED}Error: Version '${version_name}' not found in project ${project_key}${NC}" >&2
        echo -e "${YELLOW}Available versions:${NC}" >&2
        echo "$response" | jq -r '.[].name' | head -10 >&2
        return 1
    fi

    echo "$version_info"
}

cmd_version_list() {
    local project_key="${1:-}"

    if [[ -z "$project_key" ]]; then
        echo -e "${RED}Error: project_key required${NC}" >&2
        echo "Usage: jira-api.sh version-list <project_key>" >&2
        exit 1
    fi

    local response
    response=$(api_get "/rest/api/3/project/${project_key}/versions")

    # Check for errors
    if echo "$response" | jq -e '.errorMessages' >/dev/null 2>&1; then
        echo -e "${RED}Error fetching versions:${NC}" >&2
        echo "$response" | jq -r '.errorMessages[]' >&2
        exit 1
    fi

    # Return formatted version list
    echo "$response" | jq '[.[] | {
        name: .name,
        id: .id,
        released: .released,
        releaseDate: .releaseDate,
        description: (if .description then (.description | tostring | .[0:100]) else "" end)
    }]'
}

cmd_version_get() {
    local project_key="${1:-}"
    local version_name="${2:-}"

    if [[ -z "$project_key" ]] || [[ -z "$version_name" ]]; then
        echo -e "${RED}Error: project_key and version_name required${NC}" >&2
        echo "Usage: jira-api.sh version-get <project_key> <version_name>" >&2
        exit 1
    fi

    local version_info
    if ! version_info=$(get_version_info "$project_key" "$version_name"); then
        exit 1
    fi

    echo "$version_info"
}

cmd_version_create() {
    local project_key=""
    local version_name=""
    local description_file=""
    local release_date=""
    local released="false"
    local is_markdown="false"
    local dry_run="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --description)
                description_file="$2"
                shift 2
                ;;
            --release-date)
                release_date="$2"
                shift 2
                ;;
            --released)
                released="true"
                shift
                ;;
            --md)
                is_markdown="true"
                shift
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            *)
                if [[ -z "$project_key" ]]; then
                    project_key="$1"
                elif [[ -z "$version_name" ]]; then
                    version_name="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$project_key" ]] || [[ -z "$version_name" ]]; then
        echo -e "${RED}Error: project_key and version_name required${NC}" >&2
        echo "Usage: jira-api.sh version-create <project_key> <name> [options]" >&2
        echo "Options:" >&2
        echo "  --description <file|->   Description content (stdin or file)" >&2
        echo "  --release-date <date>    ISO date (yyyy-mm-dd)" >&2
        echo "  --released               Mark as released" >&2
        echo "  --md                     Input is markdown (convert to ADF)" >&2
        echo "  --dry-run                Print request body without calling API" >&2
        exit 1
    fi

    # Get project ID (required for version creation) - use fake ID for dry-run
    local project_id
    if [[ "$dry_run" == "true" ]]; then
        project_id="12345"  # Fake ID for testing
    else
        echo -e "${YELLOW}Creating version '${version_name}' in ${project_key}...${NC}" >&2
        if ! project_id=$(get_project_id "$project_key"); then
            exit 1
        fi
    fi

    # Build request body
    local body
    body=$(jq -n \
        --arg projectId "$project_id" \
        --arg name "$version_name" \
        --argjson released "$released" \
        '{
            projectId: ($projectId | tonumber),
            name: $name,
            released: $released
        }')

    # Add release date if provided
    if [[ -n "$release_date" ]]; then
        body=$(echo "$body" | jq --arg releaseDate "$release_date" '.releaseDate = $releaseDate')
    fi

    # Add description if provided
    if [[ -n "$description_file" ]]; then
        local description_content
        description_content=$(read_content "$description_file" "$is_markdown")
        body=$(echo "$body" | jq --argjson description "$description_content" '.description = $description')
    fi

    # Dry-run mode: output the request body and exit
    if [[ "$dry_run" == "true" ]]; then
        echo "$body"
        return 0
    fi

    local response
    response=$(api_post "/rest/api/3/version" "$body")

    # Check for errors
    if echo "$response" | jq -e '.errorMessages' >/dev/null 2>&1; then
        echo -e "${RED}Error creating version:${NC}" >&2
        echo "$response" | jq -r '.errorMessages[]' >&2
        if echo "$response" | jq -e '.errors' >/dev/null 2>&1; then
            echo "$response" | jq -r '.errors | to_entries[] | "\(.key): \(.value)"' >&2
        fi
        exit 1
    fi

    local version_id
    version_id=$(echo "$response" | jq -r '.id')

    local base_url
    base_url=$(normalize_base_url)
    local version_url="${base_url}/projects/${project_key}/versions/${version_id}"

    jq -n \
        --arg action "VERSION_CREATE" \
        --arg status "success" \
        --arg project "$project_key" \
        --arg version_name "$version_name" \
        --arg version_id "$version_id" \
        --arg version_url "$version_url" \
        --arg message "Version created successfully" \
        '{
            action: $action,
            status: $status,
            project: $project,
            version_name: $version_name,
            version_id: $version_id,
            version_url: $version_url,
            message: $message
        }'
}

cmd_version_update() {
    local project_key=""
    local version_name=""
    local description_file=""
    local release_date=""
    local released=""
    local is_markdown="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --description)
                description_file="$2"
                shift 2
                ;;
            --release-date)
                release_date="$2"
                shift 2
                ;;
            --released)
                released="true"
                shift
                ;;
            --md)
                is_markdown="true"
                shift
                ;;
            *)
                if [[ -z "$project_key" ]]; then
                    project_key="$1"
                elif [[ -z "$version_name" ]]; then
                    version_name="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$project_key" ]] || [[ -z "$version_name" ]]; then
        echo -e "${RED}Error: project_key and version_name required${NC}" >&2
        echo "Usage: jira-api.sh version-update <project_key> <version_name> [options]" >&2
        echo "Options:" >&2
        echo "  --description <file|->   Description content (stdin or file)" >&2
        echo "  --release-date <date>    ISO date (yyyy-mm-dd)" >&2
        echo "  --released               Mark as released" >&2
        echo "  --md                     Input is markdown (convert to ADF)" >&2
        exit 1
    fi

    echo -e "${YELLOW}Updating version '${version_name}' in ${project_key}...${NC}" >&2

    # Get version ID first
    local version_info
    if ! version_info=$(get_version_info "$project_key" "$version_name"); then
        exit 1
    fi

    local version_id
    version_id=$(echo "$version_info" | jq -r '.id')

    # Build request body - start empty
    local body='{}'

    # Add release date if provided
    if [[ -n "$release_date" ]]; then
        body=$(echo "$body" | jq --arg releaseDate "$release_date" '.releaseDate = $releaseDate')
    fi

    # Add released flag if provided
    if [[ -n "$released" ]]; then
        body=$(echo "$body" | jq --argjson released "$released" '.released = $released')
    fi

    # Add description if provided
    if [[ -n "$description_file" ]]; then
        local description_content
        description_content=$(read_content "$description_file" "$is_markdown")
        body=$(echo "$body" | jq --argjson description "$description_content" '.description = $description')
    fi

    local response
    response=$(api_put "/rest/api/3/version/${version_id}" "$body")

    # Check for errors (PUT may return empty on success)
    if [[ -n "$response" ]] && echo "$response" | jq -e '.errorMessages' >/dev/null 2>&1; then
        echo -e "${RED}Error updating version:${NC}" >&2
        echo "$response" | jq -r '.errorMessages[]' >&2
        exit 1
    fi

    local base_url
    base_url=$(normalize_base_url)
    local version_url="${base_url}/projects/${project_key}/versions/${version_id}"

    jq -n \
        --arg action "VERSION_UPDATE" \
        --arg status "success" \
        --arg project "$project_key" \
        --arg version_name "$version_name" \
        --arg version_id "$version_id" \
        --arg version_url "$version_url" \
        --arg message "Version updated successfully" \
        '{
            action: $action,
            status: $status,
            project: $project,
            version_name: $version_name,
            version_id: $version_id,
            version_url: $version_url,
            message: $message
        }'
}

# --- Field Update Commands ---

cmd_set_fix_version() {
    local issue_key="${1:-}"
    local version_name="${2:-}"

    if [[ -z "$issue_key" ]] || [[ -z "$version_name" ]]; then
        echo -e "${RED}Error: issue_key and version_name required${NC}" >&2
        echo "Usage: jira-api.sh set-fix-version <issue_key> <version_name>" >&2
        exit 1
    fi

    echo -e "${YELLOW}Setting fix version on ${issue_key} to '${version_name}'...${NC}" >&2

    # Look up version ID
    local project_key
    project_key=$(get_project_from_issue "$issue_key")

    local version_id
    if ! version_id=$(get_version_id "$project_key" "$version_name"); then
        exit 1
    fi

    echo -e "${YELLOW}Version ID: ${version_id}${NC}" >&2

    # Build minimal request body - only fix version
    local body
    body=$(jq -n --arg vid "$version_id" '{ fields: { fixVersions: [{ id: $vid }] } }')

    local response
    response=$(api_put "/rest/api/3/issue/${issue_key}" "$body")

    # Check for errors (PUT returns empty on success)
    if [[ -n "$response" ]] && echo "$response" | jq -e '.errorMessages' >/dev/null 2>&1; then
        echo -e "${RED}Error setting fix version:${NC}" >&2
        echo "$response" | jq -r '.errorMessages[]' >&2
        exit 1
    fi

    local base_url
    base_url=$(normalize_base_url)
    local issue_url="${base_url}/browse/${issue_key}"

    jq -n \
        --arg action "SET_FIX_VERSION" \
        --arg status "success" \
        --arg issue_key "$issue_key" \
        --arg version_name "$version_name" \
        --arg issue_url "$issue_url" \
        --arg message "Fix version set to ${version_name}" \
        '{
            action: $action,
            status: $status,
            issue_key: $issue_key,
            version_name: $version_name,
            issue_url: $issue_url,
            message: $message
        }'
}

cmd_link() {
    local from_issue="${1:-}"
    local link_type="${2:-}"
    local to_issue="${3:-}"

    if [[ -z "$from_issue" ]] || [[ -z "$link_type" ]] || [[ -z "$to_issue" ]]; then
        echo -e "${RED}Error: from_issue, link_type, and to_issue required${NC}" >&2
        echo "Usage: jira-api.sh link <from_issue> <link_type> <to_issue>" >&2
        echo "Link types: blocks, is-blocked-by, relates-to, duplicates, clones, is-cloned-by, causes, is-caused-by" >&2
        exit 1
    fi

    # Normalize link type to Jira's expected format
    local jira_link_type
    local link_type_lower
    link_type_lower=$(echo "$link_type" | tr '[:upper:]' '[:lower:]')
    case "$link_type_lower" in
        blocks)
            jira_link_type="Blocks"
            ;;
        is-blocked-by|is_blocked_by|blocked-by|blocked_by)
            # Jira uses "Blocks" type but with issues swapped
            jira_link_type="Blocks"
            # Swap the issues so the relationship is correct
            local temp="$from_issue"
            from_issue="$to_issue"
            to_issue="$temp"
            ;;
        relates-to|relates_to|relates|related)
            jira_link_type="Relates"
            ;;
        duplicates|duplicate)
            jira_link_type="Duplicate"
            ;;
        clones|clone)
            jira_link_type="Cloners"
            ;;
        is-cloned-by|is_cloned_by|cloned-by|cloned_by)
            # Jira uses "Cloners" type but with issues swapped
            jira_link_type="Cloners"
            # Swap the issues so the relationship is correct
            local temp="$from_issue"
            from_issue="$to_issue"
            to_issue="$temp"
            ;;
        causes|cause)
            jira_link_type="Cause"
            ;;
        is-caused-by|is_caused_by|caused-by|caused_by)
            # Jira uses "Cause" type but with issues swapped
            jira_link_type="Cause"
            # Swap the issues so the relationship is correct
            local temp="$from_issue"
            from_issue="$to_issue"
            to_issue="$temp"
            ;;
        *)
            echo -e "${RED}Error: Unknown link type: $link_type${NC}" >&2
            echo "Valid types: blocks, is-blocked-by, relates-to, duplicates, clones, is-cloned-by, causes, is-caused-by" >&2
            exit 1
            ;;
    esac

    echo -e "${YELLOW}Creating link: ${from_issue} ${link_type} ${to_issue}...${NC}" >&2

    # Build request body
    # Note: For "Blocks", outwardIssue blocks inwardIssue
    local body
    body=$(jq -n \
        --arg type "$jira_link_type" \
        --arg outward "$from_issue" \
        --arg inward "$to_issue" \
        '{
            type: { name: $type },
            outwardIssue: { key: $outward },
            inwardIssue: { key: $inward }
        }')

    local response
    response=$(api_post "/rest/api/3/issueLink" "$body")

    # Check for errors (successful POST returns 201 with empty body)
    if [[ -n "$response" ]] && echo "$response" | jq -e '.errorMessages' >/dev/null 2>&1; then
        echo -e "${RED}Error creating link:${NC}" >&2
        echo "$response" | jq -r '.errorMessages[]' >&2
        if echo "$response" | jq -e '.errors' >/dev/null 2>&1; then
            echo "$response" | jq -r '.errors | to_entries[] | "\(.key): \(.value)"' >&2
        fi
        exit 1
    fi

    local base_url
    base_url=$(normalize_base_url)

    jq -n \
        --arg action "LINK" \
        --arg status "success" \
        --arg from_issue "$from_issue" \
        --arg to_issue "$to_issue" \
        --arg link_type "$jira_link_type" \
        --arg from_url "${base_url}/browse/${from_issue}" \
        --arg to_url "${base_url}/browse/${to_issue}" \
        --arg message "Link created successfully" \
        '{
            action: $action,
            status: $status,
            from_issue: $from_issue,
            to_issue: $to_issue,
            link_type: $link_type,
            from_url: $from_url,
            to_url: $to_url,
            message: $message
        }'
}

# --- Main ---

usage() {
    cat <<EOF
Jira REST API wrapper

Usage:
  jira-api.sh get <issue_key>
  jira-api.sh create <project_key> <issue_type> <summary> <file|-> [options]
  jira-api.sh update <issue_key> <file|-> [options]
  jira-api.sh comment <issue_key> <file|-> [--md] [--fix-version <name>]
  jira-api.sh set-fix-version <issue_key> <version_name>
  jira-api.sh link <from_issue> <link_type> <to_issue>
  jira-api.sh version-list <project_key>
  jira-api.sh version-get <project_key> <version_name>
  jira-api.sh version-create <project_key> <name> [options]
  jira-api.sh version-update <project_key> <version_name> [options]

Create Options:
  --md                  Input is styled markdown (converted to ADF automatically)
  --assignee <id>       Assignee account ID (NOT email - resolve via API first)
  --component <name>    Component name (can be specified multiple times)
  --parent <key>        Parent issue key (for sub-tasks or stories under epics)
  --dry-run             Print the request body JSON instead of calling API (for testing)

Update Options:
  --md                  Input is styled markdown (converted to ADF automatically)
  --fix-version <name>  Set fix version by name (version must exist in project)

Comment Options:
  --md                  Input is styled markdown (converted to ADF automatically)
  --fix-version <name>  Set fix version (separate API call after adding comment)

Version Create/Update Options:
  --description <file|->   Description content (file path or "-" for stdin)
  --release-date <date>    Release date in ISO format (yyyy-mm-dd)
  --released               Mark version as released
  --md                     Input is markdown (convert to ADF)

Note: Use "-" as file to read from stdin.

Link Types:
  Standard (all Jira versions):
    blocks        - from_issue blocks to_issue (to_issue can't start until from_issue is done)
    is-blocked-by - from_issue is blocked by to_issue (from_issue can't start until to_issue is done)
    relates-to    - Issues are related (no dependency)
    duplicates    - from_issue is a duplicate of to_issue
    clones        - from_issue clones to_issue (from_issue is a copy of to_issue)
    is-cloned-by  - from_issue is cloned by to_issue (to_issue is a copy of from_issue)
  Extended (Jira Cloud):
    causes        - from_issue causes to_issue (from_issue directly results in to_issue)
    is-caused-by  - from_issue is caused by to_issue (to_issue directly results in from_issue)

Markdown Style Guide (with --md):
  :::context ... :::  - Context block with CONTEXT lozenge
  ## H2               - Bold + grey heading
  ### H3              - Bold + grey heading
  #### H4             - Bold + blue heading
  {status:TEXT:color} - Status lozenge (neutral/purple/blue/green/yellow/red)
  **bold**, *italic*, \`code\`, [link](url)
  - bullets, 1. numbered lists
  | tables |
  PROJ-123            - Auto inline card

Environment:
  ATLASSIAN_EMAIL      - Atlassian account email
  ATLASSIAN_API_TOKEN  - API token
  ATLASSIAN_BASE_URL   - e.g., https://company.atlassian.net

Examples:
  jira-api.sh get PROJ-123
  jira-api.sh create PROJ Story "My Issue" description.md --md
  echo 'markdown...' | jira-api.sh create PROJ Story "My Issue" - --md
  jira-api.sh update PROJ-123 description.md --md
  jira-api.sh update PROJ-123 description.md --md --fix-version "2024.01"
  jira-api.sh comment PROJ-123 release-notes.md --md --fix-version "2024.01"
  echo '{"version":1,...}' | jira-api.sh comment PROJ-123 -
  jira-api.sh set-fix-version PROJ-123 "2024.01"
  jira-api.sh link PROJ-123 blocks PROJ-456
  jira-api.sh link PROJ-123 is-blocked-by PROJ-789
  jira-api.sh link PROJ-123 relates-to PROJ-999
  jira-api.sh link PROJ-123 clones PROJ-111
  jira-api.sh link PROJ-123 causes PROJ-222   # Cloud only
  jira-api.sh version-list PROJ
  jira-api.sh version-get PROJ "2024.1.0"
  jira-api.sh version-create PROJ "2024.2.0" --release-date 2024-06-01
  echo 'Release notes...' | jira-api.sh version-create PROJ "2024.2.0" --description - --md
  jira-api.sh version-update PROJ "2024.2.0" --released --description release-notes.md --md
EOF
}

main() {
    if [[ $# -lt 1 ]]; then
        usage
        exit 1
    fi

    local cmd="$1"
    shift

    check_env

    case "$cmd" in
        get)
            cmd_get "$@"
            ;;
        create)
            cmd_create "$@"
            ;;
        update)
            cmd_update "$@"
            ;;
        comment)
            cmd_comment "$@"
            ;;
        set-fix-version)
            cmd_set_fix_version "$@"
            ;;
        link)
            cmd_link "$@"
            ;;
        version-list)
            cmd_version_list "$@"
            ;;
        version-get)
            cmd_version_get "$@"
            ;;
        version-create)
            cmd_version_create "$@"
            ;;
        version-update)
            cmd_version_update "$@"
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown command: $cmd${NC}" >&2
            usage
            exit 1
            ;;
    esac
}

main "$@"
