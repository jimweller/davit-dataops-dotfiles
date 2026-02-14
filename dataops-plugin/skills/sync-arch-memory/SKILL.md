---
description: "Sync architectural memory repos from ADO to local cache. Run manually to force refresh or check status."
allowed-tools: ["Bash", "Read"]
model: haiku
context: fork
---


# Sync Architectural Memory

Syncs the team's architectural memory repositories from Azure DevOps to local cache.

## Usage

Run the sync script:
```bash
bash ~/.dataops-assistant/bin/sync-arch-memory.sh
```

## Options

| Flag | Description |
|------|-------------|
| `--force` | Pull all repos regardless of hash |
| `--quiet` | Suppress progress output (JSON only) |
| `--check` | Check status without syncing |

## Staleness Detection

Uses git commit hash comparison (not time-based):
- Compares local HEAD vs remote HEAD
- Only pulls when remote has new commits
- Shows hash values in output for transparency

## Cache Location

Default: `~/.dataops-assistant/cached-memory/{repo-name}/`

Override via `ARCH_MEMORY_CACHE_DIR` for testing:
```bash
ARCH_MEMORY_CACHE_DIR=/tmp/test-cache ./sync-arch-memory.sh
```

## Repos Synced

| Repo | Domain |
|------|--------|
| `general-memory` | Universal process and rules |
| `golang-memory` | Go patterns and conventions |
| `bash-memory` | Shell scripting standards |
| `terraform-memory` | Terraform module patterns |
| `make-memory` | Makefile conventions |
| `shared-agw-memory` | AGW-specific patterns |

## Per-Repo Overrides

Set environment variables to use local directories instead of cache:

- `GENERAL_MEMORY_DIR` - General process and rules
- `GOLANG_MEMORY_DIR` - Go patterns and conventions
- `BASH_MEMORY_DIR` - Shell scripting standards
- `TERRAFORM_MEMORY_DIR` - Terraform module patterns
- `MAKE_MEMORY_DIR` - Makefile conventions
- `SHARED_AGW_MEMORY_DIR` - AGW-specific patterns

## Output

Display the JSON summary to the user, highlighting:
- Which repos were synced vs skipped
- Any failures
- Any overrides in effect

## Example Output

```json
{
  "cache_root": "~/.dataops-assistant/cached-memory",
  "repos": [
    {
      "repo": "golang-memory",
      "status": "current",
      "action": "none",
      "local_hash": "abc1234...",
      "remote_hash": "abc1234..."
    },
    {
      "repo": "bash-memory",
      "status": "updated",
      "action": "pull",
      "local_hash": "def5678..."
    },
    {
      "repo": "terraform-memory",
      "status": "overridden",
      "action": "skip",
      "override_path": "/local/path"
    }
  ]
}
```

**Status values:**
- `current` - Local matches remote (no update needed)
- `behind` - Remote has newer commits (needs pull)
- `updated` - Successfully pulled new commits
- `cloned` - Fresh clone
- `overridden` - Using local override path
