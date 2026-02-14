# DataOps Assistant Plugin

Research internal sources (Confluence, Jira, ADO, PagerDuty, Azure) with context-managed sub-agents.

**Development**: See [docs/DEVELOPING.md](./docs/DEVELOPING.md) for conventions and known pitfalls.

---

## How This Plugin Works

**Routing rules are injected automatically** via the `UserPromptSubmit` hook on every prompt. The hook detects configured MCP servers and environment capabilities, then injects a routing table and guardrails. You don't need to memorize what tool to use.

**Skills** run in forked contexts to prevent token bloat. Each skill's `SKILL.md` contains its own usage instructions.

**Agents** are subagents invoked via Task tool with `subagent_type: "dataops-assistant:<agent-name>"`.

**Hooks** handle bootstrap, routing injection, script auto-approval, and advisor validation.

Run `/dataops-assistant:status` to check configured capabilities.

---

## Environment Setup

Skills invoke scripts via per-script wrappers in `~/.dataops-assistant/bin/`. Each bin wrapper delegates to the `run` wrapper, which handles `DATAOPS_ASSISTANT_ROOT` internally. The bootstrap hook generates everything automatically.

```bash
# Typical SKILL.md invocation
~/.dataops-assistant/bin/jira-api.sh version-list PE
```

Scripts with naming collisions (e.g., `status.sh` exists in 8 skills) don't get bin wrappers and use the `run` wrapper directly:
```bash
~/.dataops-assistant/run skills/status/scripts/status.sh
```

For ad-hoc debugging:
```bash
source ~/.dataops-assistant/plugin-env.sh
```
