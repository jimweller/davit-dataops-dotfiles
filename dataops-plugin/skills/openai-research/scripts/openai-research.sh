#!/usr/bin/env bash
# openai-research.sh - Thorough web research via OpenAI GPT-5
# Usage: openai-research.sh "research query" [--no-web-search]
#
# Requires: OPENAI_API_KEY environment variable
# Uses: OpenAI Responses API with gpt-5 model + high reasoning
# Designed for thorough research (typically ~1 minute)

set -uo pipefail

# Check API key
if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    echo '{"error": "OPENAI_API_KEY not set"}' >&2
    exit 1
fi

# Parse arguments
query="${1:-}"
no_web_search="${2:-}"

if [[ -z "$query" ]]; then
    echo '{"error": "No query provided. Usage: openai-research.sh \"query\" [--no-web-search]"}' >&2
    exit 1
fi

# Build tools array - web search enabled by default
tools='[{"type": "web_search"}]'
if [[ "$no_web_search" == "--no-web-search" ]]; then
    tools='[]'
fi

# Escape query for JSON using jq
escaped_query=$(printf '%s' "$query" | jq -Rs .)

# Call OpenAI Responses API with gpt-5 + high reasoning for thorough research
response=$(curl -s -w "\n%{http_code}" https://api.openai.com/v1/responses \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -d "{
        \"model\": \"gpt-5\",
        \"reasoning\": {\"effort\": \"high\"},
        \"input\": $escaped_query,
        \"tools\": $tools
    }" 2>&1)

# Extract HTTP status code (last line) and body (everything else)
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

# Check for curl errors
if [[ ! "$http_code" =~ ^[0-9]+$ ]]; then
    echo "{\"error\": \"curl failed\", \"details\": $(printf '%s' "$response" | jq -Rs .)}" >&2
    exit 1
fi

# Check HTTP status
if [[ "$http_code" -ne 200 ]]; then
    echo "{\"error\": \"API returned HTTP $http_code\", \"response\": $body}" >&2
    exit 1
fi

# Check for API error in response
if echo "$body" | jq -e '.error' >/dev/null 2>&1; then
    echo "$body" >&2
    exit 1
fi

# Extract output_text from the response
# The Responses API returns output as an array of content items
output_text=$(echo "$body" | jq -r '
    if .output_text then
        .output_text
    elif .output then
        (.output[] | select(.type == "message") | .content[] | select(.type == "output_text") | .text) //
        (.output[] | select(.type == "message") | .content[] | select(.type == "text") | .text) //
        (.output | tostring)
    else
        .
    end
')

if [[ -z "$output_text" ]] || [[ "$output_text" == "null" ]]; then
    # Fallback: return the whole response for debugging
    echo "$body"
else
    echo "$output_text"
fi
