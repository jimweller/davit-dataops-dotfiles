---
description: "Publish an ADO PR draft to create a pull request. Requires preview and approval."
allowed-tools: ["Read", "Write", "Bash", "AskUserQuestion", "ToolSearch", "mcp__azure-devops__repo_get_repo_by_name_or_id", "mcp__azure-devops__repo_create_pull_request", "mcp__azure-devops__repo_get_pull_request_by_id"]
model: sonnet
context: fork
---

# ADO PR Publish

Publish a PR draft file to create a pull request in Azure DevOps.

## CRITICAL: Look Up Repository GUID First

**The MCP `repo_create_pull_request` does NOT accept projectId.** You MUST look up the repository GUID first.

```
❌ WRONG - will fail with "A project name is required":
mcp__azure-devops__repo_create_pull_request:
  repositoryId: "my-repo"     # ← Name won't work without project context
  ...

✅ CORRECT - look up GUID first, then use it:
# Step 1: Get the repository GUID
mcp__azure-devops__repo_get_repo_by_name_or_id:
  project: "MyProject"
  repositoryNameOrId: "my-repo"
# Response includes: { "id": "a1b2c3d4-...", "name": "my-repo", ... }

# Step 2: Use the GUID in create call
mcp__azure-devops__repo_create_pull_request:
  repositoryId: "a1b2c3d4-..."  # ← Use GUID from step 1
  ...
```

The `project` and `repository` fields from the draft frontmatter are used to look up the GUID.

---

## CRITICAL: Preview Before All Mutations

**NEVER execute without showing the user a preview first.**

For every publish operation:
1. **Read** the draft file
2. **Validate** frontmatter completeness
3. **Show preview** with exact content
4. **Ask for approval** explicitly
5. **Only then** execute the MCP call
6. **Update** draft file with published status

If the user hasn't approved, DO NOT execute.

---

## Workflow

1. **Validate draft** using the validator script
2. **Read draft file** from provided path
3. **Parse frontmatter** and body content
4. **Check validation passed** - stop if errors
5. **Show preview** in box format
6. **Ask** for explicit approval
7. **Load MCP tools** via ToolSearch (repo_get_repo_by_name_or_id AND repo_create_pull_request)
8. **Look up repository GUID** using project + repository name
9. **Execute** PR creation using the GUID as repositoryId
10. **Update draft** with `status: published` and `published_url`
11. **Return** PR URL

---

## Step 1: Validate Draft First

Before doing anything else, validate the draft:

```bash
bun skills/ado-pr-draft/scripts/validate-draft.js {draft_path}
```

If validation fails, show the errors and stop:
```
❌ Draft validation failed:

- CRITICAL: 'project' is missing - MCP call will fail without projectId
- Missing required field: source_branch

Fix the draft file and try again.
```

Only proceed if validation passes.

---

## Input

User provides path to a draft file:
```
/dataops-assistant:ado-pr-publish .ado-drafts/20250204-143022-pr-add-retry-logic.md
```

---

## Validation Before Preview

Required fields for PR creation:
- `project` must be present
- `repository` must be present
- `source_branch` must be present
- `target_branch` must be present
- `title` must be present

If validation fails, show error and stop:
```
❌ Cannot publish: Missing required field 'source_branch' for PR creation.
```

---

## Preview Format

```
┌─────────────────────────────────────────────────────────┐
│ PREVIEW: Create Pull Request                             │
├─────────────────────────────────────────────────────────┤
│ Project: clinical-matching                               │
│ Repository: cms-service                                  │
│ Source: feature/add-retry-logic                          │
│ Target: main                                             │
│ Draft PR: Yes                                            │
│                                                          │
│ Title: Add retry logic for transient API failures        │
│                                                          │
│ Description (first 500 chars):                           │
│ ─────────────────────────────                            │
│ > __See [ML-1234](...)__                                 │
│                                                          │
│ ## What's here                                           │
│                                                          │
│ Adds exponential backoff retry logic for calls to the    │
│ external matching API...                                 │
└─────────────────────────────────────────────────────────┘

Create this PR as a draft?
```

---

## Loading MCP Tools

Load BOTH ADO tools before execution:
```
ToolSearch query: "+azure-devops repo_get_repo"
ToolSearch query: "+azure-devops repo_create_pull_request"
```

---

## Execution - Two Steps Required

### Step 1: Look Up Repository GUID

**ALWAYS do this first.** The create call needs the GUID, not the name.

```
mcp__azure-devops__repo_get_repo_by_name_or_id:
  project: "{project}"              # ← FROM FRONTMATTER
  repositoryNameOrId: "{repository}" # ← FROM FRONTMATTER
```

Extract the `id` field from the response - this is the GUID you need.

### Step 2: Create the Pull Request

Use the GUID from step 1 as `repositoryId`:

```
mcp__azure-devops__repo_create_pull_request:
  repositoryId: "{GUID_FROM_STEP_1}"            # ← GUID, not name!
  sourceRefName: "refs/heads/{source_branch}"   # ← ADD refs/heads/ prefix
  targetRefName: "refs/heads/{target_branch}"   # ← ADD refs/heads/ prefix
  title: "{title}"                              # ← FROM FRONTMATTER
  description: "{body_content}"                 # ← FROM BODY (after frontmatter)
  isDraft: true                                 # ← ALWAYS true
```

**CHECKLIST before create call:**
- [ ] `repositoryId` is a GUID (looks like `a1b2c3d4-e5f6-...`), NOT a name
- [ ] Branch refs have `refs/heads/` prefix
- [ ] `isDraft` is `true`

---

## Post-Publish Updates

After successful publish, update the draft file:

1. Change `status: draft` to `status: published`
2. Add `published_url` with the PR URL
3. Add `published_pr_id` with the PR ID
4. Write updated file back

Example update:
```yaml
# Before
status: draft
published_url: null
published_pr_id: null

# After
status: published
published_url: https://dev.azure.com/org/project/_git/repo/pullrequest/12345
published_pr_id: 12345
```

---

## Output

### Success

```
✅ Published successfully!

PR: https://dev.azure.com/org/project/_git/repo/pullrequest/12345
Status: Draft (ready for review)

Draft updated: .ado-drafts/20250204-143022-pr-add-retry-logic.md

Next: Review the PR in ADO and publish when ready.
```

### Failure

```
❌ Publish failed:

Error: [error message from MCP]

Draft NOT modified. Fix the issue and try again.
```

---

## Rules

1. **ALWAYS preview before mutation** - No exceptions
2. **ALWAYS ask for approval** - User must explicitly confirm
3. **PRs are ALWAYS drafts** - `isDraft: true`
4. **Include projectId** - Required for MCP call
5. **Update draft after publish** - Mark as published with URL
6. **Return URL** - User needs to verify the result
7. **Don't modify draft on failure** - Only update on success
