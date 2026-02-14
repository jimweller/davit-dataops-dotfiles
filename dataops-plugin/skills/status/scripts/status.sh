#!/usr/bin/env bash
set -uo pipefail

# DataOps Assistant - Capability Check
# Status messages go to stderr (visible to user)
# JSON with additionalContext goes to stdout (injected into Claude's context)
#
# This script uses manifest-based skill discovery:
# 1. Discovers all skills/*/SKILL.md files
# 2. Parses frontmatter for `status-check` field
# 3. Runs each skill's status script
# 4. Aggregates results into unified output

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${SCRIPT_DIR}/../../.."

# --- Required MCP server names (not configurable) ---
MCP_ATLASSIAN="atlassian"
MCP_ADO="azure-devops"
MCP_PAGERDUTY="pagerduty"

# --- Capability tracking for Claude context ---
AVAILABLE_AGENTS=()
DISABLED_AGENTS=()
AVAILABLE_SKILLS=()
DISABLED_SKILLS=()
AVAILABLE_CLI=()
MISSING_CLI=()

# --- Helper functions ---

status::check_cli() {
    local name="$1"
    local context="${2:-}"
    if command -v "$name" >/dev/null 2>&1; then
        printf "  ✓ %s\n" "$name" >&2
        AVAILABLE_CLI+=("$name")
    else
        printf "  ✗ %s%s\n" "$name" "${context:+ ($context)}" >&2
        MISSING_CLI+=("$name")
    fi
}

status::check_mcp() {
    local name="$1"
    local agents="$2"
    local configured="$3"
    if printf "%s" "$configured" | grep -qi "$name"; then
        printf "  ✓ %s (%s)\n" "$name" "$agents" >&2
        AVAILABLE_AGENTS+=("$agents")
    else
        printf "  ✗ %s (%s)\n" "$name" "$agents" >&2
        DISABLED_AGENTS+=("$agents")
    fi
}

status::collect_mcp_servers() {
    local result=""
    local f
    for f in "./.mcp.json" "$HOME/.claude/settings.json" "$HOME/.claude.json"; do
        [[ -f "$f" ]] && result="$result $(jq -r '.mcpServers // {} | keys[]' "$f" 2>/dev/null || true)"
    done
    printf "%s" "$result"
}

status::parse_frontmatter() {
    # Extract status-check field from SKILL.md frontmatter
    local skill_md="$1"

    # Simple awk-based extraction (no yq dependency for core status)
    awk '
        /^---$/ { if (in_front) exit; in_front=1; next }
        in_front && /^status-check:/ { gsub(/^status-check:[[:space:]]*/, ""); print; exit }
    ' "$skill_md"
}

status::run_skill_checks() {
    printf "\nSkill Status (manifest-based discovery):\n" >&2

    local skill_dirs=("$PLUGIN_ROOT"/skills/*)
    local ran_any=false

    for skill_dir in "${skill_dirs[@]}"; do
        [[ ! -d "$skill_dir" ]] && continue

        local skill_name
        skill_name=$(basename "$skill_dir")

        # Skip the status skill itself
        [[ "$skill_name" == "status" ]] && continue

        local skill_md="$skill_dir/SKILL.md"
        [[ ! -f "$skill_md" ]] && continue

        # Parse frontmatter for status-check field
        local status_script
        status_script=$(status::parse_frontmatter "$skill_md")
        [[ -z "$status_script" ]] && continue

        local script_path="$skill_dir/$status_script"
        if [[ ! -x "$script_path" ]]; then
            printf "  ⚠ %s: status script not executable\n" "$skill_name" >&2
            continue
        fi

        ran_any=true
        printf "\n  [%s]\n" "$skill_name" >&2

        # Run the status script, capture JSON output
        local json_output
        json_output=$("$script_path" 2>&2)

        # Parse JSON result
        local available
        available=$(echo "$json_output" | jq -r '.available // false')

        if [[ "$available" == "true" ]]; then
            AVAILABLE_SKILLS+=("$skill_name")
        else
            local details
            details=$(echo "$json_output" | jq -r '.details // "unavailable"')
            DISABLED_SKILLS+=("$skill_name: $details")
        fi
    done

    if ! $ran_any; then
        printf "  (no skills with status-check defined)\n" >&2
    fi
}

status::check_mcg_email() {
    if [[ -n "${MCG_EMAIL:-}" ]]; then
        printf "  ✓ MCG_EMAIL set (%s)\n" "$MCG_EMAIL" >&2
    else
        printf "  ✗ MCG_EMAIL not set (required for 'my PRs', 'my work' queries)\n" >&2
    fi
}

status::build_context() {
    local context=""

    # Available agents (from MCP)
    if [[ ${#AVAILABLE_AGENTS[@]} -gt 0 ]]; then
        context+="DataOps Assistant available agents: "
        context+="$(IFS=', '; echo "${AVAILABLE_AGENTS[*]}")."
    fi

    # Available skills (from manifest discovery)
    if [[ ${#AVAILABLE_SKILLS[@]} -gt 0 ]]; then
        [[ -n "$context" ]] && context+=" "
        context+="Available skills: "
        context+="$(IFS=', '; echo "${AVAILABLE_SKILLS[*]}")."
    fi

    # Disabled agents
    if [[ ${#DISABLED_AGENTS[@]} -gt 0 ]]; then
        [[ -n "$context" ]] && context+=" "
        context+="Disabled agents (missing MCP): "
        context+="$(IFS=', '; echo "${DISABLED_AGENTS[*]}")."
    fi

    # Disabled skills
    if [[ ${#DISABLED_SKILLS[@]} -gt 0 ]]; then
        [[ -n "$context" ]] && context+=" "
        context+="Disabled skills: "
        context+="$(IFS=', '; echo "${DISABLED_SKILLS[*]}")."
    fi

    # CLI tools
    if [[ ${#AVAILABLE_CLI[@]} -gt 0 ]]; then
        [[ -n "$context" ]] && context+=" "
        context+="CLI tools available: "
        context+="$(IFS=', '; echo "${AVAILABLE_CLI[*]}")."
    fi

    printf "%s" "$context"
}

# --- Main ---
printf "DataOps Assistant: Checking capabilities...\n\n" >&2

printf "Core CLI Tools:\n" >&2
status::check_cli "jq" "required"
status::check_cli "bun" "jira-adf-writer"

printf "\nIdentity:\n" >&2
status::check_mcg_email

printf "\nMCP Servers:\n" >&2
configured_mcps="$(status::collect_mcp_servers)"
status::check_mcp "$MCP_ATLASSIAN" "confluence-advisor, jira-advisor" "$configured_mcps"
status::check_mcp "$MCP_ADO" "ADO PR/build reading" "$configured_mcps"
status::check_mcp "$MCP_PAGERDUTY" "pagerduty-advisor" "$configured_mcps"

# Run manifest-based skill discovery
status::run_skill_checks

printf "\n---\n" >&2
printf "Required MCP server names: atlassian, azure-devops, pagerduty\n" >&2
printf "Run /dataops-assistant:status to recheck.\n" >&2

# Build context for Claude and output as JSON
context="$(status::build_context)"
jq -n --arg ctx "$context" '{"additionalContext": $ctx}'
