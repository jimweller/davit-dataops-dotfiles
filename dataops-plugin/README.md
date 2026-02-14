# DataOps Assistant Plugin

> **Status**: Incubating. Not ready for general use.

Research internal sources (Confluence, Jira, ADO, PagerDuty, Azure, AWS) with context-managed sub-agents.

## Quick Start

```bash
claude --plugin-dir /path/to/dataops-assistant-plugin
```

Run `/dataops-assistant:status` to check what's configured.

## System Requirements (other than claude, of course)

**Required**: 
- A POSIX-friendly set of tools (`bash`, `awk`, `sed`, etc. These are almost always pre-installed)
- `bun`
- `jq`
- `yq` - For skills that interact with. yaml
- `az` - Used as the auth basis for most things

**Optional (for specific skills)**:
- `steampipe` - For k8s-steampipe, azure-steampipe-query, aws-steampipe-query
- `stern` - For k8s-logs skill
- `pinentry-mac` - To get prompted for aws-vault codes (or other inputs, equiv for windows should work too)

## Configuration

### Environment Variables

Add to your `.zprofile` or equivalent:

```shell
# Required
export MCG_EMAIL="your.email@mcg.com"
export ATLASSIAN_API_TOKEN="YOUR_TOKEN"
export ATLASSIAN_BASE_URL="https://mcghealth.atlassian.net/"
export ATLASSIAN_EMAIL="your.email@mcg.com"
export AZURE_DEVOPS_ORG="https://mcgsead.visualstudio.com/"

# Optional
export OPENAI_API_KEY="YOUR_KEY"          # For openai-research skill
export PAGERDUTY_API_TOKEN="YOUR_TOKEN"   # For PagerDuty skills
export SONARQUBE_BASE_URL="https://..."   # For sonarqube-query skill
export SONARQUBE_USER_TOKEN="YOUR_TOKEN"  # For sonarqube-query skill
```

### MCP Servers

Add to your Claude Code MCP config (names must match exactly):

```json
{
  "azure-devops": {
    "type": "stdio",
    "command": "npx",
    "args": ["@azure-devops/mcp", "mcgsead"]
  },
  "atlassian": {
    "type": "http",
    "url": "https://mcp.atlassian.com/v1/mcp"
  },
  "pagerduty": {
    "type": "http",
    "url": "https://mcp.pagerduty.com/mcp",
    "headers": {
      "Authorization": "Token ${PAGERDUTY_API_TOKEN}"
    }
  }
}
```
## Skill-Specific Setup

Some skills require additional configuration:

| Skill | Setup Guide |
|-------|-------------|
| k8s-steampipe, k8s-logs | [docs/k8s-setup.md](./docs/k8s-setup.md) |
| aws-steampipe-query | [docs/aws-setup.md](./docs/aws-setup.md) |

## Available Skills

See [CLAUDE.md](./CLAUDE.md) for the full list of skills and agents.

Common ones:
- `/dataops-assistant:research` - Multi-source internal research
- `/dataops-assistant:openai-research` - Web research (current info, docs)
- `/dataops-assistant:jira-issue-reader` - Read a Jira issue
- `/dataops-assistant:confluence-page-reader` - Read a Confluence page
- `/dataops-assistant:k8s-steampipe` - Query Kubernetes clusters
- `/dataops-assistant:aws-steampipe-query` - Query AWS accounts

## Example

```
/dataops-assistant:research what have I been working on the past 2 weeks? Summarize, provide references. Then frame actions in GTD at the end.
```

> Note: On macOS with Outlook, research can read your email. Expect ~15 minutes for comprehensive research.

## Help

Ask Terence if things don't work. Or fix it yourself and send a PR.
