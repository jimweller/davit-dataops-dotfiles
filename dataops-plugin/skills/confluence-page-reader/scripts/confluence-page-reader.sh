#!/usr/bin/env bash
#
# confluence-page-reader.sh - Fetch and format Confluence pages with minimal output
#
# Uses Confluence REST API to fetch pages and converts HTML to plain text.
# Designed to produce small, readable output for LLM consumption.
#
# Usage:
#   confluence-page-reader.sh <page_id>
#   confluence-page-reader.sh <page_id> --json    # Raw JSON output
#
# Environment:
#   ATLASSIAN_EMAIL      - Atlassian account email
#   ATLASSIAN_API_TOKEN  - API token (NOT password)
#   ATLASSIAN_BASE_URL   - e.g., https://company.atlassian.net
#
# Output:
#   Structured text with key fields, truncated to ~8000 chars max

set -euo pipefail

# Colors for stderr output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# No content truncation - let the model handle summarization

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
    url="${url%/}"
    url="${url%/jira}"
    url="${url%/wiki}"
    echo "$url"
}

get_auth_header() {
    echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64
}

# --- API Functions ---

fetch_page() {
    local page_id="$1"
    local base_url
    base_url=$(normalize_base_url)

    # Request export_view for cleaner HTML (fewer Confluence-specific tags)
    # Also get version info and ancestors for context
    local endpoint="/wiki/api/v2/pages/${page_id}"
    local params="body-format=export_view&include-labels=true"

    curl -s -X GET \
        -H "Authorization: Basic $(get_auth_header)" \
        -H "Content-Type: application/json" \
        "${base_url}${endpoint}?${params}"
}

# --- HTML to Plain Text ---

# Convert Confluence HTML to readable plain text
# Preserves structure: headings, lists, code blocks, tables (basic)
html_to_text() {
    local html="$1"

    echo "$html" | \
    # Remove script/style tags (content stripped by final tag removal)
    sed -E 's/<script[^>]*>//gi' | \
    sed -E 's/<\/script>//gi' | \
    sed -E 's/<style[^>]*>//gi' | \
    sed -E 's/<\/style>//gi' | \
    # Remove HTML comments (single-line only, BSD sed compatible)
    sed -E 's/<!--[^>]*-->//g' | \
    # Convert headings to markdown-style
    sed -E 's/<h1[^>]*>/\n\n# /gi' | \
    sed -E 's/<\/h1>/\n/gi' | \
    sed -E 's/<h2[^>]*>/\n\n## /gi' | \
    sed -E 's/<\/h2>/\n/gi' | \
    sed -E 's/<h3[^>]*>/\n\n### /gi' | \
    sed -E 's/<\/h3>/\n/gi' | \
    sed -E 's/<h4[^>]*>/\n\n#### /gi' | \
    sed -E 's/<\/h4>/\n/gi' | \
    sed -E 's/<h5[^>]*>/\n\n##### /gi' | \
    sed -E 's/<\/h5>/\n/gi' | \
    sed -E 's/<h6[^>]*>/\n\n###### /gi' | \
    sed -E 's/<\/h6>/\n/gi' | \
    # Convert code blocks
    sed -E 's/<pre[^>]*>/\n```\n/gi' | \
    sed -E 's/<\/pre>/\n```\n/gi' | \
    sed -E 's/<code[^>]*>/`/gi' | \
    sed -E 's/<\/code>/`/gi' | \
    # Convert lists
    sed -E 's/<ul[^>]*>/\n/gi' | \
    sed -E 's/<\/ul>/\n/gi' | \
    sed -E 's/<ol[^>]*>/\n/gi' | \
    sed -E 's/<\/ol>/\n/gi' | \
    sed -E 's/<li[^>]*>/\n- /gi' | \
    sed -E 's/<\/li>//gi' | \
    # Convert table structure (basic)
    sed -E 's/<table[^>]*>/\n/gi' | \
    sed -E 's/<\/table>/\n/gi' | \
    sed -E 's/<tr[^>]*>/\n| /gi' | \
    sed -E 's/<\/tr>/ |/gi' | \
    sed -E 's/<th[^>]*>/ /gi' | \
    sed -E 's/<\/th>/ |/gi' | \
    sed -E 's/<td[^>]*>/ /gi' | \
    sed -E 's/<\/td>/ |/gi' | \
    # Convert line breaks and paragraphs
    sed -E 's/<br[^>]*>/\n/gi' | \
    sed -E 's/<\/p>/\n\n/gi' | \
    sed -E 's/<p[^>]*>/\n/gi' | \
    sed -E 's/<div[^>]*>/\n/gi' | \
    sed -E 's/<\/div>/\n/gi' | \
    # Convert links - extract text and URL
    sed -E 's/<a[^>]*href="([^"]*)"[^>]*>([^<]*)<\/a>/\2 (\1)/gi' | \
    # Convert emphasis
    sed -E 's/<strong[^>]*>/*/gi' | \
    sed -E 's/<\/strong>/*/gi' | \
    sed -E 's/<b[^>]*>/*/gi' | \
    sed -E 's/<\/b>/*/gi' | \
    sed -E 's/<em[^>]*>/_/gi' | \
    sed -E 's/<\/em>/_/gi' | \
    sed -E 's/<i[^>]*>/_/gi' | \
    sed -E 's/<\/i>/_/gi' | \
    # Remove all remaining HTML tags
    sed -E 's/<[^>]+>//g' | \
    # Decode common HTML entities
    sed 's/&nbsp;/ /g' | \
    sed 's/&amp;/\&/g' | \
    sed 's/&lt;/</g' | \
    sed 's/&gt;/>/g' | \
    sed 's/&quot;/"/g' | \
    sed "s/&#39;/'/g" | \
    sed 's/&mdash;/—/g' | \
    sed 's/&ndash;/–/g' | \
    sed 's/&bull;/•/g' | \
    sed 's/&copy;/©/g' | \
    sed 's/&reg;/®/g' | \
    sed 's/&#[0-9]*;//g' | \
    # Remove CSS artifacts (Confluence inline styles that leak through)
    sed '/^\[data-colorid=/d' | \
    sed '/^html\[data-color-mode/d' | \
    sed '/{color:#/d' | \
    # Collapse multiple blank lines
    sed '/^$/N;/^\n$/d' | \
    # Trim leading/trailing whitespace per line
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
    # Remove lines that are just whitespace
    grep -v '^[[:space:]]*$' || true
}

# --- Formatting ---

format_page() {
    local json="$1"
    local base_url
    base_url=$(normalize_base_url)

    # Check for errors
    if echo "$json" | jq -e '.errors' >/dev/null 2>&1; then
        echo "ERROR: $(echo "$json" | jq -r '.errors[0].title // "Unknown error"')"
        return 1
    fi

    # Check if page exists
    if echo "$json" | jq -e '.id' >/dev/null 2>&1; then
        : # Page found
    else
        echo "ERROR: Page not found or invalid response"
        return 1
    fi

    local id title space_id status
    local created_at updated_at
    local author_name
    local body_html body_text
    local labels_text

    id=$(echo "$json" | jq -r '.id')
    title=$(echo "$json" | jq -r '.title // "Untitled"')
    space_id=$(echo "$json" | jq -r '.spaceId // "Unknown"')
    status=$(echo "$json" | jq -r '.status // "Unknown"')

    # Version info
    created_at=$(echo "$json" | jq -r '.createdAt // ""' | cut -d'T' -f1)
    updated_at=$(echo "$json" | jq -r '.version.createdAt // ""' | cut -d'T' -f1)
    author_name=$(echo "$json" | jq -r '.version.authorId // "Unknown"')

    # Labels
    labels_text=$(echo "$json" | jq -r '[.labels.results[]?.name] | join(", ")' 2>/dev/null || echo "")
    [[ -z "$labels_text" ]] && labels_text="None"

    # Body content - convert HTML to text
    body_html=$(echo "$json" | jq -r '.body.export_view.value // ""')

    if [[ -n "$body_html" ]]; then
        body_text=$(html_to_text "$body_html")
    else
        body_text="[No content]"
    fi


    # Build URL
    local page_url="${base_url}/wiki/spaces/${space_id}/pages/${id}"

    # Output structured text
    cat <<EOF
# ${title}

**URL**: ${page_url}
**Page ID**: ${id}
**Space**: ${space_id}
**Status**: ${status}
**Created**: ${created_at}
**Updated**: ${updated_at}
**Labels**: ${labels_text}

---

${body_text}
EOF
}

# --- Main ---

usage() {
    cat <<EOF
Confluence Page Reader - Fetch and format pages with minimal output

Usage:
  confluence-page-reader.sh <page_id>
  confluence-page-reader.sh <page_id> --json    # Raw JSON output

Environment:
  ATLASSIAN_EMAIL      - Atlassian account email
  ATLASSIAN_API_TOKEN  - API token (NOT password)
  ATLASSIAN_BASE_URL   - e.g., https://company.atlassian.net

Examples:
  confluence-page-reader.sh 12345678
  confluence-page-reader.sh 12345678 --json
EOF
}

main() {
    local page_id=""
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
                if [[ -z "$page_id" ]]; then
                    page_id="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$page_id" ]]; then
        echo -e "${RED}Error: page_id required${NC}" >&2
        usage >&2
        exit 1
    fi

    check_env

    echo -e "${YELLOW}Fetching page ${page_id}...${NC}" >&2

    local response
    response=$(fetch_page "$page_id")

    # Check for HTTP/API errors
    if echo "$response" | jq -e '.statusCode' >/dev/null 2>&1; then
        local status_code
        status_code=$(echo "$response" | jq -r '.statusCode')
        if [[ "$status_code" != "null" ]] && [[ "$status_code" -ge 400 ]]; then
            echo -e "${RED}Error: HTTP ${status_code}${NC}" >&2
            echo "$response" | jq -r '.message // "Unknown error"' >&2
            exit 1
        fi
    fi

    if [[ "$output_json" == "true" ]]; then
        echo "$response" | jq '.'
    else
        format_page "$response"
    fi
}

main "$@"
