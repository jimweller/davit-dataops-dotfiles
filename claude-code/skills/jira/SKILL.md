---
name: jira
description: Jira conventions and operations. Always use when when working with jira issues, tickets, stories, tasks, epics, comments, or attachments.
user-invocable: false
---

STARTER_CHARACTER = 🎟️

# JIRA Conventions

Jira is an issue tracking sytem. Use the atl mcp, jira cli, and jira api with curl according to the directions for the entity and operation.

## Instance

Use environment variables for JIRA configuration:

| Variable         | Description                                         |
| ---------------- | --------------------------------------------------- |
| `JIRA_URL`       | Base URL (e.g., `https://mcghealth.atlassian.net/`) |
| `JIRA_EMAIL`     | User email for authentication                       |
| `JIRA_API_TOKEN` | API token for authentication                        |

- Browse URL: `${JIRA_URL}browse/{KEY}`

## MCP Tool Data Types

When calling tools, use correct data types for parameters:

| Type    | Example                       | Wrong                              |
| ------- | ----------------------------- | ---------------------------------- |
| Integer | `limit=10`                    | `limit="10"`                       |
| String  | `issue_key="DEVX-123"`        | `issue_key=DEVX-123`               |
| Object  | `fields={"summary": "Title"}` | `fields="{\"summary\": \"Title\"}"` |
| Array   | `labels=["bug", "urgent"]`    | `labels="[\"bug\", \"urgent\"]"`   |

Incorrect types cause validation errors like: `'10' is not of type 'integer'`

**Known bug:** `mcp__atl__jira_update_issue` cannot set numeric custom fields (e.g., story points). The `fields` dict gets serialized to a string by pydantic, causing either a validation error or a Jira rejection. Use the curl approach for numeric custom fields (see Story Points section below).

## Issue Key Recognition

`{KEY}` refers to the normalized JIRA issue key in format `PROJ-###` (e.g., `DEVX-209`).

The default jira project is DEVX. DEVX-###.

Accept flexible input formats:

- `PROJ-209` (full key)
- `proj-209` (lowercase)
- `PROJ209` (no hyphen)
- `proj209` (lowercase, no hyphen)
- `209` (number only, requires project context)

Always normalize to uppercase with hyphen: `DEVX-209`

## Writing Standards

- No emojis
- No glyphs
- No emdashes
- Direct, technical language
- Clear imperative sentences

## Formatting Conventions

- Prose is normal paragraphs
- Code and commands use code blocks
- Citations from documentation or other people use block quotes

## MCP ATL Markup Format

**IMPORTANT:** The MCP ATL tools (`mcp__atl__jira_create_issue`, `mcp__atl__jira_update_issue`, `mcp__atl__jira_add_comment`) convert Markdown to Jira wiki format automatically.

### Use Markdown for content

Code blocks with shebangs:
```
#!/bin/bash
set -euo pipefail
```

Nested lists (use indentation):
- Level 1
  - Level 2
    - Level 3

### Wiki markup panels are supported

Panels can wrap markdown content:
```
{panel:bgColor=#deebff}
### Context
Content here uses markdown.
{panel}
```

### Do NOT use wiki markup for content

Passing wiki markup for regular content causes double-conversion bugs:
- `{code}#!/bin/bash{code}` → `#` becomes `h1.`
- `** nested item` → `**` becomes `__`

### Known Limitations

- **Code blocks with `#`** - Fixed in [PR #894](https://github.com/sooperset/mcp-atlassian/pull/894), pending merge. Using local fork at `~/tmp/mcp-atlassian` until released.
- Jira does not support syntax highlighting in code blocks

## Description Format

Use panel template for new issues (panel is wiki markup, content is markdown):

```
{panel:bgColor=#deebff}
### Context
<narrative: background, expected outcomes, why this matters>
{panel}

### The Work
<bullet points of tasks to complete>

### Details
<optional: technical information - config values, resources, commands, data>
```

## Operations

# Epic

## create

```
mcp__atl__jira_create_issue(
  project_key="PROJ",
  issue_type="Epic",
  summary="Epic title",
  description="{panel:bgColor=#deebff}\n### Context\nBackground and why this matters.\n{panel}\n\n### The Work\n- First task\n- Second task\n\n### Details\nTechnical information."
)
```

## read

```
mcp__atl__jira_get_issue(
  issue_key="PROJ-123"
)
```

## update

```
mcp__atl__jira_update_issue(
  issue_key="PROJ-123",
  fields={
    "summary": "New title",
    "description": "{panel:bgColor=#deebff}\n### Context\nUpdated background.\n{panel}\n\n### The Work\n- Updated tasks\n\n### Details\nUpdated details."
  }
)
```

## cancel

```
mcp__atl__jira_transition_issue(
  issue_key="PROJ-123",
  transition_id="91"
)
```

## list children

```
jira issue list -q "parent = PROJ-123" -p PROJ --plain
```

# Task

## create

```
mcp__atl__jira_create_issue(
  project_key="PROJ",
  issue_type="Task",
  summary="Task title",
  description="{panel:bgColor=#deebff}\n### Context\nBackground and why this matters.\n{panel}\n\n### The Work\n- First task\n- Second task\n\n### Details\nTechnical information."
)
```

## create with parent

```
mcp__atl__jira_create_issue(
  project="PROJ",
  issue_type="Task",
  summary="Task title",
  description="{panel:bgColor=#deebff}\n### Context\nBackground and why this matters.\n{panel}\n\n### The Work\n- First task\n- Second task\n\n### Details\nTechnical information.",
  additional_fields={"parent": "PROJ-123"}
)
```

## read

```
mcp__atl__jira_get_issue(
  issue_key="PROJ-456"
)
```

## update

```
mcp__atl__jira_update_issue(
  issue_key="PROJ-456",
  fields={
    "summary": "New title",
    "description": "{panel:bgColor=#deebff}\n### Context\nUpdated background.\n{panel}\n\n### The Work\n- Updated tasks\n\n### Details\nUpdated details."
  }
)
```

## cancel

```
mcp__atl__jira_transition_issue(
  issue_key="PROJ-456",
  transition_id="91"
)
```

## search

```
jira issue list -q "project = PROJ AND status != Done ORDER BY created DESC" -p PROJ --plain
```

# Link

## link to epic

```
mcp__atl__jira_link_to_epic(
  issue_key="PROJ-456",
  epic_key="PROJ-123"
)
```

## create link

```
mcp__atl__jira_create_issue_link(
  inward_issue_key="PROJ-456",
  outward_issue_key="PROJ-789",
  link_type="Blocks"
)
```

Common link types: Blocks, Dependency, Duplicate, Relates, Parent/Child

## get types

```
mcp__atl__jira_get_link_types()
```

## remove

```
mcp__atl__jira_remove_issue_link(
  issue_key="PROJ-456",
  link_id="12345"
)
```

# Assignment

## assign

```
mcp__atl__jira_update_issue(
  issue_key="PROJ-456",
  fields={"assignee": "user@example.com"}
)
```

## unassign

```
mcp__atl__jira_update_issue(
  issue_key="PROJ-456",
  fields={"assignee": null}
)
```

## get user

```
mcp__atl__jira_get_user_profile()
```

# Transition/Move

## get available

```
mcp__atl__jira_get_transitions(
  issue_key="PROJ-456"
)
```

## change status

```
mcp__atl__jira_transition_issue(
  issue_key="PROJ-456",
  transition_id="31"
)
```

**Rule:** When transitioning an issue to Done, always assign it to the current user (from `JIRA_EMAIL`) if unassigned. Use the curl approach for assignment since the MCP tool has serialization issues with the assignee field.

# Comment

## add

```
mcp__atl__jira_add_comment(
  issue_key="PROJ-456",
  comment="Comment text here."
)
```

## read

```
mcp__atl__jira_get_issue(
  issue_key="PROJ-456",
  fields="summary,comment",
  comment_limit=10
)
```

Note: The `comment` field must be included in `fields` to retrieve comments. The `comment_limit` parameter only limits how many are returned.

## update

```
curl -X PUT \
  -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"body":"Updated comment text."}' \
  "${JIRA_URL}rest/api/2/issue/PROJ-456/comment/12345"
```

## delete

```
curl -X DELETE \
  -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  "${JIRA_URL}rest/api/2/issue/PROJ-456/comment/12345"
```

# Attachment

## add

```
mcp__atl__jira_update_issue(
  issue_key="PROJ-456",
  fields={},
  attachments="/path/to/file.pdf"
)
```

## read

```
mcp__atl__jira_get_issue(
  issue_key="PROJ-456",
  fields="attachment"
)
```

The attachment ID is in the response at attachments array.

## download

```
mcp__atl__jira_download_attachments(
  issue_key="PROJ-456",
  download_path="/tmp/downloads"
)
```

## delete

```
curl -X DELETE \
  -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  "${JIRA_URL}rest/api/3/attachment/12345"
```

# Priority

## get

```
mcp__atl__jira_get_issue(
  issue_key="PROJ-456"
)
```

The priority is in the response at priority.name.

## set

```
mcp__atl__jira_update_issue(
  issue_key="PROJ-456",
  fields={"priority": {"name": "High"}}
)
```

Valid values: Highest, High, Medium, Low, Lowest

# Label

## add

First get current labels, then update with the merged list.

```
mcp__atl__jira_get_issue(
  issue_key="PROJ-456"
)
```

```
mcp__atl__jira_update_issue(
  issue_key="PROJ-456",
  fields={"labels": ["existing-label", "new-label"]}
)
```

## remove

First get current labels, then update with the filtered list.

```
mcp__atl__jira_get_issue(
  issue_key="PROJ-456"
)
```

```
mcp__atl__jira_update_issue(
  issue_key="PROJ-456",
  fields={"labels": ["remaining-label"]}
)
```

## list

```
mcp__atl__jira_get_issue(
  issue_key="PROJ-456"
)
```

Labels are in the response at labels array.

# Story Points

Custom field: `customfield_10814` (Story point estimate)

The MCP ATL tool cannot set this field due to a numeric type serialization bug. Use curl instead.

## set

```
curl -s -X PUT \
  -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"fields":{"customfield_10814":0.5}}' \
  "${JIRA_URL}rest/api/2/issue/PROJ-456"
```

## set with assignee (bulk pattern)

```
for KEY in DEVX-101 DEVX-102 DEVX-103; do
  curl -s -X PUT \
    -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"fields":{"assignee":{"emailAddress":"user@example.com"},"customfield_10814":0.5}}' \
    "${JIRA_URL}rest/api/2/issue/${KEY}"
done
```

## get

```
mcp__atl__jira_get_issue(
  issue_key="PROJ-456",
  fields="summary,customfield_10814"
)
```

The value is at customfield_10814 in the response. Common values: 0.5, 1, 2, 3, 5, 8, 13.
