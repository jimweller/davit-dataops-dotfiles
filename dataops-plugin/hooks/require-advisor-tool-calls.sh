#!/usr/bin/env bash
# require-advisor-tool-calls.sh - Block advisor agents that don't call tools
# Used in SubagentStop hook to prevent hallucinated search results

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Extract fields
AGENT_TRANSCRIPT=$(echo "$INPUT" | jq -r '.agent_transcript_path // empty')
AGENT_NAME=$(echo "$INPUT" | jq -r '.metadata.subagent_type // empty')

# Only apply to advisor agents
if [[ ! "$AGENT_NAME" =~ -advisor$ ]]; then
    # Not an advisor agent, allow
    exit 0
fi

# Count tool_use blocks in the agent transcript
if [[ -z "$AGENT_TRANSCRIPT" ]] || [[ ! -f "$AGENT_TRANSCRIPT" ]]; then
    # No transcript available (shouldn't happen), allow
    exit 0
fi

# Parse JSONL transcript and count tool_use content blocks
TOOL_COUNT=$(jq -rs '
  [ .[]
    | select(.message.role == "assistant")
    | try (.message.content // []) catch []
    | map(select(.type == "tool_use"))
    | length
  ] | add // 0
' "$AGENT_TRANSCRIPT" 2>/dev/null || echo "0")

if [[ "${TOOL_COUNT:-0}" -lt 1 ]]; then
    # Block the completion
    cat <<EOF
{
  "decision": "block",
  "reason": "CRITICAL: You are a ${AGENT_NAME} agent. You MUST call search/list tools to retrieve real data. You have not called any tools (tool_uses: 0). Do NOT fabricate results. Call the appropriate MCP tool (searchJiraIssuesUsingJql, searchConfluenceUsingCql, list_incidents, etc.) to get actual data, then return a reading plan based on those results."
}
EOF
    exit 0
fi

# Tool(s) were called, allow completion
exit 0
