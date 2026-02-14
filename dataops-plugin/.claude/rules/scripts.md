---
paths:
  - "skills/*/scripts/**"
---
# Script Development Rules

## File Structure

Each skill's scripts live in `skills/<skill-name>/scripts/`. Common patterns:

```
skills/ado-query/scripts/
  ado-common.sh          # Shared functions (sourced, not executed directly)
  ado-projects.sh        # Standalone script (gets a bin wrapper)
  ado-repos.sh           # Standalone script
  ado-user-commits-cached.sh
```

## Common Library Pattern

Shared functions go in `*-common.sh` files. These are sourced, not executed:

```bash
#!/usr/bin/env bash
# ado-common.sh - shared functions for ADO query scripts

ado::error() {
    echo "ERROR: $*" >&2
    exit 1
}

ado::require_org() {
    [[ -z "${AZURE_DEVOPS_ORG:-}" ]] && ado::error "AZURE_DEVOPS_ORG not set"
}
```

Consuming scripts source them with relative paths:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ado-common.sh"
```

## Output Conventions

- **Structured data** (JSON) goes to **stdout** only
- **Diagnostics, warnings, progress** go to **stderr**
- This separation is critical — skills and tests parse stdout as JSON

```bash
echo "Processing..." >&2          # Diagnostic → stderr
echo '{"result": "ok"}'           # Data → stdout
```

## Error Handling

- Use `set -euo pipefail` at the top of every script
- Use `ado::error` / `sonar::error` / similar for fatal errors (stderr + exit 1)
- Validate required arguments early, before any API calls
- Fail gracefully with clear messages when auth or env vars are missing

## Argument Parsing

Use `while [[ $# -gt 0 ]]; do case $1 in ...` pattern. Reject unknown options explicitly:

```bash
-*)
    ado::error "Unknown option: $1. Usage: ..."
    ;;
```

## Naming Collisions

Scripts with unique basenames across all skills get bin wrappers automatically. If a basename conflicts (e.g., `status.sh` exists in multiple skills), it won't get a wrapper. Check with:

```bash
# After bootstrap, see which scripts got wrappers
ls ~/.dataops-assistant/bin/
```
