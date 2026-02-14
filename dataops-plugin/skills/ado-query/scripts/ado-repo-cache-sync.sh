#!/usr/bin/env bash
# ado-repo-cache-sync.sh - Clone/update bare blobless repo cache for commit queries
# Usage: ado-repo-cache-sync.sh [--project X] [--all-projects] [--force] [--check] [--quiet]
# Output: JSON summary of sync results
#
# Clones repos as bare blobless clones (commit/tree metadata only, no file content).
# Subsequent runs fetch only new objects. Zero API calls for commit queries after sync.
#
# Configuration: ~/.dataops-assistant/ado-query/repo-cache.yaml
#   cache_dir: /custom/path          # Override cache location
#   exclude_projects:                 # Skip entire projects
#     - Archived Project
#   exclude_repos:                    # Skip specific repos (format: "Project/repo-name")
#     - "Data Science/huge-ml-models"
#
# Default: syncs projects from projects.yaml (same as PR/commit scripts)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ado-common.sh"

ado::init

# Parse arguments
project_filter=""
all_projects=false
force=false
check_only=false
quiet=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --project)
            project_filter="$2"
            shift 2
            ;;
        --all-projects)
            all_projects=true
            shift
            ;;
        --force)
            force=true
            shift
            ;;
        --check)
            check_only=true
            shift
            ;;
        --quiet)
            quiet=true
            shift
            ;;
        -*)
            ado::error "Unknown option: $1. Usage: ado-repo-cache-sync.sh [--project X] [--all-projects] [--force] [--check] [--quiet]"
            ;;
        *)
            ado::error "Unexpected argument: $1. Usage: ado-repo-cache-sync.sh [--project X] [--all-projects] [--force] [--check] [--quiet]"
            ;;
    esac
done

# Resolve project list via shared helper
projects=$(ado::project_list "$project_filter" "$all_projects")

# Resolve cache dir and config
cache_dir=$(ado::repo_cache_dir)
config="${HOME}/.dataops-assistant/ado-query/repo-cache.yaml"

# Read exclude lists from config
exclude_projects="[]"
exclude_repos="[]"
if [[ -f "$config" ]] && command -v yq &>/dev/null; then
    exclude_projects=$(yq -o=json '.exclude_projects // []' "$config" 2>/dev/null || echo "[]")
    exclude_repos=$(yq -o=json '.exclude_repos // []' "$config" 2>/dev/null || echo "[]")
fi

# Setup git auth
askpass=$(ado::setup_git_askpass "$cache_dir")

org_base="${AZURE_DEVOPS_ORG%/}"

# Log helper (respects --quiet)
log() {
    if [[ "$quiet" != "true" ]]; then
        echo "$*" >&2
    fi
}

# Create temp dir for parallel results
tmpdir=$(mktemp -d)
trap "rm -rf '$tmpdir'" EXIT

max_parallel=10

# --- Phase 1: List repos for each project (parallel) ---
log "Phase 1: Discovering repos..."

count=0
saved_ifs="$IFS"
IFS=$'\n'
for project in $(echo "$projects" | jq -r '.[]'); do
    # Check if project is excluded
    is_excluded=$(echo "$exclude_projects" | jq --arg p "$project" 'map(select(. == $p)) | length')
    if [[ "$is_excluded" -gt 0 ]]; then
        log "  Skipping excluded project: $project"
        continue
    fi

    output_file="$tmpdir/repos_${count}.tsv"

    (
        repos=$(az repos list --organization "$AZURE_DEVOPS_ORG" --project "$project" --output json 2>/dev/null) || repos="[]"
        [[ -z "$repos" ]] && repos="[]"
        # Output: project<TAB>repoName<TAB>isDisabled<TAB>size
        echo "$repos" | jq -r --arg p "$project" \
            '.[] | select(.isDisabled == false and .size > 0) | [$p, .name] | @tsv' > "$output_file"
    ) &

    ((count++))

    if (( count % max_parallel == 0 )); then
        wait
    fi
done
IFS="$saved_ifs"

wait

# Merge repo lists and filter excludes
all_repos_file="$tmpdir/all_repos.tsv"
cat "$tmpdir"/repos_*.tsv > "$all_repos_file" 2>/dev/null || true

total_repos=$(wc -l < "$all_repos_file" | tr -d ' ')
log "  Found $total_repos repos across projects"

# --- Phase 2: Clone or fetch each repo (parallel) ---
log "Phase 2: Syncing repos..."

count=0
results_dir="$tmpdir/results"
mkdir -p "$results_dir"

while IFS=$'\t' read -r project repo_name; do
    [[ -z "$repo_name" ]] && continue

    # Check if repo is excluded
    is_excluded=$(echo "$exclude_repos" | jq --arg r "$project/$repo_name" 'map(select(. == $r)) | length')
    if [[ "$is_excluded" -gt 0 ]]; then
        log "  Skipping excluded repo: $project/$repo_name"
        echo "{\"project\":\"$project\",\"repo\":\"$repo_name\",\"status\":\"excluded\",\"action\":\"skip\"}" > "$results_dir/${count}.json"
        ((count++))
        continue
    fi

    result_file="$results_dir/${count}.json"

    (
        repo_dir="$cache_dir/$project/$repo_name.git"
        url="${org_base}/${project// /%20}/_git/${repo_name// /%20}"

        if [[ -d "$repo_dir" ]]; then
            # Existing repo — fetch or check
            if [[ "$check_only" == "true" ]]; then
                local_hash=$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || echo "unknown")
                echo "{\"project\":\"$project\",\"repo\":\"$repo_name\",\"status\":\"cached\",\"action\":\"check\",\"localHash\":\"$local_hash\"}" > "$result_file"
            else
                if ado::git_with_token "$askpass" -C "$repo_dir" fetch origin --quiet 2>/dev/null; then
                    local_hash=$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || echo "unknown")
                    echo "{\"project\":\"$project\",\"repo\":\"$repo_name\",\"status\":\"updated\",\"action\":\"fetch\",\"localHash\":\"$local_hash\"}" > "$result_file"
                else
                    echo "{\"project\":\"$project\",\"repo\":\"$repo_name\",\"status\":\"error\",\"action\":\"fetch_failed\"}" > "$result_file"
                fi
            fi
        else
            # New repo — clone
            if [[ "$check_only" == "true" ]]; then
                echo "{\"project\":\"$project\",\"repo\":\"$repo_name\",\"status\":\"missing\",\"action\":\"check\"}" > "$result_file"
            else
                mkdir -p "$(dirname "$repo_dir")"
                if ado::git_with_token "$askpass" clone --bare --filter=blob:none "$url" "$repo_dir" 2>/dev/null; then
                    local_hash=$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || echo "unknown")
                    echo "{\"project\":\"$project\",\"repo\":\"$repo_name\",\"status\":\"cloned\",\"action\":\"clone\",\"localHash\":\"$local_hash\"}" > "$result_file"
                else
                    echo "{\"project\":\"$project\",\"repo\":\"$repo_name\",\"status\":\"error\",\"action\":\"clone_failed\"}" > "$result_file"
                fi
            fi
        fi
    ) &

    ((count++))

    if (( count % max_parallel == 0 )); then
        wait
    fi
done < "$all_repos_file"

wait

# Record sync timestamp
date -u +%Y-%m-%dT%H:%M:%SZ > "$cache_dir/.last-sync"

# --- Phase 3: Build JSON summary ---
all_results="[]"
for file in "$results_dir"/*.json; do
    if [[ -f "$file" ]]; then
        all_results=$(echo "$all_results" | jq --slurpfile r "$file" '. + $r')
    fi
done

# Group by project for output
summary=$(echo "$all_results" | jq --arg cd "$cache_dir" '{
    cache_dir: $cd,
    last_sync: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
    summary: {
        total: length,
        cloned: [.[] | select(.action == "clone")] | length,
        updated: [.[] | select(.action == "fetch")] | length,
        errors: [.[] | select(.status == "error")] | length,
        excluded: [.[] | select(.status == "excluded")] | length,
        cached: [.[] | select(.action == "check" and .status == "cached")] | length,
        missing: [.[] | select(.action == "check" and .status == "missing")] | length
    },
    projects: (group_by(.project) | map({
        project: .[0].project,
        repos: map({repo, status, action} + (if .localHash then {localHash} else {} end))
    }))
}')

echo "$summary"
