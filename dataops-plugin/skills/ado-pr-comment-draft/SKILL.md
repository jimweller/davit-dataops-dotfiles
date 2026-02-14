---
description: "Draft ADO PR comment/reply/resolve to a local file for review. Does NOT post comments."
allowed-tools: ["Bash", "Read", "Write", "Glob", "Grep", "Task"]
model: opus
context: fork
---

# ADO PR Comment Draft

Draft Azure DevOps PR comments, replies, or resolve actions to a local markdown file for review before publishing.

## Workflow

1. **Understand the request** - What PR? What action (comment, reply, resolve)?
2. **Gather PR context** - Use `ado-pr-reader` agent to understand the PR
3. **Read the comment style guide** - Follow the Comment Style Guide below
4. **Draft content** - Write the comment following the guide
5. **Create frontmatter** - Include metadata for publishing
6. **Write to file** - Save to `.ado-drafts/{timestamp}-pr-comment-{slug}.md`
7. **Return instructions** - Tell user how to review and publish

**This skill NEVER touches Azure DevOps.** It only creates local files.

---

## FIRST: Gather PR Context

Before drafting any comment, understand the PR by using the `ado-pr-reader` agent:

```
Task(subagent_type: "dataops-assistant:ado-pr-reader", prompt: "Read PR #{pr_id} in project {project} repo {repo}. I need to understand the context for writing a comment.")
```

This gives you:
- PR title and description
- Files changed
- Existing threads and comments
- Current status

**Never draft a comment without first reading the PR context.**

---

## Draft File Format

```yaml
---
ado_comment_draft_version: "1"
action: comment           # comment | reply | resolve
project: "ProjectName"    # Required
repository: "repo-name"   # Required
pull_request_id: 12345    # Required
thread_id: 67890          # Required for reply/resolve, null for new comment
file_path: "/src/file.go" # Optional - for line comments
line_number: 42           # Optional - for line comments
resolve_status: "fixed"   # Only for resolve: fixed | wontFix | closed | byDesign
created_at: "2025-02-10T14:30:00Z"
status: draft             # draft | published
published_thread_id: null # Set after publish (for new comments)
---

[Comment content follows in markdown]
```

**File naming:** `.ado-drafts/{timestamp}-pr-comment-{slug}.md`
- Timestamp: `YYYYMMDD-HHMMSS`
- Slug: brief description (max 30 chars)
- Examples:
  - `20250210-143022-pr-comment-nil-check.md`
  - `20250210-144500-pr-reply-addressed.md`
  - `20250210-145000-pr-resolve-fixed.md`

---

## Creating Draft Files

Always create the `.ado-drafts/` directory first:

```bash
mkdir -p .ado-drafts
```

Generate filename:
```bash
timestamp=$(date +%Y%m%d-%H%M%S)
slug="nil-check-suggestion"  # derived from comment purpose
filename=".ado-drafts/${timestamp}-pr-comment-${slug}.md"
```

---

## Comment Style Guide

### Tone
- **Collaborative**, not confrontational
- **Specific**, not vague
- **Actionable** when requesting changes

### Format
- Use backticks for `code`, `variables`, `file names`
- Keep comments concise (1-3 sentences ideal)
- If suggesting code, use fenced code blocks
- Ask questions when genuinely uncertain

### Good Examples

**Asking a question**:
```
Should `max_retries` be configurable via environment variable?
That would help with different deployment environments.
```

**Suggesting a change**:
```
Consider adding a nil check here - `config.Retry` could be
nil if the config file doesn't have a retry section.
```

**Approving with minor note**:
```
LGTM! One small thing - the error message on line 45 could
include the actual value that failed validation.
```

**Requesting clarification**:
```
What's the expected behavior if `timeout` is 0? Should it
mean "no timeout" or "immediate timeout"?
```

**Replying to feedback**:
```
Good catch! I've added the nil check in the latest commit.
```

### Bad Examples (Don't Do These)

```
This is wrong.                    # Not specific
Fix this.                         # Not actionable
Why did you do it this way?       # Confrontational
I would have done it differently. # Not helpful
```

---

## Examples

### Example 1: New Line Comment

**User request:** "Comment on PR 12345 in cms-service suggesting a nil check on line 42 of retry.go"

**First:** Use ado-pr-reader to understand the PR context.

**Draft file:** `.ado-drafts/20250210-143022-pr-comment-nil-check.md`

```yaml
---
ado_comment_draft_version: "1"
action: comment
project: "clinical-matching"
repository: "cms-service"
pull_request_id: 12345
thread_id: null
file_path: "/src/retry.go"
line_number: 42
resolve_status: null
created_at: "2025-02-10T14:30:22Z"
status: draft
published_thread_id: null
---

Consider adding a nil check here - `config.Retry` could be nil if the config file doesn't have a retry section.

```go
if config.Retry == nil {
    return defaultRetryConfig()
}
```
```

### Example 2: General Comment (No File)

**User request:** "Add a general comment on PR 12345 asking about test coverage"

**Draft file:** `.ado-drafts/20250210-144000-pr-comment-test-coverage.md`

```yaml
---
ado_comment_draft_version: "1"
action: comment
project: "clinical-matching"
repository: "cms-service"
pull_request_id: 12345
thread_id: null
file_path: null
line_number: null
resolve_status: null
created_at: "2025-02-10T14:40:00Z"
status: draft
published_thread_id: null
---

Are there integration tests covering the new retry behavior? I'd like to see tests for:
- Successful retry after transient failure
- Max retries exceeded
- Circuit breaker activation
```

### Example 3: Reply to Thread

**User request:** "Reply to thread 67890 on PR 12345 saying I addressed the feedback"

**Draft file:** `.ado-drafts/20250210-144500-pr-reply-addressed.md`

```yaml
---
ado_comment_draft_version: "1"
action: reply
project: "clinical-matching"
repository: "cms-service"
pull_request_id: 12345
thread_id: 67890
file_path: null
line_number: null
resolve_status: null
created_at: "2025-02-10T14:45:00Z"
status: draft
published_thread_id: null
---

Good catch! I've added the nil check in commit `a1b2c3d`. Also added a unit test to cover the nil config case.
```

### Example 4: Resolve Thread

**User request:** "Resolve thread 67890 on PR 12345 as fixed"

**Draft file:** `.ado-drafts/20250210-145000-pr-resolve-fixed.md`

```yaml
---
ado_comment_draft_version: "1"
action: resolve
project: "clinical-matching"
repository: "cms-service"
pull_request_id: 12345
thread_id: 67890
file_path: null
line_number: null
resolve_status: fixed
created_at: "2025-02-10T14:50:00Z"
status: draft
published_thread_id: null
---

Addressed in latest commit.
```

**Resolve status options:**
- `fixed` - Issue has been addressed
- `wontFix` - Acknowledged but won't change
- `closed` - Discussion complete, no action needed
- `byDesign` - Current behavior is intentional

---

## Output

After creating the draft file, respond with:

```
Draft saved to: .ado-drafts/{filename}

Next steps:
1. Review the draft: cat .ado-drafts/{filename}
2. Edit if needed
3. Publish: /dataops-assistant:ado-pr-comment-publish .ado-drafts/{filename}
```

---

## Rules

1. **ALWAYS gather PR context first** - Use ado-pr-reader before drafting
2. **NEVER use /tmp/** - All drafts go to `.ado-drafts/`
3. **NEVER touch Azure DevOps** - This skill only creates local files
4. **Follow comment style guide** - Be collaborative and specific
5. **Include all required frontmatter** - action, project, repository, pull_request_id
6. **Avoid AI-smelling formatting** - Use `->` not `→`, avoid excessive emoji, keep it natural
7. **Context matters** - Read the PR to understand what comment is appropriate
