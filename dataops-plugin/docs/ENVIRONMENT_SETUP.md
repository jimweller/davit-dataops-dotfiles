# Environment Setup: DATAOPS_ASSISTANT_ROOT

## The Problem

SKILL.md files need a reliable way to invoke scripts. The original approach used `$DATAOPS_ASSISTANT_ROOT` directly:

```bash
# Old pattern (no longer used in SKILL.md files)
"$DATAOPS_ASSISTANT_ROOT/skills/ado-query/scripts/ado-projects.sh"
```

This required the variable in Claude's bash environment. The intended mechanism is:

1. SessionStart hook writes `export DATAOPS_ASSISTANT_ROOT=...` to `$CLAUDE_ENV_FILE`
2. Claude Code sources this file before each Bash tool call
3. The variable is available when Claude runs skill commands

However, **plugin-defined SessionStart hooks don't reliably receive `CLAUDE_ENV_FILE`** (known Claude Code bug (anthropics/claude-code#15840, regression of fixed #11649)). When the variable is missing, Claude can't call any skill scripts.

## The Solution

The bootstrap hook (`hooks/bootstrap.sh`) writes to **both** locations:

1. **`$CLAUDE_ENV_FILE`** (when available) - the proper mechanism
2. **`~/.dataops-assistant/plugin-env.sh`** (always) - fallback for when CLAUDE_ENV_FILE doesn't work

`CLAUDE.md` instructs Claude to source the fallback file when the variable is missing:

```bash
[[ -z "${DATAOPS_ASSISTANT_ROOT:-}" ]] && source ~/.dataops-assistant/plugin-env.sh
```

## Current Pattern: Bin Wrappers

Bootstrap now generates per-script wrappers in `~/.dataops-assistant/bin/`. SKILL.md files use these wrappers instead of `$DATAOPS_ASSISTANT_ROOT` directly:

```bash
# Current — SKILL.md files use bin wrappers
~/.dataops-assistant/bin/ado-projects.sh

# The run wrapper handles DATAOPS_ASSISTANT_ROOT internally
~/.dataops-assistant/run skills/status/scripts/status.sh
```

Individual scripts (`.sh` files in `skills/*/scripts/`) use relative paths from their own location:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
```

Neither SKILL.md files nor scripts reference `$DATAOPS_ASSISTANT_ROOT` directly — the bin/run wrappers handle it.

## References

- Claude Code Hooks: https://docs.claude.com/en/docs/claude-code/hooks
- [#11649](https://github.com/anthropics/claude-code/issues/11649): Plugin SessionStart hooks don't receive CLAUDE_ENV_FILE (fixed Dec 2025, regressed)
- [#15840](https://github.com/anthropics/claude-code/issues/15840): CLAUDE_ENV_FILE not provided to SessionStart hooks (open, Feb 2026)
