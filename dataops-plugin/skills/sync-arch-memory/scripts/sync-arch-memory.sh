#!/usr/bin/env bash
set -euo pipefail

# Sync architectural memory repos from ADO to local cache
# Usage: sync-arch-memory.sh [--force] [--quiet] [--check]
#
# Output: JSON summary to stdout
# Errors: To stderr
#
# Staleness is determined by comparing local vs remote git commit hashes.
# Only pulls when remote has new commits.
#
# Requires: az CLI (authenticated via `az login`)
#
# Environment variables:
#   ARCH_MEMORY_CACHE_DIR - Direct override for cache directory (for testing)
#   DATAOPS_ASSISTANT_HOME - Base directory (default: ~/.dataops-assistant)
#   {REPO}_MEMORY_DIR - Override location for specific repo (e.g., GOLANG_MEMORY_DIR)

# ARCH_MEMORY_CACHE_DIR takes precedence for direct override (useful for testing)
if [[ -n "${ARCH_MEMORY_CACHE_DIR:-}" ]]; then
  CACHE_ROOT="$ARCH_MEMORY_CACHE_DIR"
else
  CACHE_ROOT="${DATAOPS_ASSISTANT_HOME:-$HOME/.dataops-assistant}/cached-memory"
fi
ADO_BASE_URL="https://mcgsead.visualstudio.com/DefaultCollection/Platform%20Engineering/_git"
ADO_RESOURCE_ID="499b84ac-1321-427f-aa17-267ca6975798"  # Azure DevOps resource ID for token

# Repos and their env var override names
REPOS="bash-memory:BASH_MEMORY_DIR
general-memory:GENERAL_MEMORY_DIR
golang-memory:GOLANG_MEMORY_DIR
make-memory:MAKE_MEMORY_DIR
terraform-memory:TERRAFORM_MEMORY_DIR
shared-agw-memory:SHARED_AGW_MEMORY_DIR"

FORCE=false
QUIET=false
CHECK_ONLY=false
ADO_TOKEN=""

log() {
  [[ "$QUIET" == "true" ]] || echo "$@" >&2
}

get_ado_token() {
  if [[ -z "$ADO_TOKEN" ]]; then
    ADO_TOKEN=$(az account get-access-token --resource "$ADO_RESOURCE_ID" --query accessToken -o tsv 2>/dev/null) || {
      log "ERROR: Failed to get ADO token. Run 'az login' first." >&2
      return 1
    }
  fi
  echo "$ADO_TOKEN"
}

git_with_token() {
  local token
  token=$(get_ado_token) || return 1
  # Use credential helper that returns our token
  GIT_ASKPASS="$CACHE_ROOT/.git-askpass" git "$@"
}

setup_git_askpass() {
  mkdir -p "$CACHE_ROOT"
  local askpass="$CACHE_ROOT/.git-askpass"
  local token
  token=$(get_ado_token) || return 1
  cat > "$askpass" << EOF
#!/bin/sh
echo "$token"
EOF
  chmod +x "$askpass"
}

# Get local HEAD commit hash
get_local_hash() {
  local repo_dir="$1"
  git -C "$repo_dir" rev-parse HEAD 2>/dev/null || echo ""
}

# Get remote HEAD commit hash (requires token setup)
get_remote_hash() {
  local repo="$1"
  local url="$ADO_BASE_URL/$repo"
  git_with_token ls-remote "$url" HEAD 2>/dev/null | cut -f1 || echo ""
}

sync_repo() {
  local repo="$1"
  local env_var="$2"
  local repo_dir="$CACHE_ROOT/$repo"
  local status="unknown"
  local action="none"
  local override_path=""
  local local_hash=""
  local remote_hash=""

  # Check for env var override
  local override_value="${!env_var:-}"
  if [[ -n "$override_value" ]]; then
    status="overridden"
    action="skip"
    override_path="$override_value"
    log "SKIP: $repo (overridden by $env_var=$override_value)"
  elif [[ "$CHECK_ONLY" == "true" ]]; then
    # Just check status, don't sync
    if [[ -d "$repo_dir/.git" ]]; then
      local_hash=$(get_local_hash "$repo_dir")
      remote_hash=$(get_remote_hash "$repo")
      if [[ -z "$remote_hash" ]]; then
        status="check_failed"
        action="none"
        log "CHECK: $repo - failed to get remote hash"
      elif [[ "$local_hash" == "$remote_hash" ]]; then
        status="current"
        action="none"
        log "CHECK: $repo - current (${local_hash:0:7})"
      else
        status="behind"
        action="needs_pull"
        log "CHECK: $repo - behind (local: ${local_hash:0:7}, remote: ${remote_hash:0:7})"
      fi
    else
      status="missing"
      action="needs_clone"
      log "CHECK: $repo - missing"
    fi
  elif [[ -d "$repo_dir/.git" ]]; then
    local_hash=$(get_local_hash "$repo_dir")

    if [[ "$FORCE" == "true" ]]; then
      log "PULL: $repo (forced)"
      if git_with_token -C "$repo_dir" pull --quiet --ff-only 2>/dev/null; then
        local_hash=$(get_local_hash "$repo_dir")
        status="updated"
        action="pull"
      else
        status="pull_failed"
        action="pull"
        log "WARN: $repo pull failed, using cached version" >&2
      fi
    else
      # Check if remote has new commits
      remote_hash=$(get_remote_hash "$repo")
      if [[ -z "$remote_hash" ]]; then
        status="check_failed"
        action="none"
        log "WARN: $repo - failed to check remote, using cached version"
      elif [[ "$local_hash" == "$remote_hash" ]]; then
        status="current"
        action="none"
        log "CURRENT: $repo (${local_hash:0:7})"
      else
        log "PULL: $repo (${local_hash:0:7} -> ${remote_hash:0:7})"
        if git_with_token -C "$repo_dir" pull --quiet --ff-only 2>/dev/null; then
          local_hash=$(get_local_hash "$repo_dir")
          status="updated"
          action="pull"
        else
          status="pull_failed"
          action="pull"
          log "WARN: $repo pull failed, using cached version" >&2
        fi
      fi
    fi
  else
    log "CLONE: $repo"
    mkdir -p "$CACHE_ROOT"
    local clone_url="$ADO_BASE_URL/$repo"
    if git_with_token clone --quiet "$clone_url" "$repo_dir" 2>/dev/null; then
      local_hash=$(get_local_hash "$repo_dir")
      status="cloned"
      action="clone"
    else
      status="clone_failed"
      action="clone"
      log "ERROR: $repo clone failed" >&2
    fi
  fi

  # Return JSON for this repo
  local json="{\"repo\":\"$repo\",\"status\":\"$status\",\"action\":\"$action\""
  if [[ -n "$override_path" ]]; then
    json="$json,\"override_path\":\"$override_path\""
  fi
  if [[ -n "$local_hash" ]]; then
    json="$json,\"local_hash\":\"$local_hash\""
  fi
  if [[ -n "$remote_hash" ]]; then
    json="$json,\"remote_hash\":\"$remote_hash\""
  fi
  json="$json}"
  echo "$json"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) FORCE=true; shift ;;
      --quiet) QUIET=true; shift ;;
      --check) CHECK_ONLY=true; shift ;;
      --help)
        echo "Usage: sync-arch-memory.sh [--force] [--quiet] [--check]"
        echo ""
        echo "Options:"
        echo "  --force   Pull all repos regardless of hash"
        echo "  --quiet   Suppress progress output (JSON only)"
        echo "  --check   Check status without syncing"
        echo ""
        echo "Environment:"
        echo "  ARCH_MEMORY_CACHE_DIR     Direct cache dir override (for testing)"
        echo "  DATAOPS_ASSISTANT_HOME    Base directory (default: ~/.dataops-assistant)"
        echo "  {REPO}_MEMORY_DIR         Override location for specific repo"
        exit 0
        ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  log "Syncing architectural memory to $CACHE_ROOT"

  # Setup git authentication
  if ! setup_git_askpass; then
    log "ERROR: Failed to setup git authentication" >&2
    exit 1
  fi

  local results=()
  local IFS=$'\n'
  for line in $REPOS; do
    local repo="${line%%:*}"
    local env_var="${line##*:}"
    local result
    result=$(sync_repo "$repo" "$env_var")
    results+=("$result")
  done

  # Output JSON summary
  local repos_json
  repos_json=$(printf '%s\n' "${results[@]}" | jq -s '.')

  jq -n \
    --arg cache_root "$CACHE_ROOT" \
    --argjson repos "$repos_json" \
    '{
      cache_root: $cache_root,
      repos: $repos
    }'
}

main "$@"
