# CLAUDE_PLUGIN_ROOT Knowledge Document

## Overview

This document captures key learnings about `CLAUDE_PLUGIN_ROOT`, `CLAUDE_ENV_FILE`, and the patterns used in this plugin for referencing scripts from skills and hooks.

## What CLAUDE_PLUGIN_ROOT Is

`CLAUDE_PLUGIN_ROOT` is a **variable substitution** provided by the Claude Code plugin system. It is used in the plugin manifest (`plugin.json`) to reference hook scripts relative to the plugin directory.

### What It's Used For

**ONLY for hook commands in plugin.json**:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/bootstrap.sh",
            "timeout": 5,
            "description": "Bootstrap plugin environment"
          }
        ]
      }
    ]
  }
}
```

**Key characteristics:**
- It's a **literal string substitution** performed by Claude Code before executing the hook
- It's replaced with the absolute path to the plugin directory
- It works **ONLY in the plugin.json manifest**
- The substitution happens at the Claude Code infrastructure level, not in bash

## What CLAUDE_PLUGIN_ROOT Is NOT

`CLAUDE_PLUGIN_ROOT` is **NOT**:

1. **Not a bash environment variable** - You cannot reference it as `$CLAUDE_PLUGIN_ROOT` in bash scripts
2. **Not available in skill contexts** - Skills run in forked contexts and don't have access to this variable
3. **Not available in agent contexts** - Agents (subagents) have completely separate environments
4. **Not available in regular bash commands** - Even in the main context, this is not exported to bash

### Why ${CLAUDE_PLUGIN_ROOT} Doesn't Work in Bash Commands

Consider this example:

```bash
# This WILL NOT WORK:
bash "${CLAUDE_PLUGIN_ROOT}/skills/azure-steampipe-query/scripts/bootstrap.sh"

# Why it fails:
# 1. Bash sees the literal string "${CLAUDE_PLUGIN_ROOT}"
# 2. Bash tries to expand it as a variable
# 3. CLAUDE_PLUGIN_ROOT is not set in the bash environment
# 4. Result: empty string, leading to "bash: /skills/...: No such file or directory"
```

The variable substitution in `plugin.json` happens **before** the command reaches bash, so by the time bash runs the command, `${CLAUDE_PLUGIN_ROOT}` has already been replaced. But in subsequent bash commands (like in skills), this substitution doesn't happen.

## The Bootstrap + CLAUDE_ENV_FILE Pattern

To make the plugin root available to all contexts (main, skills, agents), this plugin uses the bootstrap pattern:

### Step 1: Bootstrap Hook (SessionStart)

**File**: `/Users/terence.kent/code/dataops/dataops-assistant-plugin/hooks/bootstrap.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# Derive plugin root from this script's location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Export to CLAUDE_ENV_FILE so it's available in all subsequent bash commands
# (including Skills, forked contexts, and subagents)
if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
    echo "export DATAOPS_ASSISTANT_ROOT=\"$PLUGIN_ROOT\"" >> "$CLAUDE_ENV_FILE"
fi

exit 0
```

**What this does:**
1. Uses `BASH_SOURCE` to find its own location (absolute path)
2. Derives the plugin root by going up one directory from `hooks/`
3. Writes an export statement to `CLAUDE_ENV_FILE`
4. `CLAUDE_ENV_FILE` is a special file whose contents are sourced before every bash command

### Step 2: Bin Wrappers (Current Pattern)

Bootstrap generates per-script wrappers in `~/.dataops-assistant/bin/`. SKILL.md files invoke scripts through these wrappers rather than using `$DATAOPS_ASSISTANT_ROOT` directly:

```bash
# Current pattern — SKILL.md files use bin wrappers
~/.dataops-assistant/bin/steampipe-query.sh "SELECT ..."

# For scripts with naming collisions, use the run wrapper
~/.dataops-assistant/run skills/status/scripts/status.sh
```

The bin wrappers delegate to a `run` wrapper, which internally sources `DATAOPS_ASSISTANT_ROOT` and resolves paths. This gives SKILL.md files a single unambiguous invocation path without depending on environment variables.

**Why the indirection:**
- `DATAOPS_ASSISTANT_ROOT` is still exported to `CLAUDE_ENV_FILE` during SessionStart
- The `run` wrapper uses it internally to resolve script paths
- But SKILL.md files never reference `$DATAOPS_ASSISTANT_ROOT` directly — bin wrappers abstract it away
- This avoids failures when `CLAUDE_ENV_FILE` is not available (known Claude Code bug)

## Implementation Pattern in This Plugin

### Directory Structure

```
dataops-assistant-plugin/
├── .claude-plugin/
│   └── plugin.json              # Uses ${CLAUDE_PLUGIN_ROOT} for hooks
├── hooks/
│   ├── bootstrap.sh             # Exports DATAOPS_ASSISTANT_ROOT to CLAUDE_ENV_FILE
│   ├── inject-routing-rules.sh
│   └── approve-api-scripts.sh
└── skills/
    ├── azure-steampipe-query/
    │   ├── SKILL.md            # References $DATAOPS_ASSISTANT_ROOT
    │   └── scripts/
    │       ├── bootstrap.sh    # One-time setup script
    │       └── steampipe-query.sh
    └── aws-steampipe-query/
        ├── SKILL.md            # References $DATAOPS_ASSISTANT_ROOT
        └── scripts/
            ├── bootstrap.sh    # One-time setup script
            └── aws-steampipe.sh
```

### Naming Convention

**Plugin-specific environment variable**: `DATAOPS_ASSISTANT_ROOT`
- Named after the plugin (`dataops-assistant`)
- Follows the pattern: `<PLUGIN_NAME>_ROOT` (with dashes converted to underscores)
- Distinct from `CLAUDE_PLUGIN_ROOT` to avoid confusion
- Makes it clear this is a plugin-specific variable, not a Claude Code system variable

### Script Patterns

**SKILL.md files** use bin wrappers (never `$DATAOPS_ASSISTANT_ROOT` directly):
```bash
~/.dataops-assistant/bin/some-script.sh arg1 arg2
```

**Scripts that are called by hooks (in plugin.json)**:
```json
{
  "command": "${CLAUDE_PLUGIN_ROOT}/hooks/bootstrap.sh"
}
```

**Bootstrap scripts for complex skills**:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Derive paths from script location (not from DATAOPS_ASSISTANT_ROOT)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(dirname "$SCRIPT_DIR")"

# Use relative paths from here
SHIPPED_CONFIG="$SKILL_ROOT/config/something.yaml"
```

**Why bootstrap scripts derive paths**: Bootstrap scripts may be run manually by users (outside Claude context), so they can't rely on environment variables. They use `BASH_SOURCE` to find their own location and derive paths from there.

## Key Takeaways

1. **Use `${CLAUDE_PLUGIN_ROOT}` ONLY in plugin.json** — never in bash scripts
2. **SKILL.md files use bin wrappers** (`~/.dataops-assistant/bin/<script>.sh`) — never `$DATAOPS_ASSISTANT_ROOT` directly
3. **`$DATAOPS_ASSISTANT_ROOT` is used internally** by the `run` wrapper to resolve script paths
4. **Bootstrap pattern is essential** — generates bin wrappers and exports `DATAOPS_ASSISTANT_ROOT` to `CLAUDE_ENV_FILE`
5. **CLAUDE_ENV_FILE is the bridge** — makes variables available across all contexts
6. **Bootstrap scripts are self-contained** — derive paths from their own location using `BASH_SOURCE`

## Common Mistakes

### Mistake 1: Using ${CLAUDE_PLUGIN_ROOT} in Bash

```bash
# WRONG - will not work
bash "${CLAUDE_PLUGIN_ROOT}/skills/something/bootstrap.sh"

# CORRECT - use bin wrapper
~/.dataops-assistant/bin/something.sh
```

### Mistake 2: Using $DATAOPS_ASSISTANT_ROOT in SKILL.md

```bash
# WRONG - fragile, depends on env var availability
"$DATAOPS_ASSISTANT_ROOT/skills/something/scripts/script.sh"

# CORRECT - use bin wrapper
~/.dataops-assistant/bin/script.sh
```

### Mistake 3: Relying on Environment Variables in Bootstrap Scripts

```bash
# WRONG - won't work when run manually
SHIPPED_CONFIG="$DATAOPS_ASSISTANT_ROOT/config/file.yaml"

# CORRECT - derive from script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(dirname "$SCRIPT_DIR")"
SHIPPED_CONFIG="$SKILL_ROOT/config/file.yaml"
```

### Mistake 4: Forgetting the Bootstrap Hook

If you don't have a SessionStart hook that exports to CLAUDE_ENV_FILE, the plugin-specific variable won't be available in any context.

## References

**Implementation files**:
- `/Users/terence.kent/code/dataops/dataops-assistant-plugin/.claude-plugin/plugin.json` - Hook definitions using ${CLAUDE_PLUGIN_ROOT}
- `/Users/terence.kent/code/dataops/dataops-assistant-plugin/hooks/bootstrap.sh` - Bootstrap that exports DATAOPS_ASSISTANT_ROOT
- `/Users/terence.kent/code/dataops/dataops-assistant-plugin/skills/azure-steampipe-query/SKILL.md` - Example skill using $DATAOPS_ASSISTANT_ROOT
- `/Users/terence.kent/code/dataops/dataops-assistant-plugin/skills/azure-steampipe-query/scripts/bootstrap.sh` - Example bootstrap script deriving paths from BASH_SOURCE

**Schema reference**:
- `/Users/terence.kent/code/dataops/dataops-assistant-plugin/.claude-plugin/plugin.schema.json` - Line 101: "Use ${CLAUDE_PLUGIN_ROOT} for plugin paths"
