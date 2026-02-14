---
description: "Publish a Jira draft to create/update issues or add comments. Requires preview and approval."
allowed-tools: ["Bash", "Read", "AskUserQuestion", "ToolSearch", "mcp__atlassian__lookupJiraAccountId"]
model: sonnet
context: fork
---


# Jira Publish

Publish a Jira draft file to create issues, update descriptions, or add comments.

## CRITICAL: Preview Before All Mutations

**NEVER execute without showing the user a preview first.**

For every publish operation:
1. **Read** the draft file
2. **Validate** frontmatter completeness
3. **Show preview** with exact content
4. **Ask for approval** explicitly
5. **Only then** execute the command
6. **Update** draft file with published status

If the user hasn't approved, DO NOT execute.

---

## Workflow

1. **Read draft file** from provided path (use Read tool — do NOT extract body with shell)
2. **Parse frontmatter** fields from the Read output (the YAML between `---` delimiters)
3. **Validate** required fields for action type
4. **Resolve assignee** - if `assignee` is an email, look up account ID via `lookupJiraAccountId`
5. **Resolve mentions** - look up any `@email` mentions in body (see Mentions section)
6. **Show preview** in box format (including resolved assignee and mentions)
7. **Ask** for explicit approval
8. **Execute** via jira-api.sh with all options (--assignee, --component, --parent)
9. **Add links** if any specified
10. **Update draft** with `status: published` and `published_issue`
11. **Return** issue URL

---

## Input

User provides path to a draft file:
```
/dataops-assistant:jira-publish .jira-drafts/20250203-143022-openai-instance.md
```

---

## Preview Format

### Create Issue

```
┌─────────────────────────────────────────────────────────┐
│ PREVIEW: Create Issue                                    │
├─────────────────────────────────────────────────────────┤
│ Project: PE                                              │
│ Type: Story                                              │
│ Summary: Set up dedicated OpenAI instance for CMS        │
│ Assignee: john@company.com -> John Smith (5b10ac...)     │  # if present
│ Parent: PE-100                                           │  # if present
│ Components: Backend, API                                 │  # if present
│                                                          │
│ Description (first 500 chars):                           │
│ ─────────────────────────────                            │
│ :::context                                               │
│ Forever ago, we set up the initial OpenAI instance...    │
│ :::                                                      │
│                                                          │
│ ## What We Have Today                                    │
│ - Single OpenAI instance shared across all...            │
│                                                          │
│ Links to add after creation:                             │
│ - blocks PE-456                                          │
│ - relates-to MAT-28                                      │
└─────────────────────────────────────────────────────────┘
```

### Update Issue

```
┌─────────────────────────────────────────────────────────┐
│ PREVIEW: Update Issue                                    │
├─────────────────────────────────────────────────────────┤
│ Target: PE-1234                                          │
│ Fix Version: 2025.1.0                                    │  # if present
│                                                          │
│ New Description (first 500 chars):                       │
│ ─────────────────────────────────                        │
│ {status:UPDATE 2025-02-03:purple}                        │
│                                                          │
│ ## Investigation Findings                                │
│ Checked Nolio server logs and found...                   │
└─────────────────────────────────────────────────────────┘
```

### Add Comment

```
┌─────────────────────────────────────────────────────────┐
│ PREVIEW: Add Comment                                     │
├─────────────────────────────────────────────────────────┤
│ Target: PE-1234                                          │
│ Fix Version: llm_utils#0.6.4                             │  # if present
│                                                          │
│ Comment:                                                 │
│ ────────                                                 │
│ What's the expected timeline for getting the log         │
│ forwarder config approved?                               │
│                                                          │
│ We have a dependency on this for Q2 monitoring.          │
└─────────────────────────────────────────────────────────┘
```

---

## Commands

**CRITICAL: Always use the bin wrapper.** Never call scripts by direct path.
The bin wrapper delegates to the `run` wrapper which sources `DATAOPS_ASSISTANT_ROOT` and resolves
paths — without it, scripts cannot find their sibling files (like `md-to-adf.js`).

```bash
# CORRECT — single unambiguous path
JIRA_API="$HOME/.dataops-assistant/bin/jira-api.sh"

# WRONG — do NOT use direct paths to scripts:
# JIRA_API=~/.dataops-assistant/skills/jira-publish/scripts/jira-api.sh   ← BROKEN
# JIRA_API=/Users/.../incubating-dataops-assistant-plugin/skills/...      ← BROKEN
```

### Create Issue

```bash
# Basic create
echo 'markdown content' | bash "$JIRA_API" create <project> "<issue_type>" "<summary>" - --md

# With optional fields (assignee must be account ID, not email)
echo 'markdown content' | bash "$JIRA_API" create <project> "<issue_type>" "<summary>" - --md \
  --assignee "<account_id>" \
  --parent "<epic_key>" \
  --component "Backend" --component "API"
```

### Update Issue

```bash
# Update description only
echo 'markdown content' | bash "$JIRA_API" update <issue_key> - --md

# Update description and set fix version
echo 'markdown content' | bash "$JIRA_API" update <issue_key> - --md \
  --fix-version "2025.1.0"
```

### Add Comment

```bash
# Add comment only
echo 'markdown content' | bash "$JIRA_API" comment <issue_key> - --md

# Add comment AND set fix version (two API calls handled internally)
echo 'markdown content' | bash "$JIRA_API" comment <issue_key> - --md \
  --fix-version "llm_utils#0.6.4"
```

### Add Links (after create)

For each link in frontmatter, use the **exact type specified**:

```yaml
# Frontmatter format:
links:
  - type: blocks        # Use "blocks" in command
    target: PE-456
  - type: is-blocked-by # Use "is-blocked-by" in command
    target: PE-789
```

```bash
# Execute for EACH link, using the type FROM the frontmatter:
bash "$JIRA_API" link <created_issue> <type_from_frontmatter> <target_from_frontmatter>

# Examples:
bash "$JIRA_API" link PE-1234 blocks PE-456
bash "$JIRA_API" link PE-1234 is-blocked-by PE-789
```

**CRITICAL:** Do NOT default to `relates-to`. Use exactly what the frontmatter specifies.

Valid link types:
- **Standard (all Jira):** `blocks`, `is-blocked-by`, `relates-to`, `duplicates`, `clones`, `is-cloned-by`
- **Extended (Cloud only):** `causes`, `is-caused-by`

**Note:** The 4 core types (Blocks, Relates, Duplicate, Cloners) work in all Jira versions. The Causes type is a Jira Cloud extended feature. Other Cloud extended types (implements, reviews, product discovery types) and custom link types are not supported.

---

## Validation Before Preview

### Create Action
- `project` must be present
- `issue_type` must be valid (Story, Task, Bug, Epic, Sub-task)
- `summary` must be present

### Update Action
- `target_issue` must be present and valid format (PROJ-123)
- `fix_version` (optional) - version name must exist in the project

### Comment Action
- `target_issue` must be present and valid format (PROJ-123)
- `fix_version` (optional) - version name must exist in the project

If validation fails, show error and stop:
```
❌ Cannot publish: Missing required field 'project' for create action.
```

---

## Assignee Resolution

**CRITICAL: Email Domain is @mcg.com**

The company email domain is `@mcg.com`, NOT `@mcghealth.com`. Do not be confused by the Atlassian cloud ID being `mcghealth` - that's just the subdomain for Atlassian Cloud, not the email domain.

- ✅ Correct: `jack.stouffer@mcg.com`
- ❌ Wrong: `jack.stouffer@mcghealth.com`

If `assignee` is present in frontmatter and looks like an email (contains `@`), resolve it to an account ID:

```
1. Call: mcp__atlassian__lookupJiraAccountId(query: "user@company.com")
2. Extract accountId from result
3. If no result found, abort:
   ❌ Cannot publish: Could not resolve assignee "user@company.com"
   Check spelling or use valid Atlassian email address.
4. Store resolved ID to pass to jira-api.sh --assignee
```

### Preview with Assignee

```
┌─────────────────────────────────────────────────────────┐
│ PREVIEW: Create Issue                                    │
├─────────────────────────────────────────────────────────┤
│ Project: PE                                              │
│ Type: Story                                              │
│ Summary: Set up dedicated OpenAI instance                │
│ Assignee: user@company.com -> John Smith (5b10ac8d...)   │
│ Parent: PE-100                                           │
│ Components: Backend, API                                 │
```

---

## Mentions (@user)

**Remember: Email domain is @mcg.com** (not @mcghealth.com)

The markdown converter supports `@email@domain.com` syntax for mentioning users. These are converted to placeholder mentions that **must be resolved before publishing**.

### How It Works

1. Markdown like `Hey @john.smith@company.com please review` converts to ADF with:
   ```json
   { "type": "mention", "attrs": { "id": "__EMAIL__:john.smith@company.com", ... } }
   ```

2. Before publishing, scan the body content for `__EMAIL__:` patterns
3. For each email found, call `mcp__atlassian__lookupJiraAccountId` with the email
4. If lookup succeeds, replace `__EMAIL__:email` with the actual account ID
5. If ANY lookup fails, **abort immediately** with error

### Resolution Steps

**IMPORTANT:** Resolution happens AFTER markdown-to-ADF conversion, on the ADF JSON.

```
1. Scan the Read tool output for @email@domain.com patterns (do NOT use shell to extract body)
2. For each email found:
   - Call: mcp__atlassian__lookupJiraAccountId(query: "email@domain.com")
   - If result has accountId, store mapping: email -> accountId
   - If no result, add to failed list
3. If failed list not empty:
   ❌ Cannot publish: Could not resolve mentions for:
      - john.smith@company.com
      - jane.doe@company.com
   Check spelling or use valid Atlassian email addresses.
4. Convert whole draft file to ADF: cat "$draft_file" | bun ~/.dataops-assistant/run skills/jira-publish/scripts/md-to-adf.js
   (md-to-adf.js strips frontmatter automatically)
5. The ADF will contain: "id": "__EMAIL__:john.smith@company.com"
6. String-replace in ADF JSON: __EMAIL__:email -> resolved_account_id
7. Pass the modified ADF to Jira API (no --md flag)
```

**Practical approach:** Since jira-api.sh handles the markdown conversion internally, you have two options:

**Option A (recommended):** Convert markdown separately, replace in ADF, pass raw ADF:
```bash
# Convert whole draft file to ADF (md-to-adf.js strips frontmatter automatically)
adf=$(cat "$draft_file" | bun ~/.dataops-assistant/run skills/jira-publish/scripts/md-to-adf.js)
# Replace email placeholders with account IDs
adf=$(echo "$adf" | sed "s/__EMAIL__:john@example.com/5b10ac8d.../g")
# Pass raw ADF (no --md flag)
echo "$adf" | bash "$JIRA_API" create PE Story "Title" -
```

**Option B:** Replace @email in markdown with a temporary marker, then fix after:
- Not recommended - the @email syntax is designed for this flow

### Example Preview with Mentions

```
┌─────────────────────────────────────────────────────────┐
│ PREVIEW: Create Issue                                    │
├─────────────────────────────────────────────────────────┤
│ Project: PE                                              │
│ Type: Story                                              │
│ Summary: Review needed for API changes                   │
│                                                          │
│ Mentions to resolve:                                     │
│ ✓ @john.smith@company.com -> John Smith (5b10ac8d...)    │
│ ✓ @jane.doe@company.com -> Jane Doe (6c21bd9e...)        │
│                                                          │
│ Description (first 500 chars):                           │
│ ─────────────────────────────                            │
│ Hey @john.smith@company.com can you review this?         │
└─────────────────────────────────────────────────────────┘
```

### Failed Resolution Example

```
❌ Cannot publish: Could not resolve mentions:
   - bob.nobody@company.com (no matching Atlassian user)

Fix the email addresses in the draft and try again.
```

---

## Post-Publish Updates

After successful publish, update the draft file:

1. Change `status: draft` to `status: published`
2. Add `published_issue: PE-1234` (the created/updated issue key)
3. Write updated file back

Example update:
```yaml
# Before
status: draft
published_issue: null

# After
status: published
published_issue: PE-1234
```

---

## Execution Flow

**CRITICAL: Pipe the whole draft file.** Do NOT extract the body with awk/sed/shell.
The `md-to-adf.js` converter strips YAML frontmatter automatically, so piping
the entire file (frontmatter included) is correct and reliable.

### For Create

```bash
# 1. Build command with optional flags
cmd="bash \"$JIRA_API\" create \"$project\" \"$issue_type\" \"$summary\" - --md"

# Add assignee if present (must be resolved account ID)
[[ -n "$assignee_id" ]] && cmd="$cmd --assignee \"$assignee_id\""

# Add parent if present
[[ -n "$parent" ]] && cmd="$cmd --parent \"$parent\""

# Add components if present (one --component per component)
for comp in "${components[@]}"; do
  cmd="$cmd --component \"$comp\""
done

# 2. Pipe the WHOLE draft file (md-to-adf.js strips frontmatter)
#    If mentions need resolution, use Option A from Mentions section instead
result=$(cat "$draft_file" | eval "$cmd")
issue_key=$(echo "$result" | jq -r '.issue_key')

# 3. Add links if any (use EXACT type from frontmatter)
for link in links:
  bash "$JIRA_API" link "$issue_key" "${link.type}" "${link.target}"
  # Example: if frontmatter has {type: blocks, target: PE-456}
  #          then run: bash "$JIRA_API" link PE-1234 blocks PE-456

# 4. Return URL
echo "$result" | jq -r '.issue_url'
```

### For Update

```bash
# Build command with optional flags
cmd="bash \"$JIRA_API\" update \"$target_issue\" - --md"

# Add fix version if present
[[ -n "$fix_version" ]] && cmd="$cmd --fix-version \"$fix_version\""

# Pipe the WHOLE draft file (md-to-adf.js strips frontmatter)
result=$(cat "$draft_file" | eval "$cmd")
echo "$result" | jq -r '.issue_url'
```

### For Comment

```bash
# Build command with optional flags
cmd="bash \"$JIRA_API\" comment \"$target_issue\" - --md"

# Add fix version if present (will add comment AND set fix version)
[[ -n "$fix_version" ]] && cmd="$cmd --fix-version \"$fix_version\""

# Pipe the WHOLE draft file (md-to-adf.js strips frontmatter)
result=$(cat "$draft_file" | eval "$cmd")
echo "$result" | jq -r '.issue_url'
```

---

## Output

### Success

```
✅ Published successfully!

Issue: PE-1234
URL: https://mcghealth.atlassian.net/browse/PE-1234

Links added:
- relates-to MAT-28

Draft updated: .jira-drafts/20250203-143022-openai-instance.md
```

### Failure

```
❌ Publish failed:

Error: [error message from jira-api.sh]

Draft NOT modified. Fix the issue and try again.
```

---

## Example Session

**User:** `/dataops-assistant:jira-publish .jira-drafts/20250203-143022-openai-instance.md`

**Response:**

```
┌─────────────────────────────────────────────────────────┐
│ PREVIEW: Create Issue                                    │
├─────────────────────────────────────────────────────────┤
│ Project: PE                                              │
│ Type: Story                                              │
│ Summary: Set up dedicated OpenAI instance for CMS        │
│                                                          │
│ Description (first 500 chars):                           │
│ ─────────────────────────────                            │
│ :::context                                               │
│ Forever ago, we set up the initial OpenAI instance for   │
│ DataSci (MAT-28). Today they still use that single       │
│ instance for everything...                               │
│ :::                                                      │
│                                                          │
│ ## What We Have Today                                    │
│ - Single OpenAI instance shared across all DataSci...    │
│                                                          │
│ Links to add after creation:                             │
│ - relates-to MAT-28                                      │
└─────────────────────────────────────────────────────────┘

Create this issue in Jira?
```

**User:** Yes

**Response:**

```
✅ Published successfully!

Issue: PE-3456
URL: https://mcghealth.atlassian.net/browse/PE-3456

Links added:
- relates-to MAT-28

Draft updated: .jira-drafts/20250203-143022-openai-instance.md
```

---

## Rules

1. **ALWAYS preview before execution** - No exceptions
2. **ALWAYS ask for approval** - User must explicitly confirm
3. **Validate before preview** - Don't show preview if fields missing
4. **Update draft after publish** - Mark as published with issue key
5. **Return URL** - User needs to verify the result
6. **Don't modify draft on failure** - Only update on success
