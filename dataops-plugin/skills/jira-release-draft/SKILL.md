---
description: "Draft Jira release notes to a local file. Queries issues by fix version and auto-generates release notes."
allowed-tools: ["Bash", "Read", "Write", "Glob", "ToolSearch", "mcp__atlassian__searchJiraIssuesUsingJql"]
model: opus
context: fork
---


# Jira Release Draft

Draft release notes for a Jira version by querying issues in that fix version and generating markdown.

## Workflow

1. **Understand the request** - What project? What version name?
2. **Check if version exists** - Use jira-api.sh version-get to validate
3. **Query issues** - Search for issues with that fix version
4. **Group by type** - Stories/Epics -> Features, Bugs -> Bug Fixes, Tasks -> Improvements
5. **Generate release notes** - Create structured markdown
6. **Create frontmatter** - Include metadata for publishing
7. **Write to file** - Save to `.jira-release-drafts/{timestamp}-{slug}.md`
8. **Return instructions** - Tell user how to review and publish

**This skill NEVER touches Jira versions.** It only creates local files.

---

## Draft File Format

```yaml
---
jira_release_version: "1"
action: create | update
project: PE
version_name: "2025.1.0"
release_date: "2025-02-15"        # Optional, ISO date
mark_released: false              # Optional, mark as released when publishing
source_query: "fixVersion = ..."  # JQL used to generate notes
issue_count: 15                   # Number of issues found
created_at: "2025-02-09T18:00:00Z"
status: draft | published
published_version_id: null        # Set after publish
---

[Auto-generated release notes markdown]
```

**File naming:** `.jira-release-drafts/{timestamp}-{slug}.md`
- Timestamp: `YYYYMMDD-HHMMSS`
- Slug: lowercase version name with hyphens (max 30 chars)
- Example: `20250209-180000-2025-1-0.md`

---

## Creating Draft Files

Always create the `.jira-release-drafts/` directory if it doesn't exist:

```bash
mkdir -p .jira-release-drafts
```

Generate filename:
```bash
timestamp=$(date +%Y%m%d-%H%M%S)
slug=$(echo "2025.1.0" | tr '.' '-' | tr '[:upper:]' '[:lower:]' | cut -c1-30)
filename=".jira-release-drafts/${timestamp}-${slug}.md"
```

---

## Querying Issues

Use the Atlassian MCP to search for issues:

```
mcp__atlassian__searchJiraIssuesUsingJql(
  jql: "project = PE AND fixVersion = \"2025.1.0\" ORDER BY issuetype ASC, key ASC",
  limit: 100
)
```

**Important:** First load the tool with ToolSearch:
```
ToolSearch(query: "select:mcp__atlassian__searchJiraIssuesUsingJql")
```

---

## Issue Type Grouping

Group issues by type for the release notes:

| Issue Types | Section Name |
|-------------|--------------|
| Story, Epic | Features |
| Bug | Bug Fixes |
| Task, Sub-task | Improvements |
| Improvement | Improvements |

Skip sections with no issues.

---

## Release Notes Template

```markdown
## Release {version_name}

Released: {release_date or "TBD"}

### Features

- [{KEY}]({url}): {summary}
- [{KEY}]({url}): {summary}

### Bug Fixes

- [{KEY}]({url}): {summary}

### Improvements

- [{KEY}]({url}): {summary}

---

*Generated from {issue_count} issues in fixVersion "{version_name}"*
```

**URL format:** `https://mcghealth.atlassian.net/browse/{KEY}`

---

## Checking Version Existence

Before generating notes, verify the version exists:

```bash
# CRITICAL: Always use the bin wrapper — never call scripts by direct path
JIRA_API="$HOME/.dataops-assistant/bin/jira-api.sh"
bash "$JIRA_API" version-get PE "2025.1.0"
```

If the version doesn't exist, you can still generate notes (action: create), but inform the user that the version will be created on publish.

---

## Actions

### action: create

Use when the version does NOT exist in Jira yet. Publishing will:
1. Create the version in Jira
2. Set the description to the release notes

### action: update

Use when the version ALREADY exists in Jira. Publishing will:
1. Update the version's description with the release notes
2. Optionally mark as released (if mark_released: true)

---

## Example Session

**User:** "Generate release notes for PE version 2025.1.0"

**Steps:**

1. Check if version exists:
   ```bash
   bash "$JIRA_API" version-get PE "2025.1.0"
   ```

2. Query issues:
   ```
   mcp__atlassian__searchJiraIssuesUsingJql(
     jql: "project = PE AND fixVersion = \"2025.1.0\"",
     limit: 100
   )
   ```

3. Generate draft file:
   ```yaml
   ---
   jira_release_version: "1"
   action: update           # Version exists
   project: PE
   version_name: "2025.1.0"
   release_date: "2025-02-15"
   mark_released: false
   source_query: "project = PE AND fixVersion = \"2025.1.0\""
   issue_count: 12
   created_at: "2025-02-09T18:30:00Z"
   status: draft
   published_version_id: null
   ---

   ## Release 2025.1.0

   Released: 2025-02-15

   ### Features

   - [PE-1234](https://mcghealth.atlassian.net/browse/PE-1234): Add user authentication flow
   - [PE-1235](https://mcghealth.atlassian.net/browse/PE-1235): Implement dashboard redesign

   ### Bug Fixes

   - [PE-1300](https://mcghealth.atlassian.net/browse/PE-1300): Fix login timeout issue
   - [PE-1301](https://mcghealth.atlassian.net/browse/PE-1301): Resolve cache invalidation

   ### Improvements

   - [PE-1400](https://mcghealth.atlassian.net/browse/PE-1400): Optimize database queries

   ---

   *Generated from 12 issues in fixVersion "2025.1.0"*
   ```

4. Save and respond:
   ```
   Draft saved to: .jira-release-drafts/20250209-183000-2025-1-0.md

   Next steps:
   1. Review the draft: `cat .jira-release-drafts/20250209-183000-2025-1-0.md`
   2. Edit if needed (add context, reorder, etc.)
   3. Publish: `/dataops-assistant:jira-release-publish .jira-release-drafts/20250209-183000-2025-1-0.md`
   ```

---

## Output

After creating the draft file, respond with:

```
Draft saved to: .jira-release-drafts/{filename}

Version: {version_name} ({action}: {"will create new version" | "will update existing version"})
Issues found: {count}

Next steps:
1. Review the draft: `cat .jira-release-drafts/{filename}`
2. Edit if needed (add context, reorder items, etc.)
3. Publish: `/dataops-assistant:jira-release-publish .jira-release-drafts/{filename}`
```

---

## Rules

1. **NEVER use /tmp/** - All drafts go to `.jira-release-drafts/`
2. **NEVER touch Jira versions** - This skill only creates local files
3. **Include all required frontmatter** - action, project, version_name, source_query
4. **Always link issue keys** - Use full URLs so user can click to verify
5. **Determine action correctly** - Use "update" if version exists, "create" if not
6. **Handle empty results** - If no issues found, still create draft but note it's empty
