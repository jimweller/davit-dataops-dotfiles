---
description: "Publish an ADO PR comment draft to post comments, replies, or resolve threads. Requires preview and approval."
allowed-tools: ["Bash", "Read", "AskUserQuestion", "ToolSearch", "mcp__azure-devops__repo_get_repo_by_name_or_id", "mcp__azure-devops__repo_create_pull_request_thread", "mcp__azure-devops__repo_reply_to_comment", "mcp__azure-devops__repo_update_pull_request_thread"]
model: sonnet
context: fork
---

# ADO PR Comment Publish

Publish a PR comment draft file to post comments, replies, or resolve threads.

## CRITICAL: Preview Before All Mutations

**NEVER execute without showing the user a preview first.**

For every publish operation:
1. **Read** the draft file
2. **Validate** frontmatter completeness
3. **Resolve** repository GUID (required by ADO MCP)
4. **Show preview** with exact content
5. **Ask for approval** explicitly
6. **Only then** execute the MCP call
7. **Update** draft file with published status

If the user hasn't approved, DO NOT execute.

---

## CRITICAL: Repository GUID Required

**The ADO MCP requires repository GUIDs, not names.**

Before any MCP call, resolve the repository:

```
mcp__azure-devops__repo_get_repo_by_name_or_id:
  project: "{project}"
  repositoryNameOrId: "{repository}"
```

Extract the `id` field from the response and use that as `repositoryId` in subsequent calls.

---

## CRITICAL: project is REQUIRED for ALL MCP calls

**Every MCP call WILL FAIL without `project`.** Always include it.

---

## Loading MCP Tools

Load ADO tools at the start:

```
ToolSearch query: "+azure-devops repo_get_repo_by_name_or_id"
ToolSearch query: "+azure-devops repo_create_pull_request_thread"
ToolSearch query: "+azure-devops repo_reply_to_comment"
ToolSearch query: "+azure-devops repo_update_pull_request_thread"
```

---

## Workflow

1. **Read draft file** from provided path
2. **Parse frontmatter** and body content
3. **Validate** required fields for action type
4. **Resolve repository GUID** via MCP lookup
5. **Show preview** in box format
6. **Ask** for explicit approval
7. **Execute** appropriate MCP call
8. **Update draft** with `status: published` and thread ID
9. **Return** confirmation with PR URL

---

## Input

User provides path to a draft file:
```
/dataops-assistant:ado-pr-comment-publish .ado-drafts/20250210-143022-pr-comment-nil-check.md
```

---

## Validation

### Comment Action
- `project` must be present
- `repository` must be present
- `pull_request_id` must be present
- Body must have content

### Reply Action
- All of the above, plus:
- `thread_id` must be present

### Resolve Action
- All of the above, plus:
- `thread_id` must be present
- `resolve_status` must be valid (fixed, wontFix, closed, byDesign)

If validation fails, show error and stop:
```
Cannot publish: Missing required field 'thread_id' for reply action.
```

---

## Preview Format

### For New Comment

```
+-----------------------------------------------------+
| PREVIEW: Add Comment                                 |
+-----------------------------------------------------+
| Target: PR #12345 in project/repo                   |
| Location: /src/retry.go:42                          |
|                                                     |
| Comment:                                            |
| ---------                                           |
| Consider adding a nil check here - `config.Retry`   |
| could be nil if the config file doesn't have a      |
| retry section.                                      |
+-----------------------------------------------------+

Post this comment?
```

### For Reply

```
+-----------------------------------------------------+
| PREVIEW: Reply to Thread                             |
+-----------------------------------------------------+
| Target: PR #12345, Thread #67890                    |
|                                                     |
| Reply:                                              |
| -------                                             |
| Good catch! I've added the nil check in commit      |
| `a1b2c3d`.                                          |
+-----------------------------------------------------+

Post this reply?
```

### For Resolve

```
+-----------------------------------------------------+
| PREVIEW: Resolve Thread                              |
+-----------------------------------------------------+
| Target: PR #12345, Thread #67890                    |
| Status: fixed                                        |
|                                                     |
| Comment (optional):                                 |
| ------------------                                  |
| Addressed in latest commit.                         |
+-----------------------------------------------------+

Resolve this thread?
```

---

## MCP Execution

### New Comment (Line-Specific)

```
mcp__azure-devops__repo_create_pull_request_thread:
  project: "{project}"
  repositoryId: "{repository_guid}"
  pullRequestId: {pull_request_id}
  threadContext:
    filePath: "{file_path}"
    rightFileStart:
      line: {line_number}
      offset: 1
    rightFileEnd:
      line: {line_number}
      offset: 1
  comments:
    - content: "{comment_body}"
      commentType: 1
  status: "active"
```

### New Comment (General)

```
mcp__azure-devops__repo_create_pull_request_thread:
  project: "{project}"
  repositoryId: "{repository_guid}"
  pullRequestId: {pull_request_id}
  comments:
    - content: "{comment_body}"
      commentType: 1
  status: "active"
```

### Reply to Thread

```
mcp__azure-devops__repo_reply_to_comment:
  project: "{project}"
  repositoryId: "{repository_guid}"
  pullRequestId: {pull_request_id}
  threadId: {thread_id}
  content: "{reply_body}"
```

### Resolve Thread

First add optional comment (if body present), then update status:

```
# Optional: Add closing comment
mcp__azure-devops__repo_reply_to_comment:
  project: "{project}"
  repositoryId: "{repository_guid}"
  pullRequestId: {pull_request_id}
  threadId: {thread_id}
  content: "{resolve_comment}"

# Update thread status
mcp__azure-devops__repo_update_pull_request_thread:
  project: "{project}"
  repositoryId: "{repository_guid}"
  pullRequestId: {pull_request_id}
  threadId: {thread_id}
  status: "{resolve_status}"
```

---

## Post-Publish Updates

After successful publish, update the draft file:

1. Change `status: draft` to `status: published`
2. For new comments: Add `published_thread_id: {thread_id}` from response
3. Write updated file back

Example update:
```yaml
# Before
status: draft
published_thread_id: null

# After
status: published
published_thread_id: 98765
```

---

## Output

### Success

```
Posted successfully!

PR: https://dev.azure.com/org/project/_git/repo/pullrequest/12345
Thread: #98765

Draft updated: .ado-drafts/20250210-143022-pr-comment-nil-check.md
```

### Failure

```
Failed to post comment:

Error: [error message from MCP]

Draft NOT modified. Fix the issue and try again.
```

---

## Example Session

**User:** `/dataops-assistant:ado-pr-comment-publish .ado-drafts/20250210-143022-pr-comment-nil-check.md`

**Response:**

```
+-----------------------------------------------------+
| PREVIEW: Add Comment                                 |
+-----------------------------------------------------+
| Target: PR #12345 in clinical-matching/cms-service  |
| Location: /src/retry.go:42                          |
|                                                     |
| Comment:                                            |
| ---------                                           |
| Consider adding a nil check here - `config.Retry`   |
| could be nil if the config file doesn't have a      |
| retry section.                                      |
|                                                     |
| ```go                                               |
| if config.Retry == nil {                            |
|     return defaultRetryConfig()                     |
| }                                                   |
| ```                                                 |
+-----------------------------------------------------+

Post this comment?
```

**User:** Yes

**Response:**

```
Posted successfully!

PR: https://dev.azure.com/mcgsead/clinical-matching/_git/cms-service/pullrequest/12345
Thread: #98765

Draft updated: .ado-drafts/20250210-143022-pr-comment-nil-check.md
```

---

## Rules

1. **ALWAYS preview before execution** - No exceptions
2. **ALWAYS ask for approval** - User must explicitly confirm
3. **ALWAYS resolve repository GUID** - MCP requires GUIDs, not names
4. **ALWAYS include project** - Required for all MCP calls
5. **Validate before preview** - Don't show preview if fields missing
6. **Update draft after publish** - Mark as published with thread ID
7. **Don't modify draft on failure** - Only update on success
