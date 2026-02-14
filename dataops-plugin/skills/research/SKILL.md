---
description: "Research internal sources (Confluence, Jira, ADO, PagerDuty, Azure, Outlook) for documentation, ownership, status, infrastructure, and incidents"
allowed-tools: ["Task", "Skill", "Read", "Glob", "Grep"]
model: sonnet
context: fork
---


# Internal Research

Research internal sources using parallel Task execution. **ALWAYS wait for Task completion before proceeding.**

## Step 1: Dispatch Search Tasks (PARALLEL)

Launch relevant advisors in a **single message** - they run concurrently:

```
Task(subagent_type: "dataops-assistant:confluence-advisor", prompt: "{query}")  // docs, architecture
Task(subagent_type: "dataops-assistant:jira-advisor", prompt: "{query}")        // tickets, status
Task(subagent_type: "dataops-assistant:pagerduty-advisor", prompt: "{query}")   // incidents, on-call
```

**For ADO** (code, PRs, pipelines): Use bash scripts directly:
```bash
~/.dataops-assistant/bin/ado-repos.sh <project> [filter]
~/.dataops-assistant/bin/ado-repo-activity.sh <project> <repo> [--since YYYY-MM-DD] [--author email]
~/.dataops-assistant/bin/ado-pipelines.sh <project> [filter]
~/.dataops-assistant/bin/ado-pipeline-runs.sh <project> <pipeline-id> [--top N]
~/.dataops-assistant/bin/ado-assigned-prs-fast.sh --project <project> [user] [--status active|completed|all] [--since YYYY-MM-DD]
~/.dataops-assistant/bin/ado-reviewed-prs-fast.sh --project <project> [user] [--status active|completed|all] [--since YYYY-MM-DD]
```

**WAIT for all Tasks to complete before Step 2.**

## Step 2: Read Items (PARALLEL via Task)

From the reading plans, launch reader Tasks in a **single message**:

```
Task(subagent_type: "general-purpose", prompt: "Use /dataops-assistant:confluence-page-reader to read page {id}. Context: {query}")
Task(subagent_type: "general-purpose", prompt: "Use /dataops-assistant:jira-issue-reader to read {KEY}. Context: {query}")
Task(subagent_type: "dataops-assistant:ado-pr-reader", prompt: "{project}:{repo}:{pr} | {query}")
```

Available readers:
- `confluence-page-reader` skill - Confluence pages
- `jira-issue-reader` skill - Jira issues
- `ado-build-reader` skill - ADO builds
- `ado-pr-reader` agent - ADO pull requests (use agent directly, not via skill)
- `read-macos-outlook` skill - Outlook emails
- `read-macos-outlook-calendar` skill - Outlook calendar

**WAIT for all Tasks to complete before Step 3.**

## Step 3: External Research (if needed, PARALLEL)

For external concepts, launch research Tasks:

```
Task(subagent_type: "general-purpose", prompt: "Use /dataops-assistant:openai-research to research: {topic}")
```

**WAIT for completion.**

## Step 4: Synthesize

Only after ALL Tasks complete, output:

```markdown
## Research: {Question}

### Answer
[Direct answer]

### Key Findings
1. [Finding + source]

### Sources
- [Links]

### Confidence
**{High/Medium/Low}** - [Why]

### Gaps
- [What's missing]
```
