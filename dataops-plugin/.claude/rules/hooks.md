---
paths:
  - "hooks/**"
  - ".claude-plugin/plugin.json"
---
# Hook Development Rules

## Hook Types

Hooks are registered in `.claude-plugin/plugin.json` under event triggers:

| Event | When it runs | Use for |
|-------|-------------|---------|
| `SessionStart` | Once at session start | Bootstrap env, sync caches |
| `UserPromptSubmit` | Before every response | Inject routing rules, context |
| `PreToolUse` | Before a tool call | Approve/block specific tools |
| `SubagentStop` | After a subagent completes | Validate agent output |

## Current Hooks

- **bootstrap.sh** (SessionStart) — Sets `DATAOPS_ASSISTANT_ROOT`, generates bin wrappers
- **sync-arch-memory-hook.sh** (SessionStart) — Syncs architect memory repos
- **inject-routing-rules.sh** (UserPromptSubmit) — Injects routing table into context
- **approve-api-scripts.sh** (PreToolUse) — Approves known API script executions
- **require-advisor-tool-calls.sh** (SubagentStop) — Blocks advisor agents that made zero tool calls (anti-hallucination)

## Performance

`UserPromptSubmit` hooks run on **every prompt**. Keep them fast:
- No subprocess calls where possible (use file checks, env var checks)
- Cache MCP server detection results within the script
- `inject-routing-rules.sh` uses `jq` to read MCP configs once, then bash checks

## Writing a New Hook

1. Create `hooks/<name>.sh` with a shebang (`#!/bin/bash` or `#!/usr/bin/env bash`)
2. Register it in `.claude-plugin/plugin.json` under the appropriate event
3. Output goes to Claude's context — keep it concise and actionable
4. Use stderr for diagnostics that shouldn't enter Claude's context
5. Run `./tests/lint.sh` to verify the hook is discoverable

## Conditional Routing Rules

In `inject-routing-rules.sh`, routing rules are conditionally emitted based on capability flags:

```bash
# Fast capability detection (no subprocesses)
HAS_ATLASSIAN=false
has_mcp "atlassian" "$configured_mcps" && HAS_ATLASSIAN=true

# Only emit rules when the backend is available
if $HAS_ATLASSIAN; then
    echo "| Jira search | \`jira-advisor\` agent |"
fi
```

When adding a new skill with an external dependency, add it behind the appropriate capability guard. If it needs a new guard, add detection in the capability section at the top.

## Anti-Hallucination Pattern

The `require-advisor-tool-calls.sh` hook prevents advisor agents (jira-advisor, confluence-advisor, pagerduty-advisor) from returning fabricated results by checking that they actually made tool calls. If a new advisor agent is added, register it in this hook.
