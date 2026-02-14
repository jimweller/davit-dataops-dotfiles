---
description: "Draft Azure DevOps PR content to a local file for review. Does NOT create PRs."
allowed-tools: ["Bash", "Read", "Write", "Glob", "Grep"]
model: opus
context: fork
---

# ADO PR Draft

Draft Azure DevOps PR content to a local markdown file for review before publishing.

## Workflow

1. **Read the PR writing guide** from `assets/PR_WRITING_GUIDE.md`
2. **Understand the request** - What repo? What branch? What changes?
3. **Gather context** - Read relevant files, understand the diff
4. **Draft content** - Write title and description following the guide
5. **Create frontmatter** - Include metadata for publishing
6. **Write to file** - Save to `.ado-drafts/{timestamp}-{slug}.md`
7. **Return instructions** - Tell user how to review and publish

**This skill NEVER touches Azure DevOps.** It only creates local files.

---

## FIRST: Read the Style Guide

Before drafting any PR, read:
```
Read: skills/ado-pr-draft/assets/PR_WRITING_GUIDE.md
```

This guide contains title conventions, description structure, formatting rules, and examples.

---

## Draft File Format

```yaml
---
ado_draft_version: "1"
action: create_pr
project: "ProjectName"           # Required
repository: "repo-name"          # Required
source_branch: "feature/branch"  # Required
target_branch: "main"            # Required (usually main or master)
title: "PR title here"           # Required
is_draft: true                   # Always true
jira_issue: "ML-1234"            # Optional - linked Jira issue
created_at: "2025-02-04T14:30:00Z"
status: draft                    # draft | published
published_url: null              # Set after publish
published_pr_id: null            # Set after publish
---

[PR description follows in markdown]
```

**File naming:** `.ado-drafts/{timestamp}-pr-{slug}.md`
- Timestamp: `YYYYMMDD-HHMMSS`
- Slug: brief description (max 30 chars)
- Example: `20250204-143022-pr-add-retry-logic.md`

---

## Creating Draft Files

Always create the `.ado-drafts/` directory first:

```bash
mkdir -p .ado-drafts
```

Generate filename:
```bash
timestamp=$(date +%Y%m%d-%H%M%S)
slug="add-retry-logic"  # derived from title/branch
filename=".ado-drafts/${timestamp}-pr-${slug}.md"
```

---

## PR Description Structure

Follow the guide in `assets/PR_WRITING_GUIDE.md`. Quick reference:

```markdown
> __See [ML-XXXX](https://mcghealth.atlassian.net/browse/ML-XXXX)__

## What's here

[Brief explanation of the change and WHY]

- Key change 1
- Key change 2

## How to test it

[Testing instructions - keep terse if obvious]
```

**Key rules:**
- Explain "why" not just "what"
- Use `backticks` for code/commands
- Don't enumerate files (visible in diff)
- Don't re-state JIRA verbatim (just link)
- Conversational tone, be direct

---

## Title Conventions

| Prefix | When to Use | Example |
|--------|-------------|---------|
| `Bug fix:` | Fixing broken functionality | `Bug fix: Enable job retries` |
| `Temporary fix:` | Hack or workaround | `Temporary fix: CPU delay` |
| `[TICKET-ID] -` | When ticket is primary context | `ML-889 - Add payload capture` |
| None | Features, refactors, bumps | `Bump workflow to v0.1.5` |

---

## Examples

### Example 1: Feature PR

**User request:** "Draft a PR for my feature/add-retry-logic branch in cms-service"

**Draft file:** `.ado-drafts/20250204-143022-pr-add-retry-logic.md`

```yaml
---
ado_draft_version: "1"
action: create_pr
project: "clinical-matching"
repository: "cms-service"
source_branch: "feature/add-retry-logic"
target_branch: "main"
title: "Add retry logic for transient API failures"
is_draft: true
jira_issue: "ML-1234"
created_at: "2025-02-04T14:30:22Z"
status: draft
published_url: null
published_pr_id: null
---

> __See [ML-1234](https://mcghealth.atlassian.net/browse/ML-1234)__

## What's here

Adds exponential backoff retry logic for calls to the external matching API. Previously, transient network errors would cause immediate failures. Now we retry up to 3 times with increasing delays.

- Retry wrapper for HTTP client with configurable max attempts
- Exponential backoff: 1s, 2s, 4s delays
- Circuit breaker to avoid hammering a down service

## How to test it

- `make test` - unit tests including retry scenarios
- `make integration-test` - tests against mock API with injected failures
```

### Example 2: Bug Fix PR

**User request:** "Draft a PR for the selector fix on bug/api-routing"

**Draft file:** `.ado-drafts/20250204-150000-pr-fix-api-routing.md`

```yaml
---
ado_draft_version: "1"
action: create_pr
project: "clinical-matching"
repository: "cms-service"
source_branch: "bug/api-routing"
target_branch: "main"
title: "Bug fix: API routing to wrong pods"
is_draft: true
jira_issue: "ML-1285"
created_at: "2025-02-04T15:00:00Z"
status: draft
published_url: null
published_pr_id: null
---

> __See [ML-1285](https://mcghealth.atlassian.net/browse/ML-1285)__

## What's here

Adds `app.kubernetes.io/component: api` label to API deployment and service selectors to distinguish API pods from harness pods. Previously, the ingress was routing some requests to harness pods.

## How to test it

- `make test` - run unit tests including new selector tests
- `make dv-test` - full deployment verification
```

---

## Output

After creating the draft file, respond with:

```
Draft saved to: .ado-drafts/{filename}

Next steps:
1. Review the draft: cat .ado-drafts/{filename}
2. Edit if needed
3. Publish: /dataops-assistant:ado-pr-publish .ado-drafts/{filename}
```

---

## Validating Drafts

After creating a draft, validate it:

```bash
~/.dataops-assistant/run skills/ado-pr-draft/scripts/validate-draft.js .ado-drafts/{filename}
```

This checks:
- All required frontmatter fields are present
- `project` is set (CRITICAL - MCP calls fail without it)
- Branch names don't have `refs/heads/` prefix (added during publish)
- Body has content and follows style guide

---

## Rules

1. **ALWAYS read PR_WRITING_GUIDE.md first** - Follow the conventions
2. **NEVER use /tmp/** - All drafts go to `.ado-drafts/`
3. **NEVER touch Azure DevOps** - This skill only creates local files
4. **Include all required frontmatter** - project, repository, branches, title
5. **Follow title conventions** - Use appropriate prefix
6. **Explain the "why"** - Not just what changed, but why it matters
7. **Avoid AI-smelling formatting** - Use `->` not `→`, avoid excessive emoji, keep it natural
