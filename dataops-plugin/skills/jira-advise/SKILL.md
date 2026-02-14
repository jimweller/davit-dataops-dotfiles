---
description: "Review a Jira draft file and provide feedback on content, structure, and style compliance."
allowed-tools: ["Bash", "Read", "Write", "Glob", "AskUserQuestion"]
model: sonnet
context: fork
---

# Jira Advise

Review a Jira draft file and provide feedback on frontmatter validity, content quality, and style guide compliance.

## Workflow

1. **Read draft file** from provided path
2. **Validate frontmatter** - Required fields present, valid values
3. **Check content** against style guide
4. **Provide feedback** with specific suggestions
5. **Optionally revise** file with user approval

---

## Input

User provides path to a draft file:
```
/dataops-assistant:jira-advise .jira-drafts/20250203-143022-openai-instance.md
```

If no path provided, list available drafts:
```bash
ls -la .jira-drafts/*.md 2>/dev/null || echo "No drafts found in .jira-drafts/"
```

---

## Validation Checklist

Present findings in this format:

```markdown
## Frontmatter Validation

- [x] `jira_draft_version`: present (1)
- [x] `action`: valid (create)
- [x] `project`: present (PE)
- [x] `issue_type`: valid (Story)
- [ ] `summary`: too long (>100 chars) - should be concise
- [x] `status`: valid (draft)

## Content Review

- [x] CONTEXT block present
- [x] Structure matches issue type
- [ ] AC should be skipped for infrastructure work
- [x] Links use valid issue keys
- [ ] Missing "What Needs To Be Figured Out" section

## Style Compliance

- [x] Headings use correct levels
- [x] Code uses backticks
- [ ] Status lozenge has invalid color (use: purple, red, blue, green, yellow, neutral)
```

---

## Frontmatter Rules

### Required Fields by Action

| Action | Required Fields |
|--------|-----------------|
| `create` | `project`, `issue_type`, `summary` |
| `update` | `target_issue` |
| `comment` | `target_issue` |

### Valid Values

- **action**: `create`, `update`, `comment`
- **issue_type**: `Story`, `Task`, `Bug`, `Epic`, `Sub-task`
- **link types**: `blocks`, `is-blocked-by`, `relates-to`, `duplicates`
- **status**: `draft`, `published`

### Summary Guidelines

- Max 100 characters recommended
- Sentence case, not title case
- Starts with verb or noun, not article
- No trailing punctuation

---

## Content Rules

### CONTEXT Block

**Required for:** All `create` actions except simple tasks.

**Check for:**
- Explains "why" not just "what"
- Includes historical context or current state
- References related issues inline (not duplicating links)

### Structure Pattern Selection

| Issue Type | Expected Pattern |
|------------|------------------|
| Story (user-facing) | AC pattern with checkboxes |
| Story (infrastructure) | Requirements pattern, skip AC |
| Task (investigation) | Questions pattern, skip AC |
| Task (simple change) | Minimal, just describe the change |
| Bug | AC pattern (what "fixed" looks like) |
| Epic | Persona/use-case sections, no AC |

### When AC Should Be Skipped

Flag if AC is present but shouldn't be:
- Infrastructure/platform work
- Research spikes
- Investigation tasks
- Simple config changes
- Sub-tasks (parent defines done)

### When AC Should Be Added

Flag if AC is missing but should be present:
- User-facing feature with multiple outcomes
- Bug fix where "fixed" is ambiguous
- Story where "done" could be misunderstood

---

## Style Rules

### Headings

- `##` for major sections
- `###` for sub-sections
- `####` for questions/action items
- Don't skip levels (no `##` then `####`)

### Status Lozenges

Valid format: `{status:TEXT:color}`

Valid colors: `purple`, `red`, `blue`, `green`, `yellow`, `neutral`

### Issue Keys

- Format: `PROJ-123` (uppercase project, hyphen, number)
- Should auto-link in Jira

### Links in Frontmatter

```yaml
links:
  - type: blocks        # Valid
    target: PE-456
  - type: block         # Invalid - should be "blocks"
    target: PE-789
```

---

## Revision Workflow

If issues found:

1. **Show checklist** with all findings
2. **Summarize** the critical issues
3. **Ask user**: "Would you like me to revise the draft?"
4. **If yes**: Make changes and show diff
5. **Save** revised file (same path)

### Making Revisions

Read the file, apply fixes, write back:

```bash
# Read current content
cat .jira-drafts/filename.md

# After revising, write back with Write tool
```

Always show what changed:
```
## Changes Made

1. Shortened summary from 150 to 80 characters
2. Added CONTEXT block
3. Changed link type from "block" to "blocks"
4. Removed AC section (infrastructure work)
```

---

## Example Review

**Input:** `.jira-drafts/20250203-143022-openai-instance.md`

**Output:**

```markdown
## Frontmatter Validation

- [x] `jira_draft_version`: present (1)
- [x] `action`: valid (create)
- [x] `project`: present (PE)
- [x] `issue_type`: valid (Story)
- [x] `summary`: good length (45 chars)
- [x] `links`: valid types and targets
- [x] `status`: valid (draft)

## Content Review

- [x] CONTEXT block present and explains "why"
- [x] Structure: Requirements pattern (appropriate for infrastructure)
- [x] No AC section (correct for this work type)
- [x] Inline issue mentions don't duplicate links

## Style Compliance

- [x] Headings use correct levels
- [x] Lists formatted correctly
- [x] Issue keys properly formatted

## Summary

✅ **Draft looks good!** No issues found.

Ready to publish:
`/dataops-assistant:jira-publish .jira-drafts/20250203-143022-openai-instance.md`
```

---

## Output

End with one of:

**If no issues:**
```
✅ Draft looks good! Ready to publish:
/dataops-assistant:jira-publish {path}
```

**If issues found and not revised:**
```
Found {N} issues. Run this skill again after making changes, or ask me to revise.
```

**If issues found and revised:**
```
✅ Draft revised and saved. Ready to publish:
/dataops-assistant:jira-publish {path}
```
