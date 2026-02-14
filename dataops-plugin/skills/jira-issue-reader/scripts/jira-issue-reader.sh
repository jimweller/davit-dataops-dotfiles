#!/usr/bin/env bash
#
# jira-issue-reader.sh - Fetch and format Jira issues with minimal output
#
# Uses Jira search API with field selection to minimize payload size.
# Converts ADF to plain text and outputs structured markdown.
#
# Usage:
#   jira-issue-reader.sh <issue_key>
#   jira-issue-reader.sh <issue_key> --json    # Raw JSON output
#
# Environment:
#   ATLASSIAN_EMAIL      - Atlassian account email
#   ATLASSIAN_API_TOKEN  - API token (NOT password)
#   ATLASSIAN_BASE_URL   - e.g., https://company.atlassian.net
#
# Output:
#   Structured markdown with key fields, ~500-1000 tokens max

set -euo pipefail

# Colors for stderr output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

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

# Fetch issue using search API with field selection
# Search API respects fields param (unlike single issue endpoint)
fetch_issue() {
    local issue_key="$1"
    local base_url
    base_url=$(normalize_base_url)

    # Fields we want (minimal set for context)
    local fields="summary,status,assignee,reporter,priority,labels,parent,issuelinks,description,comment,created,updated,issuetype,project"

    # Use new search/jql endpoint (migrated from /rest/api/3/search)
    # See: https://developer.atlassian.com/changelog/#CHANGE-2046
    # expand=renderedFields gives us HTML instead of ADF where available
    local endpoint="/rest/api/3/search/jql"
    local jql="key=$issue_key"

    curl -s -X GET \
        -H "Authorization: Basic $(get_auth_header)" \
        -H "Content-Type: application/json" \
        "${base_url}${endpoint}?jql=$(printf '%s' "$jql" | jq -sRr @uri)&fields=${fields}&expand=renderedFields&maxResults=1"
}

# --- ADF to Plain Text ---

# Extract plain text from ADF recursively
adf_to_text() {
    local adf="$1"

    # Use jq to recursively extract text nodes
    echo "$adf" | jq -r '
        def extract_text:
            if type == "object" then
                if .type == "text" then
                    .text // ""
                elif .type == "hardBreak" then
                    "\n"
                elif .type == "paragraph" then
                    ([.content[]? | extract_text] | join("")) + "\n"
                elif .type == "bulletList" or .type == "orderedList" then
                    [.content[]? | extract_text] | join("")
                elif .type == "listItem" then
                    "- " + ([.content[]? | extract_text] | join(""))
                elif .type == "heading" then
                    ([.content[]? | extract_text] | join("")) + "\n"
                elif .type == "codeBlock" then
                    "```\n" + ([.content[]? | extract_text] | join("")) + "\n```\n"
                elif .type == "blockquote" then
                    "> " + ([.content[]? | extract_text] | join(""))
                elif .type == "table" then
                    [.content[]? | extract_text] | join("")
                elif .type == "tableRow" then
                    ([.content[]? | extract_text] | join(" | ")) + "\n"
                elif .type == "tableCell" or .type == "tableHeader" then
                    [.content[]? | extract_text] | join("")
                elif .type == "mention" then
                    "@" + (.attrs.text // .attrs.id // "user")
                elif .type == "inlineCard" then
                    .attrs.url // "[link]"
                else
                    [.content[]? | extract_text] | join("")
                end
            elif type == "array" then
                [.[] | extract_text] | join("")
            else
                ""
            end;
        extract_text
    ' 2>/dev/null || echo "[Unable to parse ADF]"
}

# Strip HTML tags for plain text (for renderedFields fallback)
html_to_text() {
    local html="$1"
    echo "$html" | sed -e 's/<br[^>]*>/\n/gi' -e 's/<\/p>/\n/gi' -e 's/<\/li>/\n/gi' -e 's/<[^>]*>//g' | sed 's/&nbsp;/ /g; s/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g'
}

# --- Formatting ---

format_issue() {
    local json="$1"
    local base_url
    base_url=$(normalize_base_url)

    # Check if we got results (new API uses isLast + issues array, not total)
    local issue_count
    issue_count=$(echo "$json" | jq -r '.issues | length')

    if [[ "$issue_count" == "0" ]]; then
        echo "ERROR: Issue not found"
        return 1
    fi

    # Extract issue from search results
    local issue
    issue=$(echo "$json" | jq '.issues[0]')

    local key summary status assignee reporter priority labels parent
    local issue_type project created updated description_text

    key=$(echo "$issue" | jq -r '.key')
    summary=$(echo "$issue" | jq -r '.fields.summary // "No summary"')
    status=$(echo "$issue" | jq -r '.fields.status.name // "Unknown"')
    issue_type=$(echo "$issue" | jq -r '.fields.issuetype.name // "Unknown"')
    project=$(echo "$issue" | jq -r '.fields.project.key // "Unknown"')
    assignee=$(echo "$issue" | jq -r '.fields.assignee.displayName // "Unassigned"')
    reporter=$(echo "$issue" | jq -r '.fields.reporter.displayName // "Unknown"')
    priority=$(echo "$issue" | jq -r '.fields.priority.name // "None"')
    created=$(echo "$issue" | jq -r '.fields.created // ""' | cut -d'T' -f1)
    updated=$(echo "$issue" | jq -r '.fields.updated // ""' | cut -d'T' -f1)

    # Labels as comma-separated
    labels=$(echo "$issue" | jq -r '.fields.labels // [] | join(", ")' | head -c 200)
    [[ -z "$labels" ]] && labels="None"

    # Parent/Epic
    parent=$(echo "$issue" | jq -r '.fields.parent.key // "None"')
    local parent_summary=""
    if [[ "$parent" != "None" ]]; then
        parent_summary=$(echo "$issue" | jq -r '.fields.parent.fields.summary // ""')
        [[ -n "$parent_summary" ]] && parent="$parent ($parent_summary)"
    fi

    # Description - try renderedFields first (HTML), fall back to ADF
    local rendered_desc
    rendered_desc=$(echo "$json" | jq -r '.issues[0].renderedFields.description // empty')

    if [[ -n "$rendered_desc" ]] && [[ "$rendered_desc" != "null" ]]; then
        description_text=$(html_to_text "$rendered_desc")
    else
        local adf_desc
        adf_desc=$(echo "$issue" | jq '.fields.description // null')
        if [[ "$adf_desc" != "null" ]]; then
            description_text=$(adf_to_text "$adf_desc")
        else
            description_text="No description"
        fi
    fi

    # Truncate description to ~500 chars
    if [[ ${#description_text} -gt 500 ]]; then
        description_text="${description_text:0:500}..."
    fi

    # Issue links - extract key info
    local linked_issues
    linked_issues=$(echo "$issue" | jq -r '
        [.fields.issuelinks[]? |
            if .outwardIssue then
                .type.outward + " " + .outwardIssue.key
            elif .inwardIssue then
                .type.inward + " " + .inwardIssue.key
            else empty end
        ] | join(", ")
    ')
    [[ -z "$linked_issues" ]] && linked_issues="None"

    # Comments - count and content
    local comment_count
    comment_count=$(echo "$issue" | jq -r '.fields.comment.total // 0')

    # Output structured markdown
    cat <<EOF
## ${key}: ${summary}

**URL**: ${base_url}/browse/${key}
**Type**: ${issue_type} | **Status**: ${status} | **Priority**: ${priority}
**Project**: ${project}
**Assignee**: ${assignee} | **Reporter**: ${reporter}
**Created**: ${created} | **Updated**: ${updated}
**Labels**: ${labels}
**Parent/Epic**: ${parent}
**Linked Issues**: ${linked_issues}

### Description
${description_text}

### Comments (${comment_count} total)
EOF

    if [[ "$comment_count" -gt 0 ]]; then
        # Get rendered comments (HTML) from renderedFields, or fall back to ADF
        local rendered_comments
        rendered_comments=$(echo "$json" | jq -r '.issues[0].renderedFields.comment.comments // empty')

        # Show last 10 comments (most recent at bottom)
        local comments_to_show=10
        local start_idx=$((comment_count > comments_to_show ? comment_count - comments_to_show : 0))

        if [[ "$start_idx" -gt 0 ]]; then
            echo "_Showing last ${comments_to_show} of ${comment_count} comments..._"
            echo ""
        fi

        # Process each comment
        echo "$issue" | jq -r --argjson start "$start_idx" '
            .fields.comment.comments[$start:] | to_entries[] |
            "COMMENT_IDX:\(.key)|\(.value.id)|\(.value.author.displayName // "Unknown")|\(.value.created // "")"
        ' | while IFS='|' read -r idx comment_id author created_raw; do
            local created_date="${created_raw:0:10}"  # YYYY-MM-DD
            local actual_idx=$((start_idx + ${idx#COMMENT_IDX:}))

            echo "**[${comment_id}]** ${created_date} - **${author}**:"

            # Try rendered HTML first, fall back to ADF
            local comment_body=""
            if [[ -n "$rendered_comments" ]] && [[ "$rendered_comments" != "null" ]]; then
                comment_body=$(echo "$rendered_comments" | jq -r ".[$actual_idx].body // empty")
                if [[ -n "$comment_body" ]]; then
                    comment_body=$(html_to_text "$comment_body")
                fi
            fi

            if [[ -z "$comment_body" ]]; then
                # Fall back to ADF parsing
                local adf_body
                adf_body=$(echo "$issue" | jq ".fields.comment.comments[$actual_idx].body // null")
                if [[ "$adf_body" != "null" ]]; then
                    comment_body=$(adf_to_text "$adf_body")
                fi
            fi

            # Truncate long comments
            if [[ ${#comment_body} -gt 500 ]]; then
                comment_body="${comment_body:0:500}..."
            fi

            # Clean up whitespace and output
            comment_body=$(echo "$comment_body" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -c 600)
            echo "$comment_body"
            echo ""
        done
    else
        echo "_No comments_"
    fi
}

# --- Main ---

usage() {
    cat <<EOF
Jira Issue Reader - Fetch and format Jira issues with minimal output

Usage:
  jira-issue-reader.sh <issue_key>
  jira-issue-reader.sh <issue_key> --json    # Raw JSON output

Environment:
  ATLASSIAN_EMAIL      - Atlassian account email
  ATLASSIAN_API_TOKEN  - API token (NOT password)
  ATLASSIAN_BASE_URL   - e.g., https://company.atlassian.net

Examples:
  jira-issue-reader.sh PROJ-123
  jira-issue-reader.sh ML-1170 --json
EOF
}

main() {
    local issue_key=""
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
                if [[ -z "$issue_key" ]]; then
                    issue_key="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$issue_key" ]]; then
        echo -e "${RED}Error: issue_key required${NC}" >&2
        usage >&2
        exit 1
    fi

    check_env

    echo -e "${YELLOW}Fetching ${issue_key}...${NC}" >&2

    local response
    response=$(fetch_issue "$issue_key")

    # Check for API errors
    if echo "$response" | jq -e '.errorMessages' >/dev/null 2>&1; then
        echo -e "${RED}Error fetching issue:${NC}" >&2
        echo "$response" | jq -r '.errorMessages[]' >&2
        exit 1
    fi

    if [[ "$output_json" == "true" ]]; then
        echo "$response" | jq '.'
    else
        format_issue "$response"
    fi
}

main "$@"
