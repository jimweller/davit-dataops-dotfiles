#!/usr/bin/env bash
# ado-common.sh - Shared functions for ADO query scripts
# Source this file: source "$(dirname "$0")/ado-common.sh"

set -euo pipefail

# --- Configuration ---
# Organization URL must be set via environment variable
# Example: export AZURE_DEVOPS_ORG="https://dev.azure.com/your-org"
#
# Identity variable (for "my" queries):
# Example: export MCG_EMAIL="user@mcg.com"

# Azure DevOps resource ID for token requests
ADO_RESOURCE_ID="499b84ac-1321-427f-aa17-267ca6975798"

# --- Identity Functions ---

# Get current user's email
# Checks MCG_EMAIL first, falls back to az account
# Usage: email=$(ado::current_user_email)
ado::current_user_email() {
    if [[ -n "${MCG_EMAIL:-}" ]]; then
        echo "$MCG_EMAIL"
    else
        az account show --query user.name -o tsv 2>/dev/null || echo ""
    fi
}

# --- Utility Functions ---

# Output JSON error to stderr and exit
# Usage: ado::error "message"
ado::error() {
    local msg="$1"
    echo "{\"error\": \"$msg\"}" >&2
    exit 1
}

# Check that AZURE_DEVOPS_ORG is set
ado::require_org() {
    if [[ -z "${AZURE_DEVOPS_ORG:-}" ]]; then
        ado::error "AZURE_DEVOPS_ORG environment variable not set. Set to your Azure DevOps org URL (e.g., https://dev.azure.com/your-org)"
    fi
}

# Check that az CLI is installed and authenticated
ado::check_auth() {
    if ! command -v az &>/dev/null; then
        ado::error "az CLI not installed. Install from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi

    # Check if azure-devops extension is installed
    if ! az extension show --name azure-devops &>/dev/null 2>&1; then
        ado::error "azure-devops extension not installed. Run: az extension add --name azure-devops"
    fi

    # Check if logged in (az devops commands need this)
    if ! az account show &>/dev/null 2>&1; then
        ado::error "Azure CLI not authenticated. Run: az login"
    fi
}

# Initialize: check auth and validate org is set
# Call this at the start of each script
ado::init() {
    ado::check_auth
    ado::require_org
}

# Generic pagination handler for az devops commands
# Loops through results using --skip and --top parameters
# Usage: ado::paginate "az devops command" [page_size]
# Note: Not all az devops commands support pagination consistently
ado::paginate() {
    local cmd="$1"
    local page_size="${2:-100}"
    local skip=0
    local all_results="[]"
    local page_results

    while true; do
        page_results=$($cmd --skip "$skip" --top "$page_size" 2>/dev/null) || break

        # Check if we got results
        local count
        count=$(echo "$page_results" | jq 'length')

        if [[ "$count" -eq 0 ]]; then
            break
        fi

        # Merge results
        all_results=$(echo "$all_results" "$page_results" | jq -s '.[0] + .[1]')

        # If we got fewer than page_size, we're done
        if [[ "$count" -lt "$page_size" ]]; then
            break
        fi

        skip=$((skip + page_size))
    done

    echo "$all_results"
}

# Format a simple JSON array output
# Usage: some_command | ado::format_json
ado::format_json() {
    jq '.'
}

# Filter JSON array by field value (case-insensitive)
# Usage: echo "$json" | ado::filter_ilike "field" "pattern"
ado::filter_ilike() {
    local field="$1"
    local pattern="$2"
    jq --arg f "$field" --arg p "$pattern" '[.[] | select(.[$f] | ascii_downcase | contains($p | ascii_downcase))]'
}

# Extract specific fields from JSON array
# Usage: echo "$json" | ado::select_fields "field1" "field2" ...
ado::select_fields() {
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

# --- Git Auth Functions (for repo cache) ---

# Get or cache ADO access token (1 call per session)
# Usage: token=$(ado::get_token)
ado::get_token() {
    if [[ -z "${_ADO_TOKEN:-}" ]]; then
        _ADO_TOKEN=$(az account get-access-token --resource "$ADO_RESOURCE_ID" --query accessToken -o tsv 2>/dev/null) || ado::error "Failed to get ADO token. Run 'az login' first."
    fi
    echo "$_ADO_TOKEN"
}

# Setup .git-askpass script for HTTPS clone/fetch
# Usage: askpass=$(ado::setup_git_askpass "$cache_dir")
ado::setup_git_askpass() {
    local cache_dir="$1"
    local askpass="$cache_dir/.git-askpass"
    local token
    token=$(ado::get_token)
    mkdir -p "$cache_dir"
    printf '#!/bin/sh\necho "%s"\n' "$token" > "$askpass"
    chmod +x "$askpass"
    echo "$askpass"
}

# Run git with token auth
# Usage: ado::git_with_token "$askpass" clone --bare ...
ado::git_with_token() {
    local askpass="$1"; shift
    GIT_ASKPASS="$askpass" git "$@"
}

# Resolve repo cache directory from config
# Usage: cache_dir=$(ado::repo_cache_dir)
# Override: ADO_REPO_CACHE_DIR env var takes precedence over config
ado::repo_cache_dir() {
    # Env var override (used by tests for isolated fixtures)
    if [[ -n "${ADO_REPO_CACHE_DIR:-}" ]]; then
        echo "$ADO_REPO_CACHE_DIR"
        return 0
    fi
    local config="${HOME}/.dataops-assistant/ado-query/repo-cache.yaml"
    local default_dir="${HOME}/.dataops-assistant/ado-query-repo-cache"
    if [[ -f "$config" ]] && command -v yq &>/dev/null; then
        local dir
        dir=$(yq -r '.cache_dir // ""' "$config" 2>/dev/null)
        if [[ -n "$dir" ]]; then
            echo "${dir/#\~/$HOME}"
            return 0
        fi
    fi
    echo "$default_dir"
}

# --- Project Scope Functions ---

# Config file path for default projects
ADO_CONFIG_DIR="${HOME}/.dataops-assistant/ado-query"
ADO_PROJECTS_CONFIG="${ADO_CONFIG_DIR}/projects.yaml"

# Parse common PR script arguments: [user] [--status X] [--project X] [--all-projects] [--since YYYY-MM-DD]
# Sets caller-scope variables: user, status, project_filter, all_projects, since_date
# Usage: ado::parse_pr_args "$@"
ado::parse_pr_args() {
    user=""
    status="active"
    project_filter=""
    all_projects=false
    since_date=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --status)
                status="$2"
                shift 2
                ;;
            --project)
                project_filter="$2"
                shift 2
                ;;
            --all-projects)
                all_projects=true
                shift
                ;;
            --since)
                since_date="$2"
                shift 2
                ;;
            -*)
                local script_name
                script_name="$(basename "${BASH_SOURCE[1]}")"
                ado::error "Unknown option: $1. Usage: $script_name [user] [--status active|completed|all] [--project <project>] [--all-projects] [--since YYYY-MM-DD]"
                ;;
            *)
                if [[ -z "$user" ]]; then
                    user="$1"
                fi
                shift
                ;;
        esac
    done

    # Default to current user if not specified
    if [[ -z "$user" ]]; then
        user=$(ado::current_user_email)
        if [[ -z "$user" ]]; then
            ado::error "Failed to get current user. Set MCG_EMAIL or run 'az login'."
        fi
    fi
}

# Resolve project list based on args and config.
# Resolution order:
#   1. --project "X"        → ["X"]
#   2. --all-projects        → az devops project list (with stderr warning)
#   3. Config file           → read projects from ~/.dataops-assistant/ado-query/projects.yaml
#   4. Error                 → tells user how to fix
#
# Usage: projects=$(ado::project_list "$project_filter" "$all_projects")
# Outputs JSON array to stdout.
ado::project_list() {
    local filter="${1:-}"
    local all="${2:-false}"

    # 1. Explicit --project
    if [[ -n "$filter" ]]; then
        echo "[\"$filter\"]"
        return 0
    fi

    # 2. Explicit --all-projects
    if [[ "$all" == "true" ]]; then
        echo "WARNING: Querying all projects. This makes many API calls and may be slow." >&2
        az devops project list --organization "$AZURE_DEVOPS_ORG" --query "value[].name" -o json 2>/dev/null || ado::error "Failed to list projects"
        return 0
    fi

    # 3. Config file
    if [[ -f "$ADO_PROJECTS_CONFIG" ]]; then
        local config_projects
        if command -v yq &>/dev/null; then
            config_projects=$(yq -o=json '.projects' "$ADO_PROJECTS_CONFIG" 2>/dev/null)
        else
            # Fallback: parse simple YAML list without yq
            config_projects=$(awk '/^projects:/{found=1; next} found && /^  - /{gsub(/^  - /, ""); print} found && !/^  - /{exit}' "$ADO_PROJECTS_CONFIG" | jq -R -s 'split("\n") | map(select(length > 0))')
        fi
        if [[ -n "$config_projects" ]] && [[ "$config_projects" != "null" ]] && [[ "$config_projects" != "[]" ]]; then
            echo "$config_projects"
            return 0
        fi
    fi

    # 4. Error
    ado::error "No projects specified. Use --project <name>, --all-projects, or configure $ADO_PROJECTS_CONFIG"
}

# Standard jq expression for PR field selection.
# Usage in jq: --arg proj "$project" --arg org "$org_base" "$(ado::pr_fields)"
ado::pr_fields() {
    cat <<'JQ'
[.[] | {
    project: $proj,
    pullRequestId,
    title,
    status,
    createdBy: .createdBy.displayName,
    creationDate,
    sourceRefName,
    targetRefName,
    repository: .repository.name,
    repositoryId: .repository.id,
    webUrl: ($org + "/" + $proj + "/_git/" + .repository.name + "/pullrequest/" + (.pullRequestId | tostring))
}]
JQ
}

# Run a callback function across projects in parallel, merge JSON results.
#
# Arguments:
#   $1 - callback function name (receives: project, output_file)
#   $2 - JSON array of project names
#
# The callback must write a JSON array to the output_file.
# Results are merged and sorted by creationDate descending.
#
# Usage:
#   my_query() { local project="$1" output_file="$2"; ...; }
#   ado::for_each_project_parallel my_query "$projects"
ado::for_each_project_parallel() {
    local callback="$1"
    local projects_json="$2"

    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" EXIT

    local max_parallel=10
    local count=0

    local old_IFS="${IFS}"
    IFS=$'\n'
    for project in $(echo "$projects_json" | jq -r '.[]'); do
        local output_file="$tmpdir/${count}.json"

        "$callback" "$project" "$output_file" &

        ((count++))

        # Throttle: wait if we hit max parallel
        if (( count % max_parallel == 0 )); then
            wait
        fi
    done
    IFS="${old_IFS}"

    # Wait for remaining jobs
    wait

    # Merge all results
    local all_results="[]"
    for file in "$tmpdir"/*.json; do
        if [[ -f "$file" ]]; then
            local content
            content=$(cat "$file")
            if [[ "$content" != "[]" ]]; then
                all_results=$(echo "$all_results" "$content" | jq -s '.[0] + .[1]')
            fi
        fi
    done

    # Filter by since_date if set (ISO date string comparison works for YYYY-MM-DD vs full timestamps)
    if [[ -n "${since_date:-}" ]]; then
        all_results=$(echo "$all_results" | jq --arg since "$since_date" '[.[] | select((.creationDate // .date) >= $since)]')
    fi

    # Sort by creation date (newest first) — works for both PRs and commits
    echo "$all_results" | jq 'sort_by(.creationDate // .date) | reverse'
}
