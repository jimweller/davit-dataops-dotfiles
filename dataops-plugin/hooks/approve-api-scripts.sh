#!/usr/bin/env bash
#
# PreToolUse hook to auto-approve trusted plugin scripts
#
# Uses directory-based allowlisting to approve any script in:
#   - $CLAUDE_PLUGIN_ROOT/skills/
#   - $CLAUDE_PLUGIN_ROOT/hooks/
#
# Input (stdin): JSON with tool_input containing the command
# Output (stdout): JSON with hookSpecificOutput for approval decisions
#
# Security: Blocks path traversal, validates inputs, uses absolute paths
#
# Debug: Set HOOK_DEBUG=1 to enable stderr logging

# Fail-safe: if anything goes wrong, fall through to normal permission system
set -eo pipefail

# Debug logging (off by default)
debug() {
    [[ "${HOOK_DEBUG:-0}" == "1" ]] && echo "[approve-scripts] $*" >&2
    return 0
}

# Output approval decision in correct Claude Code format
approve() {
    local reason="${1:-Approved plugin internal script}"
    jq -n --arg reason "$reason" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "allow",
            permissionDecisionReason: $reason
        }
    }'
    exit 0
}

# Read the tool input from stdin
INPUT=$(cat)

# Extract the command from the tool input
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || {
    debug "Failed to parse JSON input"
    exit 0
}

# Fail-safe: if no command, fall through
if [[ -z "$COMMAND" ]]; then
    debug "No command found in input"
    exit 0
fi

debug "Checking command: $COMMAND"

# Security: reject path traversal attempts
if [[ "$COMMAND" == *".."* ]]; then
    debug "Blocked: path traversal detected"
    exit 0
fi

# Get plugin root (set by Claude plugin system)
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [[ -z "$PLUGIN_ROOT" ]]; then
    debug "CLAUDE_PLUGIN_ROOT not set, falling through"
    exit 0
fi

# Extract the script path (first token of command)
# Handles: /path/to/script.sh arg1 arg2
#          "/path/with spaces/script.sh" arg1
SCRIPT_PATH=$(echo "$COMMAND" | awk '{print $1}' | tr -d '"'"'")

# Resolve to absolute path if it exists
if [[ -e "$SCRIPT_PATH" ]]; then
    SCRIPT_PATH=$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd)/$(basename "$SCRIPT_PATH") || {
        debug "Failed to resolve path: $SCRIPT_PATH"
        exit 0
    }
fi

debug "Resolved script path: $SCRIPT_PATH"

# Approved directories within the plugin
APPROVED_DIRS=(
    "$PLUGIN_ROOT/skills"
    "$PLUGIN_ROOT/hooks"
    "$HOME/.dataops-assistant/bin"
)

# Check if script is in an approved directory
for dir in "${APPROVED_DIRS[@]}"; do
    if [[ "$SCRIPT_PATH" == "$dir/"* ]]; then
        debug "Approved: $SCRIPT_PATH is in $dir"
        approve "Plugin script in $dir"
    fi
done

# Auto-approve ls commands checking plugin directories
# (Claude sometimes verifies paths before running scripts)
if [[ "$COMMAND" =~ ^ls[[:space:]] ]]; then
    LS_TARGET=$(echo "$COMMAND" | awk '{print $2}' | tr -d '"'"'")
    for dir in "${APPROVED_DIRS[@]}"; do
        if [[ "$LS_TARGET" == "$dir"* ]] || [[ "$LS_TARGET" == "$PLUGIN_ROOT"* ]]; then
            debug "Approved: ls checking plugin path $LS_TARGET"
            approve "ls checking plugin path"
        fi
    done
fi

debug "Not in approved directories, falling through"
exit 0
