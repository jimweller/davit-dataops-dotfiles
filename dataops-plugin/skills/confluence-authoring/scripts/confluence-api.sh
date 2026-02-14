#!/usr/bin/env bash
#
# confluence-api.sh - Confluence REST API wrapper
#
# Usage:
#   confluence-api.sh get <page_id> [--adf]
#   confluence-api.sh download <page_id> <output_file>   # Download ADF to file (for large page edits)
#   confluence-api.sh validate <adf_file|->             # Validate ADF structure
#   confluence-api.sh create <space_id> <title> <file|-> [--md] [--parent <page_id>] [--publish]
#   confluence-api.sh update <page_id> <file|-> [--md] [--title <new_title>] [--publish]
#   confluence-api.sh delete <page_id>
#
# Options:
#   --md    Input is styled markdown (converted to ADF automatically)
#           Without --md, input is expected to be raw ADF JSON
#
# Note: Pages are created/updated as DRAFTS by default (human-in-the-loop).
#       Use --publish to publish immediately (not recommended).
#       Use "-" as file to read from stdin (avoids temp files).
#
# Markdown Style Guide (with --md):
#   :::metadata owner="@Name" date="YYYY-MM-DD" :::  - Metadata table
#   :::toc maxLevel=2 :::                            - Table of contents
#   :::callout title="NOTE" color=blue ... :::       - Callout box
#   # H1              - Bold + grey
#   ## H2             - Bold + grey
#   ##! H2            - Bold + blue (action sections)
#   ### H3            - Bold + green
#   #### H4           - Bold + grey
#   ##### H5          - Grey only
#   {status:TEXT:color} - Status lozenge
#   ---               - Horizontal rule
#   {pageCard:url}    - Inline card
#
# Environment:
#   ATLASSIAN_EMAIL      - Atlassian account email
#   ATLASSIAN_API_TOKEN  - API token (NOT password)
#   ATLASSIAN_BASE_URL   - e.g., https://company.atlassian.net
#
# Examples:
#   confluence-api.sh get 123456789 --adf
#   confluence-api.sh download 123456789 ./page-content.json
#   confluence-api.sh validate ./page-content.json
#   confluence-api.sh create 2643820699 "My Page" content.md --md
#   echo 'markdown...' | confluence-api.sh create 2643820699 "My Page" - --md
#   confluence-api.sh update 123456789 content.md --md --title "New Title"
#   confluence-api.sh delete 123456789

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

api_delete() {
    local endpoint="$1"
    local base_url
    base_url=$(normalize_base_url)
    local http_code

    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
        -H "Authorization: Basic $(get_auth_header)" \
        "${base_url}${endpoint}")

    echo "$http_code"
}

# --- Helper Functions ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

    if [[ "$is_markdown" == "true" ]]; then
        local converter="${SCRIPT_DIR}/confluence-md-to-adf.js"
        if [[ ! -x "$converter" ]]; then
            echo -e "${RED}Error: Markdown converter not found: $converter${NC}" >&2
            exit 1
        fi
        echo "$content" | "$converter"
    else
        echo "$content"
    fi
}

# --- Commands ---

cmd_get() {
    local page_id=""
    local format="storage"  # Default to storage format

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --adf)
                format="atlas_doc_format"
                shift
                ;;
            --storage)
                format="storage"
                shift
                ;;
            *)
                if [[ -z "$page_id" ]]; then
                    page_id="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$page_id" ]]; then
        echo -e "${RED}Error: page_id required${NC}" >&2
        echo "Usage: confluence-api.sh get <page_id> [--adf|--storage]" >&2
        exit 1
    fi

    local endpoint="/wiki/api/v2/pages/${page_id}?body-format=${format}"
    local response
    response=$(api_get "$endpoint")

    # Check for errors
    if echo "$response" | jq -e '.errors' >/dev/null 2>&1; then
        echo -e "${RED}Error fetching page:${NC}" >&2
        echo "$response" | jq -r '.errors[].message // .message // .' >&2
        exit 1
    fi

    echo "$response"
}

cmd_download() {
    local page_id="$1"
    local output_file="$2"

    if [[ -z "$page_id" ]] || [[ -z "$output_file" ]]; then
        echo -e "${RED}Error: page_id and output_file required${NC}" >&2
        echo "Usage: confluence-api.sh download <page_id> <output_file>" >&2
        exit 1
    fi

    echo -e "${YELLOW}Downloading page ADF to ${output_file}...${NC}" >&2

    local endpoint="/wiki/api/v2/pages/${page_id}?body-format=atlas_doc_format"
    local response
    response=$(api_get "$endpoint")

    # Check for errors
    if echo "$response" | jq -e '.errors' >/dev/null 2>&1; then
        echo -e "${RED}Error fetching page:${NC}" >&2
        echo "$response" | jq -r '.errors[].message // .message // .' >&2
        exit 1
    fi

    # Extract just the ADF body content
    local adf_body
    adf_body=$(echo "$response" | jq -r '.body.atlas_doc_format.value // empty')

    if [[ -z "$adf_body" ]]; then
        echo -e "${RED}Error: No ADF body found in response${NC}" >&2
        exit 1
    fi

    # Parse and pretty-print the ADF JSON to the file
    echo "$adf_body" | jq '.' > "$output_file"

    # Get page metadata for output
    local title version
    title=$(echo "$response" | jq -r '.title')
    version=$(echo "$response" | jq -r '.version.number')
    local file_size
    file_size=$(wc -c < "$output_file" | tr -d ' ')

    echo -e "${GREEN}Downloaded:${NC} ${title} (v${version})" >&2
    echo -e "${GREEN}File:${NC} ${output_file} (${file_size} bytes)" >&2

    jq -n \
        --arg action "DOWNLOAD" \
        --arg status "success" \
        --arg page_id "$page_id" \
        --arg title "$title" \
        --argjson version "$version" \
        --arg output_file "$output_file" \
        --argjson file_size "$file_size" \
        '{
            action: $action,
            status: $status,
            page_id: $page_id,
            title: $title,
            version: $version,
            output_file: $output_file,
            file_size: $file_size,
            message: "Page ADF downloaded - edit and use update command to apply changes"
        }'
}

cmd_validate() {
    local adf_file="$1"

    if [[ -z "$adf_file" ]]; then
        echo -e "${RED}Error: adf_file required${NC}" >&2
        echo "Usage: confluence-api.sh validate <adf_file|->" >&2
        exit 1
    fi

    # Read ADF content from file or stdin
    local adf_content
    if [[ "$adf_file" == "-" ]]; then
        adf_content=$(cat)
    elif [[ -f "$adf_file" ]]; then
        adf_content=$(cat "$adf_file")
    else
        echo -e "${RED}Error: ADF file not found: $adf_file${NC}" >&2
        exit 1
    fi

    local errors=()

    # Check 1: Valid JSON
    if ! echo "$adf_content" | jq empty 2>/dev/null; then
        errors+=("Invalid JSON syntax")
    else
        # Check 2: Required root fields
        local version type has_content
        version=$(echo "$adf_content" | jq -r '.version // empty')
        type=$(echo "$adf_content" | jq -r '.type // empty')
        has_content=$(echo "$adf_content" | jq -e '.content' 2>/dev/null && echo "yes" || echo "no")

        [[ "$version" != "1" ]] && errors+=("Missing or invalid 'version' (expected 1, got: ${version:-null})")
        [[ "$type" != "doc" ]] && errors+=("Missing or invalid 'type' (expected 'doc', got: ${type:-null})")
        [[ "$has_content" != "yes" ]] && errors+=("Missing 'content' array")

        # Check 3: Content array is actually an array
        if [[ "$has_content" == "yes" ]]; then
            local content_type
            content_type=$(echo "$adf_content" | jq -r '.content | type')
            [[ "$content_type" != "array" ]] && errors+=("'content' must be an array (got: $content_type)")
        fi

        # Check 4: Common node type validation
        local invalid_types
        invalid_types=$(echo "$adf_content" | jq -r '
            [.. | objects | select(.type != null) | .type] | unique |
            map(select(. as $t |
                ["doc","paragraph","heading","text","bulletList","orderedList","listItem",
                 "table","tableRow","tableCell","tableHeader","codeBlock","blockquote",
                 "rule","hardBreak","panel","expand","status","emoji","mention","date",
                 "inlineCard","mediaGroup","mediaSingle","media","layoutSection","layoutColumn",
                 "taskList","taskItem","decisionList","decisionItem","extension","bodiedExtension",
                 "inlineExtension","placeholder","unsupportedBlock","unsupportedInline"] |
                index($t) == null
            )) | join(", ")
        ' 2>/dev/null || echo "")

        [[ -n "$invalid_types" ]] && errors+=("Unknown node types: $invalid_types")

        # Check 5: Status nodes have localId
        local status_without_localid
        status_without_localid=$(echo "$adf_content" | jq '[.. | objects | select(.type == "status" and (.attrs.localId == null or .attrs.localId == ""))] | length' 2>/dev/null || echo "0")
        [[ "$status_without_localid" -gt 0 ]] && errors+=("${status_without_localid} status node(s) missing localId")
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        echo -e "${RED}Validation failed:${NC}" >&2
        for err in "${errors[@]}"; do
            echo -e "  - $err" >&2
        done

        jq -n \
            --arg status "error" \
            --argjson errors "$(printf '%s\n' "${errors[@]}" | jq -R . | jq -s .)" \
            '{
                action: "VALIDATE",
                status: $status,
                valid: false,
                errors: $errors
            }'
        exit 1
    else
        local node_count
        node_count=$(echo "$adf_content" | jq '[.. | objects | select(.type != null)] | length' 2>/dev/null || echo "0")

        echo -e "${GREEN}Validation passed${NC} (${node_count} nodes)" >&2

        jq -n \
            --argjson node_count "$node_count" \
            '{
                action: "VALIDATE",
                status: "success",
                valid: true,
                node_count: $node_count,
                message: "ADF structure is valid"
            }'
    fi
}

cmd_create() {
    local space_id=""
    local title=""
    local content_file=""
    local parent_id=""
    local status="draft"  # Default to draft for human-in-the-loop
    local is_markdown="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --parent)
                parent_id="$2"
                shift 2
                ;;
            --publish)
                status="current"
                shift
                ;;
            --md)
                is_markdown="true"
                shift
                ;;
            *)
                if [[ -z "$space_id" ]]; then
                    space_id="$1"
                elif [[ -z "$title" ]]; then
                    title="$1"
                elif [[ -z "$content_file" ]]; then
                    content_file="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$space_id" ]] || [[ -z "$title" ]] || [[ -z "$content_file" ]]; then
        echo -e "${RED}Error: space_id, title, and content_file required${NC}" >&2
        echo "Usage: confluence-api.sh create <space_id> <title> <file|-> [--md] [--parent <page_id>] [--publish]" >&2
        exit 1
    fi

    echo -e "${YELLOW}Creating page as ${status}...${NC}" >&2

    # Read content (convert from markdown if --md flag)
    local adf_content
    adf_content=$(read_content "$content_file" "$is_markdown")

    # Build request body
    local body
    if [[ -n "$parent_id" ]]; then
        body=$(jq -n \
            --arg spaceId "$space_id" \
            --arg status "$status" \
            --arg title "$title" \
            --arg parentId "$parent_id" \
            --arg adf "$adf_content" \
            '{
                spaceId: $spaceId,
                status: $status,
                title: $title,
                parentId: $parentId,
                body: {
                    representation: "atlas_doc_format",
                    value: $adf
                }
            }')
    else
        body=$(jq -n \
            --arg spaceId "$space_id" \
            --arg status "$status" \
            --arg title "$title" \
            --arg adf "$adf_content" \
            '{
                spaceId: $spaceId,
                status: $status,
                title: $title,
                body: {
                    representation: "atlas_doc_format",
                    value: $adf
                }
            }')
    fi

    local response
    response=$(api_post "/wiki/api/v2/pages" "$body")

    # Check for errors
    if echo "$response" | jq -e '.errors' >/dev/null 2>&1; then
        echo -e "${RED}Error creating page:${NC}" >&2
        echo "$response" | jq -r '.errors[].message // .message // .' >&2
        exit 1
    fi

    # Output success info
    local page_id page_url version
    page_id=$(echo "$response" | jq -r '.id')
    version=$(echo "$response" | jq -r '.version.number')

    local base_url
    base_url=$(normalize_base_url)

    # For drafts, use the edit URL with draftShareId for browser access
    if [[ "$status" == "draft" ]]; then
        local edit_link
        edit_link=$(echo "$response" | jq -r '._links.edituiv2 // ._links.editui // empty')
        if [[ -n "$edit_link" ]]; then
            page_url="${base_url}/wiki${edit_link}"
        else
            # Fallback: construct edit-v2 URL (may not work without draftShareId)
            local space_key
            space_key=$(echo "$response" | jq -r '._links.webui' | sed -n 's|.*/spaces/\([^/]*\)/.*|\1|p')
            page_url="${base_url}/wiki/spaces/${space_key}/pages/edit-v2/${page_id}"
        fi
    else
        # For published pages, use standard view URL
        local webui_link
        webui_link=$(echo "$response" | jq -r '._links.webui // empty')
        if [[ -n "$webui_link" ]]; then
            page_url="${base_url}/wiki${webui_link}"
        else
            page_url="${base_url}/wiki/spaces/$(echo "$response" | jq -r '.spaceId')/pages/${page_id}"
        fi
    fi

    local status_msg="Page created as draft - review and publish at the link below"
    [[ "$status" == "current" ]] && status_msg="Page created and published"

    jq -n \
        --arg action "CREATE" \
        --arg result "success" \
        --arg page_id "$page_id" \
        --arg page_url "$page_url" \
        --argjson version "$version" \
        --arg page_status "$status" \
        --arg message "$status_msg" \
        '{
            action: $action,
            status: $result,
            page_id: $page_id,
            page_url: $page_url,
            version: $version,
            page_status: $page_status,
            message: $message
        }'
}

cmd_update() {
    local page_id=""
    local content_file=""
    local new_title=""
    local status="draft"  # Default to draft for human-in-the-loop
    local is_markdown="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --title)
                new_title="$2"
                shift 2
                ;;
            --publish)
                status="current"
                shift
                ;;
            --md)
                is_markdown="true"
                shift
                ;;
            *)
                if [[ -z "$page_id" ]]; then
                    page_id="$1"
                elif [[ -z "$content_file" ]]; then
                    content_file="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$page_id" ]] || [[ -z "$content_file" ]]; then
        echo -e "${RED}Error: page_id and content_file required${NC}" >&2
        echo "Usage: confluence-api.sh update <page_id> <file|-> [--md] [--title <new_title>] [--publish]" >&2
        exit 1
    fi

    # Read content (convert from markdown if --md flag) - do this first before any API calls
    local adf_content
    adf_content=$(read_content "$content_file" "$is_markdown")

    # Get current page to get version and title
    echo -e "${YELLOW}Fetching current page version...${NC}" >&2
    local current
    current=$(api_get "/wiki/api/v2/pages/${page_id}")

    if echo "$current" | jq -e '.errors' >/dev/null 2>&1; then
        echo -e "${RED}Error fetching page:${NC}" >&2
        echo "$current" | jq -r '.errors[].message // .message // .' >&2
        exit 1
    fi

    local current_version current_title current_status
    current_version=$(echo "$current" | jq -r '.version.number')
    current_title=$(echo "$current" | jq -r '.title')
    current_status=$(echo "$current" | jq -r '.status')

    # Draft pages don't support version increments - keep at version 1
    local next_version
    if [[ "$current_status" == "draft" ]]; then
        next_version=1
    else
        next_version=$((current_version + 1))
    fi
    local title="${new_title:-$current_title}"

    # Build request body
    local body
    body=$(jq -n \
        --arg id "$page_id" \
        --arg status "$status" \
        --arg title "$title" \
        --argjson version "$next_version" \
        --arg adf "$adf_content" \
        '{
            id: $id,
            status: $status,
            title: $title,
            version: {
                number: $version,
                message: "Updated via confluence-api.sh"
            },
            body: {
                representation: "atlas_doc_format",
                value: $adf
            }
        }')

    echo -e "${YELLOW}Updating page (v${current_version} -> v${next_version})...${NC}" >&2

    local response
    response=$(api_put "/wiki/api/v2/pages/${page_id}" "$body")

    # Check for errors
    if echo "$response" | jq -e '.errors' >/dev/null 2>&1; then
        echo -e "${RED}Error updating page:${NC}" >&2
        echo "$response" | jq -r '.errors[].message // .message // .' >&2
        exit 1
    fi

    # Output success info
    local new_version page_url
    new_version=$(echo "$response" | jq -r '.version.number')

    local base_url
    base_url=$(normalize_base_url)

    # For drafts, use the edit URL with draftShareId for browser access
    if [[ "$status" == "draft" ]]; then
        local edit_link
        edit_link=$(echo "$response" | jq -r '._links.edituiv2 // ._links.editui // empty')
        if [[ -n "$edit_link" ]]; then
            page_url="${base_url}/wiki${edit_link}"
        else
            # Fallback: construct edit-v2 URL
            local space_key
            space_key=$(echo "$response" | jq -r '._links.webui' | sed -n 's|.*/spaces/\([^/]*\)/.*|\1|p')
            page_url="${base_url}/wiki/spaces/${space_key}/pages/edit-v2/${page_id}"
        fi
    else
        # For published pages, use standard view URL
        local webui_link
        webui_link=$(echo "$response" | jq -r '._links.webui // empty')
        if [[ -n "$webui_link" ]]; then
            page_url="${base_url}/wiki${webui_link}"
        else
            local space_key
            space_key=$(echo "$response" | jq -r '._links.webui' | sed 's|/spaces/\([^/]*\)/.*|\1|')
            page_url="${base_url}/wiki/spaces/${space_key}/pages/${page_id}"
        fi
    fi

    local status_msg="Page updated as draft - review and publish at the link below"
    [[ "$status" == "current" ]] && status_msg="Page updated and published"

    jq -n \
        --arg action "UPDATE" \
        --arg result "success" \
        --arg page_id "$page_id" \
        --arg page_url "$page_url" \
        --argjson version "$new_version" \
        --arg page_status "$status" \
        --arg message "$status_msg" \
        '{
            action: $action,
            status: $result,
            page_id: $page_id,
            page_url: $page_url,
            version: $version,
            page_status: $page_status,
            message: $message
        }'
}

cmd_delete() {
    local page_id="$1"

    if [[ -z "$page_id" ]]; then
        echo -e "${RED}Error: page_id required${NC}" >&2
        echo "Usage: confluence-api.sh delete <page_id>" >&2
        exit 1
    fi

    # First check if it's a draft (drafts need different handling)
    local page_info
    page_info=$(api_get "/wiki/api/v2/pages/${page_id}")
    local page_status
    page_status=$(echo "$page_info" | jq -r '.status // "unknown"')

    local http_code
    if [[ "$page_status" == "draft" ]]; then
        # For drafts, use the content API with status=draft
        echo -e "${YELLOW}Deleting draft page...${NC}" >&2
        http_code=$(api_delete "/wiki/rest/api/content/${page_id}?status=draft")
    else
        # For published pages, use v2 API
        echo -e "${YELLOW}Deleting page...${NC}" >&2
        http_code=$(api_delete "/wiki/api/v2/pages/${page_id}")
    fi

    if [[ "$http_code" == "204" ]]; then
        jq -n \
            --arg action "DELETE" \
            --arg status "success" \
            --arg page_id "$page_id" \
            '{
                action: $action,
                status: $status,
                page_id: $page_id,
                message: "Page deleted successfully"
            }'
    else
        echo -e "${RED}Error deleting page: HTTP $http_code${NC}" >&2
        jq -n \
            --arg action "DELETE" \
            --arg status "error" \
            --arg page_id "$page_id" \
            --arg http_code "$http_code" \
            '{
                action: $action,
                status: $status,
                page_id: $page_id,
                message: ("Delete failed with HTTP " + $http_code)
            }'
        exit 1
    fi
}

# --- Main ---

usage() {
    cat <<EOF
Confluence REST API wrapper

Usage:
  confluence-api.sh get <page_id> [--adf|--storage]
  confluence-api.sh download <page_id> <output_file>   # Download ADF to file (for large page edits)
  confluence-api.sh validate <adf_file|->             # Validate ADF structure
  confluence-api.sh create <space_id> <title> <adf_file|--> [--parent <page_id>] [--publish]
  confluence-api.sh update <page_id> <adf_file|--> [--title <new_title>] [--publish]
  confluence-api.sh delete <page_id>

Note: Pages are created/updated as DRAFTS by default (human-in-the-loop).
      Use --publish to publish immediately (not recommended).
      Use "-" as adf_file to read ADF JSON from stdin.

For large page edits (to avoid context limits):
  1. Download: confluence-api.sh download <page_id> ./page.json
  2. Edit the file with an editor agent
  3. Validate: confluence-api.sh validate ./page.json
  4. Update: cat ./page.json | confluence-api.sh update <page_id> -

Environment:
  ATLASSIAN_EMAIL      - Atlassian account email
  ATLASSIAN_API_TOKEN  - API token
  ATLASSIAN_BASE_URL   - e.g., https://company.atlassian.net

Examples:
  confluence-api.sh get 123456789 --adf
  confluence-api.sh download 123456789 ./content.json
  confluence-api.sh validate ./content.json
  confluence-api.sh create 2643820699 "My Page" /tmp/content.json
  echo '{"version":1,...}' | confluence-api.sh create 2643820699 "My Page" -
  confluence-api.sh update 123456789 /tmp/content.json --title "New Title"
  confluence-api.sh delete 123456789
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
        download)
            cmd_download "$@"
            ;;
        validate)
            cmd_validate "$@"
            ;;
        create)
            cmd_create "$@"
            ;;
        update)
            cmd_update "$@"
            ;;
        delete)
            cmd_delete "$@"
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
