# Plugin Development Rules

These rules apply when developing the DataOps Assistant plugin itself (not when using it as a consumer).

## Adding a New Skill

1. Create `skills/<name>/SKILL.md` with usage instructions and YAML frontmatter
2. Add routing rule to `hooks/inject-routing-rules.sh` (use conditional guards if external dependency)
3. If the skill has scripts, place them in `skills/<name>/scripts/`
4. Run `./tests/lint.sh` to verify structural integrity

## Adding a New Agent

**Plugin agents** (ship to consumers) go in `agents/`:
1. Create `agents/<name>.md` with the agent prompt
2. Add routing rule to `hooks/inject-routing-rules.sh`
3. If the agent needs anti-hallucination enforcement, add it to `hooks/require-advisor-tool-calls.sh`

**Project agents** (dev tools, don't ship) go in `.claude/agents/`:
1. Create `.claude/agents/<name>.md` with the agent prompt
2. Do NOT add to CLAUDE.md or routing rules (these are dev-only)
3. Reference in `.claude/rules/` or `docs/DEVELOPING.md` instead

## Dev-Only Agents

These project-level agents are available when developing in this repo:

| Agent | Purpose |
|-------|---------|
| `skill-reviewer` | Audit SKILL.md files against project conventions |

Invoke via: `Task(subagent_type: "skill-reviewer", prompt: "Review skills/ado-query/SKILL.md")`

## Script Path Conventions

Scripts must use `BASH_SOURCE` for path derivation, never `DATAOPS_ASSISTANT_ROOT`:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
```

SKILL.md files invoke scripts via bin wrappers (single unambiguous path):
```bash
~/.dataops-assistant/bin/jira-api.sh version-list PE
```

For scripts with naming collisions (e.g., `status.sh`), use the run wrapper:
```bash
~/.dataops-assistant/run skills/status/scripts/status.sh
```

Bootstrap auto-generates bin wrappers by scanning `skills/*/scripts/*.sh`. Scripts named `*-common.sh`, `bootstrap.sh`, or with duplicate basenames don't get wrappers.

## Bash Pitfalls

ADO project names contain spaces (e.g., "Data Science"). When iterating over lists from `jq -r`, always set `IFS=$'\n'`:

```bash
old_IFS="${IFS}"
IFS=$'\n'
for item in $(echo "$json_array" | jq -r '.[]'); do
    # "Data Science" stays as one token
    ...
done
IFS="${old_IFS}"
```

Never use bare `for x in $(jq -r '.[]')` without newline IFS.

## Technology Choices

- **Bash** is the default for skills wrapping CLI tools (`az`, `steampipe`, `jq`)
- **Bun/JavaScript** is available (already a dependency for Jira markdown). Use for complex string handling, parallel coordination with shared state, or when bash quoting/IFS keeps causing bugs.

## Naming Conventions

Plugin agents and skills are namespaced. Always use the full prefix:
- Agents: `dataops-assistant:<agent-name>` (e.g., `dataops-assistant:jira-advisor`)
- Skills: `/dataops-assistant:<skill-name>` (e.g., `/dataops-assistant:jira-issue-reader`)

Never reference plugin agents or skills by bare name in CLAUDE.md or routing rules. Bare names are only for project-level items (`.claude/agents/`, `.claude/skills/`).

## Documentation Sync

The root `CLAUDE.md` is dev-only (plugins don't load CLAUDE.md for consumers). The `UserPromptSubmit` hook is the primary delivery mechanism for consumer guidance. When you change any of these, keep them in sync:

- `hooks/inject-routing-rules.sh` — routing table, MCP warnings, guardrails (consumers see this)
- `CLAUDE.md` — plugin architecture, environment setup (devs only)
- `docs/DEVELOPING.md` — human-readable contributor guide
