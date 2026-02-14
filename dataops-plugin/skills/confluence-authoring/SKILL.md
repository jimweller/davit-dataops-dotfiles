---
description: "Author Confluence pages using styled markdown. Creates pages as drafts for human review."
allowed-tools: ["Bash", "Read"]
model: opus
context: fork
---


# Confluence Authoring

You help users author **NEW** Confluence pages using styled markdown that converts to ADF automatically.

## IMPORTANT: Page Edits Are NOT Supported Here

**DO NOT edit existing pages with this skill.** Large pages will exhaust context.

For editing existing pages, use the file-based flow:
```bash
~/.dataops-assistant/bin/confluence-api.sh download <page_id> ./page.json
# Edit the JSON file directly
~/.dataops-assistant/bin/confluence-api.sh validate ./page.json
~/.dataops-assistant/bin/confluence-api.sh update <page_id> ./page.json
```

## Workflow

1. **Understand the request** - What page are they creating? What space/parent?
2. **Draft content** - Write styled markdown following the Style Guide below
3. **Execute** - Create the page as a draft using the create command
4. **Return result** - Provide the draft URL so the user can review and publish

Note: All pages are created as **drafts** - user reviews via the returned URL before publishing.

## Commands

```bash
# Create new page (as DRAFT by default)
echo 'markdown content' | ~/.dataops-assistant/bin/confluence-api.sh create <space_id> "<title>" - --md

# With parent page
echo 'markdown content' | ~/.dataops-assistant/bin/confluence-api.sh create <space_id> "<title>" - --md --parent <page_id>
```

**All pages are created as DRAFTS** - user must review and publish manually.

## Markdown Style Guide

### Metadata Table (top of page)
```markdown
:::metadata owner="@Terence Kent" date="2025-01-29" :::
```
Creates a styled table with dark headers showing owner and date.

### Table of Contents
```markdown
:::toc maxLevel=2 :::
```
Inserts Confluence TOC macro.

### Callout Box
```markdown
:::callout title="PLEASE READ" color=red
Important information here.
Multiple lines supported.
:::
```
Colors: `red`, `yellow`, `blue`, `green`, `purple`, `neutral`

### Headings
```markdown
# Page Title           (bold + grey)
## Major Section       (bold + grey)
##! Action Section     (bold + blue - use for action items!)
### Subsection         (bold + green)
#### Details           (bold + grey)
##### Minor Label      (grey only, no bold)
```

### Horizontal Rule
```markdown
---
```

### Status Lozenges
```markdown
{status:DRAFT:yellow}
{status:APPROVED:green}
{status:BLOCKED:red}
```
Colors: `neutral`, `purple`, `blue`, `green`, `yellow`, `red`

### Page Cards (inline links to Confluence pages)
```markdown
{pageCard:https://mcghealth.atlassian.net/wiki/spaces/SPACE/pages/123456789}
```

### Text Formatting
```markdown
**bold text**
*italic text*
`code text`
[link text](https://example.com)
```

### Lists
```markdown
- Bullet item one
- Bullet item two

1. Numbered item one
2. Numbered item two
```

### Tables
```markdown
| Header 1 | Header 2 |
|----------|----------|
| Cell 1   | Cell 2   |
```

## Example Page

```markdown
:::metadata owner="@Terence Kent" date="2025-01-29" :::

# Service Documentation

:::toc maxLevel=2 :::

## About

This service handles user authentication across all applications.

### Ownership

{status:Platform Team:blue} owns the infrastructure.

##! Action Required

The following items need attention:

:::callout title="MIGRATION NEEDED" color=yellow
Legacy auth endpoints will be deprecated Q2 2025.
See the migration guide for details.
:::

---

## Technical Details

| Component | Technology |
|-----------|------------|
| Auth Server | OAuth 2.0 |
| Token Store | Redis |

### Configuration

1. Set environment variables
2. Deploy helm chart
3. Verify health checks
```

## Output

Commands return JSON with the draft URL:

```json
{
  "action": "CREATE",
  "status": "success",
  "page_id": "123456789",
  "page_url": "https://mcghealth.atlassian.net/wiki/spaces/SPACE/pages/edit-v2/123456789?draftShareId=...",
  "page_status": "draft"
}
```

**Always show the `page_url` to the user** so they can review and publish the draft.

---

## Rules

1. **Pages are ALWAYS drafts** - Never publish directly
2. **Return the draft URL** - User must review before publishing
3. **Avoid AI-smelling formatting** - Use `->` not `→`, avoid excessive emoji, keep it natural
