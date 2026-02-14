#!/usr/bin/env bash
# ado-user-commits-cached.sh - List recent commits by a user from local repo cache
# Usage: ado-user-commits-cached.sh [user] [--project X] [--all-projects] [--since <date>] [--top <N>]
# Output: JSON array of commits sorted by date (newest first)
#
# Queries local bare repo cache instead of ADO API — zero API calls, instant results.
# Searches ALL branches (feature, bugfix, etc.) via git log --all.
#
# Prerequisites:
#   1. Run ado-repo-cache-sync.sh first to populate the cache
#   2. Cache dir: ~/.dataops-assistant/ado-query-repo-cache/ (or configured in repo-cache.yaml)
#
# Default: current user, last 30 days, top 50 results

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ado-common.sh"

# We don't need ado::init here — no API calls needed for cached queries.
# But we do need AZURE_DEVOPS_ORG for webUrl construction.
ado::require_org

# Parse arguments
user=""
since=""
top="50"
project_filter=""
all_projects=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --since)
            since="$2"
            shift 2
            ;;
        --top)
            top="$2"
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
        -*)
            ado::error "Unknown option: $1. Usage: ado-user-commits-cached.sh [user] [--project X] [--all-projects] [--since <date>] [--top <N>]"
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

# Default since to 30 days ago
if [[ -z "$since" ]]; then
    if date -v-1d +%Y-%m-%d &>/dev/null 2>&1; then
        since=$(date -v-30d +%Y-%m-%d)
    else
        since=$(date -d '30 days ago' +%Y-%m-%d)
    fi
fi

# Resolve cache dir
cache_dir=$(ado::repo_cache_dir)

auto_sync_project() {
    local project="$1"
    echo "Cache missing for project '$project'. Auto-syncing..." >&2
    "$SCRIPT_DIR/ado-repo-cache-sync.sh" --project "$project" --quiet >&2 || true
}

# Auto-sync if cache dir doesn't exist at all
if [[ ! -d "$cache_dir" ]]; then
    if [[ -n "$project_filter" ]]; then
        auto_sync_project "$project_filter"
    elif [[ "$all_projects" == "true" ]]; then
        echo "Cache not found. Auto-syncing all projects..." >&2
        "$SCRIPT_DIR/ado-repo-cache-sync.sh" --all-projects --quiet >&2 || true
    else
        echo "Cache not found. Auto-syncing configured projects..." >&2
        "$SCRIPT_DIR/ado-repo-cache-sync.sh" --quiet >&2 || true
    fi
fi

if [[ ! -d "$cache_dir" ]]; then
    ado::error "Repo cache sync failed. Check az login and AZURE_DEVOPS_ORG."
fi

# Warn if cache is stale
if [[ -f "$cache_dir/.last-sync" ]]; then
    last_sync=$(cat "$cache_dir/.last-sync")
    echo "Cache last synced: $last_sync" >&2
else
    echo "WARNING: Cache has no .last-sync timestamp." >&2
fi

# Resolve which project directories to scan
org_base="${AZURE_DEVOPS_ORG%/}"

if [[ -n "$project_filter" ]]; then
    # Single project — auto-sync if missing
    project_dirs=()
    if [[ ! -d "$cache_dir/$project_filter" ]]; then
        auto_sync_project "$project_filter"
    fi
    if [[ -d "$cache_dir/$project_filter" ]]; then
        project_dirs+=("$cache_dir/$project_filter")
    else
        ado::error "Project '$project_filter' not found in cache after sync attempt."
    fi
elif [[ "$all_projects" == "true" ]]; then
    # All cached projects
    project_dirs=()
    for d in "$cache_dir"/*/; do
        [[ -d "$d" ]] && project_dirs+=("$d")
    done
else
    # Use projects.yaml config
    projects=$(ado::project_list "" "false")
    project_dirs=()
    saved_ifs="$IFS"
    IFS=$'\n'
    for project in $(echo "$projects" | jq -r '.[]'); do
        if [[ -d "$cache_dir/$project" ]]; then
            project_dirs+=("$cache_dir/$project")
        fi
    done
    IFS="$saved_ifs"
fi

if [[ ${#project_dirs[@]} -eq 0 ]]; then
    ado::error "No cached projects found. Run ado-repo-cache-sync.sh first."
fi

# Create temp dir for parallel results
tmpdir=$(mktemp -d)
trap "rm -rf '$tmpdir'" EXIT

max_parallel=10
count=0

# Walk all repo dirs and query git log in parallel
for project_dir in "${project_dirs[@]}"; do
    project=$(basename "$project_dir")

    for repo_dir in "$project_dir"/*.git; do
        [[ -d "$repo_dir" ]] || continue

        repo_name=$(basename "$repo_dir" .git)
        output_file="$tmpdir/commits_${count}.json"

        (
            # git log --all searches all branches
            # Format: fullHash|authorName|authorEmail|ISOdate|subject
            raw=$(git -C "$repo_dir" log --all --author="$user" --since="$since" \
                --format='%H|%aN|%ae|%aI|%s' 2>/dev/null | head -100) || raw=""

            if [[ -z "$raw" ]]; then
                echo "[]" > "$output_file"
                exit 0
            fi

            # Parse pipe-delimited output into JSON
            echo "$raw" | jq -R --arg proj "$project" --arg repo "$repo_name" --arg org "$org_base" '
                split("|") |
                if length >= 5 then
                    {
                        project: $proj,
                        repository: $repo,
                        commitId: .[0][0:8],
                        fullCommitId: .[0],
                        author: .[1],
                        email: .[2],
                        date: .[3],
                        comment: ([.[4:] | join("|")] | .[0]),
                        webUrl: ($org + "/" + ($proj | gsub(" "; "%20")) + "/_git/" + ($repo | gsub(" "; "%20")) + "/commit/" + .[0])
                    }
                else empty end
            ' | jq -s '.' > "$output_file"
        ) &

        ((count++))

        if (( count % max_parallel == 0 )); then
            wait
        fi
    done
done

wait

# Merge all results
all_commits="[]"
for file in "$tmpdir"/commits_*.json; do
    if [[ -f "$file" ]]; then
        content=$(cat "$file")
        if [[ "$content" != "[]" ]]; then
            all_commits=$(echo "$all_commits" "$content" | jq -s '.[0] + .[1]')
        fi
    fi
done

# Sort by date (newest first) and limit to --top
echo "$all_commits" | jq --argjson top "$top" 'sort_by(.date) | reverse | .[:$top]'
