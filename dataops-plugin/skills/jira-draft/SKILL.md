---
description: "Draft Jira issue content to a local file for review. Does NOT create issues."
allowed-tools: ["Bash", "Read", "Write", "Glob"]
model: opus
context: fork
---

# Jira Draft

Draft Jira issue content to a local markdown file for review before publishing.

## Workflow

1. **Understand the request** - What issue type? What project? What content?
2. **Identify relationships** - What issues should be linked? (blocks, is-blocked-by, relates-to)
3. **Draft content** - Write styled markdown following the Content and Style guides below
4. **Create frontmatter** - Include metadata for publishing
5. **Write to file** - Save to `.jira-drafts/{timestamp}-{slug}.md`
6. **Return instructions** - Tell user how to review and publish

**This skill NEVER touches Jira.** It only creates local files.

---

## Draft File Format

**IMPORTANT: Email domain is @mcg.com** (not @mcghealth.com - that's just the Atlassian subdomain)

```yaml
---
jira_draft_version: "1"
action: create          # create | update | comment
project: PE             # Required for create
issue_type: Story       # Story | Task | Bug | Epic | Sub-task (create only)
summary: "Issue title"  # Create only
target_issue: PE-1234   # Required for update/comment
assignee: user@mcg.com  # Optional, email address (resolved to account ID on publish)
parent: PE-100          # Optional, parent epic key (for stories/tasks under epics)
components:             # Optional, list of component names
  - Backend
  - API
labels: []              # Optional
fix_version: "2025.1.0" # Optional, version name (update/comment actions, must exist in project)
links:                  # Optional, applied after create
  - type: blocks
    target: PE-456
  - type: relates-to
    target: PE-789
created_at: "2025-02-03T14:30:00Z"
status: draft           # draft | published
published_issue: null   # Set after publish
---

[Markdown content follows]
```

**File naming:** `.jira-drafts/{timestamp}-{slug}.md`
- Timestamp: `YYYYMMDD-HHMMSS`
- Slug: lowercase summary with hyphens (max 30 chars)
- Example: `20250203-143022-openai-instance.md`

---

## Creating Draft Files

Always create the `.jira-drafts/` directory if it doesn't exist:

```bash
mkdir -p .jira-drafts
```

Generate filename:
```bash
timestamp=$(date +%Y%m%d-%H%M%S)
slug=$(echo "summary here" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | cut -c1-30)
filename=".jira-drafts/${timestamp}-${slug}.md"
```

---

## Content Principles

Write issues with **clarity and actionability**. Every issue should answer: "What does done look like?" or "What questions need answering?"

### Always Start with CONTEXT

Open every issue with a CONTEXT block explaining:
- **Historical background** or current state ("Forever ago, we set up X...")
- **Why this matters now** - the pain point, urgency, or business driver
- **References** to related issues for deeper context (inline mentions, not redundant links)

```markdown
:::context
Forever ago, we set up the initial OpenAI instance for DataSci (MAT-28).
Today they still use that single instance for everything. That works for
today but that isn't going to fit the upcoming usage with the CMS service.

The CMS service will need to make lots and lots of OpenAI calls and we'll
have special monitoring needs around those instances (both in cost, usage,
and availability). Things we don't care about today.
:::
```

The reader should immediately understand the "why" before diving into requirements.

---

## Structural Pattern: Requirements + Questions

**Default approach for most issues.** Use structured sections to define the work:

```markdown
:::context
Over the past few months, it became apparent that we need to know when Nolio
release processes fail. The only way to determine if a release fails is to
check Nolio's UI manually.
:::

## The Work Here

Answer the questions:

1. Are errors in Nolio processes monitored today? Like, some error log pattern rules?
2. Are Nolio logs accessible anywhere other than the Nolio server (DataDog, etc.)?
3. What would it take to add alerting for Nolio process failures?
```

**Common section patterns:**
- "What We Have Today" / "What We Need" / "What Needs To Be Figured Out"
- "The Work Here" + numbered questions or requirements
- "Questions to Answer" for spikes/research
- "Out of Scope" to clarify boundaries

This works for: infrastructure, platform tasks, research, investigations, operational work, most engineering tasks.

---

## When NOT to Use Checkbox Acceptance Criteria

**Almost always.** Checkbox-style AC is rarely the right choice:

- **Infrastructure/platform work** - use requirements sections
- **Research/spikes** - use questions to answer
- **Operational tasks** - use clear deliverables
- **Most engineering work** - the description itself defines done
- **Sub-tasks** - parent defines scope
- **Epics** - too broad; children define specifics

**Never write AC like this:**
- "Code is well-tested" (vague)
- "Performance is acceptable" (unmeasurable)
- "Documentation is updated" (implied)
- "Solution is scalable" (meaningless)
- "Error handling is robust" (fluff)

If you find yourself writing vague criteria to fill an AC section, **delete the section**. The CONTEXT + requirements structure is clearer.

---

## Exception: User-Facing Feature AC

**Rare case.** Only use checkbox AC when ALL of these apply:
1. User-facing feature with specific behaviors
2. Multiple distinct, verifiable outcomes
3. "Done" would genuinely be ambiguous without explicit criteria

```markdown
:::context
Users see generic "Something went wrong" when login fails. Need specific messages.
:::

## What Changes

Show specific error messages when login fails.

## Acceptance Criteria

- [ ] Wrong password shows "Incorrect email or password"
- [ ] Locked account shows lockout time remaining
- [ ] 5xx errors show "Unable to sign in" with retry suggestion
```

**Even here, each criterion must be:**
- Observable by someone else
- Verifiable without subjective judgment
- Not restating the work itself

---

## Issue Relationships: Links vs. Mentions

### Use First-Class Jira Links for Dependencies

Links belong in Jira's metadata panel, not cluttering the description prose.

| Relationship | Link Type | When to Use |
|--------------|-----------|-------------|
| This blocks other work | `blocks` | Feature must ship before downstream work can start |
| This depends on other work | `is-blocked-by` | Can't start until dependency is complete |
| Related context | `relates-to` | Same feature area, useful cross-reference |
| Duplicate | `duplicates` | Close as duplicate, link to canonical issue |
| This clones other work | `clones` | This issue is a copy/clone of another |
| This is cloned by other work | `is-cloned-by` | Another issue is a copy/clone of this one |
| This causes other work | `causes` | This issue directly causes/results in another (Cloud only) |
| This is caused by other work | `is-caused-by` | Another issue directly causes this one (Cloud only) |

**Note:** First 4 types (Relates, Duplicates, Blocks, Cloners) work in all Jira versions. Causes is Jira Cloud extended. Other Cloud types (implements, reviews, product discovery) and custom types are not supported.

### Determining Link Types

When the user wants to relate issues, **determine the link type automatically when context is clear**, or **ask the user** when ambiguous:

**Auto-determine when:**
- User says "this blocks X" -> use `blocks`
- User says "this is blocked by X" or "depends on X" -> use `is-blocked-by`
- User says "this is a duplicate of X" -> use `duplicates`
- User says "related to X" or just mentions an issue in context -> use `relates-to`
- Creating a follow-up task from another issue -> use `is-caused-by` (if available) or `relates-to`

**Ask the user when:**
- User just says "link to PE-1234" without specifying relationship
- Relationship could reasonably be interpreted multiple ways
- User mentions multiple potential link types

**When asking, present options like:**
```
How should this issue be linked to PE-1234?
1. This issue blocks PE-1234 (blocks)
2. This issue is blocked by PE-1234 (is-blocked-by)
3. Related context only (relates-to)
4. This is a duplicate of PE-1234 (duplicates)
```

**Store links in frontmatter** - they'll be added after issue creation:
```yaml
links:
  - type: blocks
    target: PE-456
  - type: is-blocked-by
    target: DEPENDENCY-789
```

### Use Inline Mentions for Background Context

Inline mentions (`PROJ-123`) are for **casual references** that don't imply dependency:

```markdown
:::context
Various teams need HTTPS ingress solutions and no shared central offering
exists today. Teams have set up their own Azure resources, leading to a
poor and unsustainable situation (see PE-2393).
:::
```

**Don't duplicate:** If you mention an issue in the description AND it's a real dependency, add it to the `links` frontmatter but keep the inline mention minimal.

---

## Markdown Style Guide

### Context Block

```markdown
:::context
Explain the background and why this issue exists.
Multiple paragraphs are supported.
:::
```

Renders as a single-cell table with a purple CONTEXT lozenge.

### Headings

```markdown
## Major Section       (bold + grey)
### Sub-section        (bold + grey)
#### Question/Action   (bold + blue)
```

### Status Lozenges

```markdown
{status:UPDATE 2025-01-29:purple}
{status:BLOCKED:red}
{status:IN PROGRESS:blue}
{status:DONE:green}
{status:WAITING:yellow}
{status:INFO:neutral}
```

### Text Formatting

```markdown
**bold text**
*italic text*
`code text`
[link text](https://example.com)
```

### Lists and Tables

```markdown
- Bullet item
1. Numbered item

| Header 1 | Header 2 |
|----------|----------|
| Cell 1   | Cell 2   |
```

### Blockquotes

```markdown
> This is a quoted section.
> Multiple lines are combined.
```

### Horizontal Rules

```markdown
---
```

### Jira Issue Keys

In the **published Jira content**, plain issue keys auto-convert to inline cards:

```markdown
See PE-1234 for details.
```

**However, in draft files** (which are markdown), always use full links so the user can click to verify references before publishing:

```markdown
See [PE-1234](https://mcghealth.atlassian.net/browse/PE-1234) for details.
```

The publish script will convert these back to plain keys for Jira's auto-linking.

### Azure DevOps PR References

When referencing ADO pull requests, use the format `{repo-name}#PR{number}` as the link text:

```markdown
See [my-repo#PR1234](https://dev.azure.com/org/project/_git/my-repo/pullrequest/1234) for the implementation.
```

This format:
- Clearly identifies the repo and PR number at a glance
- Provides a clickable link to verify before publishing
- Follows the `repo#PR{n}` convention familiar from GitHub/GitLab

---

## Examples

### Example 1: Create a Story (Requirements Pattern)

**User request:** "Create a story for setting up a dedicated OpenAI instance for CMS, assign to john@company.com under epic PE-100"

**Draft file:** `.jira-drafts/20250203-143022-dedicated-openai-cms.md`

```yaml
---
jira_draft_version: "1"
action: create
project: PE
issue_type: Story
summary: "Set up dedicated OpenAI instance for CMS service"
assignee: john@company.com
parent: PE-100
components:
  - Platform
labels: []
links:
  - type: relates-to
    target: MAT-28
created_at: "2025-02-03T14:30:22Z"
status: draft
published_issue: null
---

:::context
Forever ago, we set up the initial OpenAI instance for DataSci (MAT-28). Today
they still use that single instance for everything. That works for today but
that isn't going to fit the upcoming usage with the CMS service.

The CMS service will need to make lots and lots of OpenAI calls and we'll have
special monitoring needs (cost, usage, availability) that we don't care about today.
:::

## What We Have Today

- Single OpenAI instance shared across all DataSci workloads
- No usage monitoring or cost attribution
- No availability alerting

## What We Need

1. Dedicated OpenAI instance for CMS service workloads
2. Cost monitoring with attribution to CMS vs other consumers
3. Usage dashboards showing token consumption by model
4. Availability alerting when API errors exceed threshold

## What Needs To Be Figured Out

- Quota limits: What TPM/RPM do we need for CMS projected load?
- Network path: Does CMS service need private endpoint or public OK?
- Failover: Do we need secondary instance in different region?
```

### Example 2: Update an Existing Issue

**User request:** "Add investigation findings to PE-1234 and set fix version to 2025.1.0"

**Draft file:** `.jira-drafts/20250203-150000-pe-1234-update.md`

```yaml
---
jira_draft_version: "1"
action: update
target_issue: PE-1234
fix_version: "2025.1.0"
created_at: "2025-02-03T15:00:00Z"
status: draft
published_issue: null
---

{status:UPDATE 2025-02-03:purple}

## Investigation Findings

Checked Nolio server logs and found:

1. **Errors are NOT monitored** - No log pattern rules exist
2. **Logs are local only** - Not shipped to DataDog or Splunk
3. **Adding alerting requires** - Agent installation + log forwarder config

Recommend creating a follow-up task for log forwarding setup.
```

### Example 3: Add a Comment

**User request:** "Comment on PE-1234 asking about timeline"

**Draft file:** `.jira-drafts/20250203-151500-pe-1234-comment.md`

```yaml
---
jira_draft_version: "1"
action: comment
target_issue: PE-1234
created_at: "2025-02-03T15:15:00Z"
status: draft
published_issue: null
---

What's the expected timeline for getting the log forwarder config approved?

We have a dependency on this for the Q2 monitoring improvements.
```

### Example 4: Comment with Fix Version (Release Association)

**User request:** "Add a release comment to ML-1226 and set fix version to llm_utils#0.6.4"

**Draft file:** `.jira-drafts/20260209-ml1226-release.md`

```yaml
---
jira_draft_version: "1"
action: comment
target_issue: ML-1226
created_at: "2026-02-09T17:50:00Z"
status: draft
published_issue: null
fix_version: llm_utils#0.6.4
---

{status:RELEASE:green} `llm_utils#0.6.4`

Merged [llm_utils#PR59837](https://mcgsead.visualstudio.com/Data%20Science/_git/llm_utils/pullrequest/59837) - adds multi-region Azure OpenAI support with automatic failover.
```

---

## Output

After creating the draft file, respond with:

```
Draft saved to: .jira-drafts/{filename}

Next steps:
1. Review the draft: `cat .jira-drafts/{filename}`
2. Edit if needed (manually or run `/dataops-assistant:jira-advise`)
3. Publish: `/dataops-assistant:jira-publish .jira-drafts/{filename}`
```

---

## Rules

1. **NEVER use /tmp/** - All drafts go to `.jira-drafts/`
2. **NEVER touch Jira** - This skill only creates local files
3. **Include all required frontmatter** - action, project/target_issue, summary (for create)
4. **Start with CONTEXT block** - Explain the "why" before the "what"
5. **Avoid AI-smelling formatting** - Use `->` not `→`, avoid excessive emoji, keep it natural
6. **NEVER hard-wrap lines** - Do NOT insert newlines to wrap prose at 80 chars or any column width. Write each paragraph/sentence as a single long line. Line breaks in markdown become line breaks in Jira, so hard-wrapping creates ugly mid-sentence breaks in the rendered output.
7. **Always link Jira issues** - Use `[PE-1234](https://mcghealth.atlassian.net/browse/PE-1234)` not plain `PE-1234` so user can click to verify before publishing
