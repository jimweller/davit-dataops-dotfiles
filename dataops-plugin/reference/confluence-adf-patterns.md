# Confluence ADF Patterns Reference

This document contains ADF snippets extracted from MCG team page templates. Use these patterns to maintain visual consistency across documentation.

## Color Palette

### Text Colors
| Name | Hex | Usage |
|------|-----|-------|
| Section Gray | `#97a0af` | Main section headings (H1, H2) |
| Component Blue | `#0747a6` | Team/service names, H3 titles |
| Subsection Blue | `#4c9aff` | H5 subsection headers |
| Navy | `#003366` | H3 technical subsections |
| Info Purple | `#666699` | Info callout text |
| Success Navy | `#000080` | Success callout text |
| White | `#ffffff` | Text on dark backgrounds |
| Black | `#000000` | Standard body text |

### Background Colors
| Name | Hex | Usage |
|------|-----|-------|
| Slate Header | `#42526e` | Table headers (metadata) |
| Info Blue | `#DEEBFF` | Info panel background |
| Success Green | `#E3FCEF` | Success highlights |
| Warning Yellow | `#FFFAE6` | Warning highlights |
| Error Red | `#FFEBE6` | Error highlights |

---

## Heading Patterns

### Section Header (Gray + Bold)
Used for main page sections like "About", "Contents", "How it works".

```json
{
  "type": "heading",
  "attrs": {"level": 1},
  "content": [{
    "type": "text",
    "text": "How it works",
    "marks": [
      {"type": "textColor", "attrs": {"color": "#97a0af"}},
      {"type": "strong"}
    ]
  }]
}
```

### Component/Team Name Header (Blue)
Used for team names, service names in lists.

```json
{
  "type": "heading",
  "attrs": {"level": 3},
  "content": [{
    "type": "text",
    "text": "Core Services Platform Team",
    "marks": [
      {"type": "textColor", "attrs": {"color": "#0747a6"}}
    ]
  }]
}
```

### Subsection Header (Light Blue)
Used for technical subsections like "Pipeline Design", "Database discovery".

```json
{
  "type": "heading",
  "attrs": {"level": 5},
  "content": [{
    "type": "text",
    "text": "Pipeline Design",
    "marks": [
      {"type": "textColor", "attrs": {"color": "#4c9aff"}}
    ]
  }]
}
```

### Technical Sub-subsection (Navy + Bold)
Used for command/tool-specific sections.

```json
{
  "type": "heading",
  "attrs": {"level": 3},
  "content": [
    {"type": "text", "text": "Using "},
    {"type": "text", "text": "kubectl", "marks": [{"type": "code"}]},
    {
      "type": "text",
      "text": " (single pods)",
      "marks": [
        {"type": "textColor", "attrs": {"color": "#003366"}},
        {"type": "strong"}
      ]
    }
  ]
}
```

### Centered Heading
Used for revision history, change log sections.

```json
{
  "type": "heading",
  "attrs": {"level": 1},
  "marks": [{"type": "alignment", "attrs": {"align": "center"}}],
  "content": [{
    "type": "text",
    "text": "Revision History",
    "marks": [{"type": "textColor", "attrs": {"color": "#97a0af"}}]
  }]
}
```

---

## Table Patterns

### Metadata Table (Dark Header)
Used for "Content Owner", "Last Updated" at page top.

```json
{
  "type": "table",
  "attrs": {"layout": "full-width"},
  "content": [
    {
      "type": "tableRow",
      "content": [
        {
          "type": "tableHeader",
          "attrs": {
            "colspan": 1,
            "rowspan": 1,
            "background": "#42526e",
            "colwidth": [179]
          },
          "content": [{
            "type": "paragraph",
            "content": [{
              "type": "text",
              "text": "Content Owner",
              "marks": [{"type": "textColor", "attrs": {"color": "#ffffff"}}]
            }]
          }]
        },
        {
          "type": "tableCell",
          "attrs": {"colspan": 1, "rowspan": 1, "colwidth": [161]},
          "content": [{
            "type": "paragraph",
            "content": [{
              "type": "mention",
              "attrs": {"id": "USER_ID", "text": "@Person Name"}
            }]
          }]
        }
      ]
    }
  ]
}
```

### Component Card Table
Single-cell table used as a "card" for components/services.

```json
{
  "type": "table",
  "attrs": {"layout": "default", "width": 760},
  "content": [{
    "type": "tableRow",
    "content": [{
      "type": "tableCell",
      "attrs": {"colspan": 1, "rowspan": 1},
      "content": [
        {
          "type": "heading",
          "attrs": {"level": 3},
          "content": [{
            "type": "text",
            "text": "Service Name",
            "marks": [
              {"type": "textColor", "attrs": {"color": "#0747a6"}},
              {"type": "strong"}
            ]
          }]
        },
        {
          "type": "paragraph",
          "content": [{"type": "text", "text": "Description of the service."}]
        },
        {
          "type": "paragraph",
          "content": [{"type": "text", "text": "Links", "marks": [{"type": "strong"}]}]
        },
        {
          "type": "bulletList",
          "content": [
            {
              "type": "listItem",
              "content": [{
                "type": "paragraph",
                "content": [
                  {
                    "type": "text",
                    "text": "Repository",
                    "marks": [{"type": "link", "attrs": {"href": "https://..."}}]
                  },
                  {"type": "text", "text": ": Description"}
                ]
              }]
            }
          ]
        }
      ]
    }]
  }]
}
```

---

## Status & Callout Patterns

### Status Lozenge
Used for team roles, status indicators.

```json
{
  "type": "status",
  "attrs": {
    "text": "Source / Db Owner",
    "color": "blue",
    "style": "bold",
    "localId": "UUID-HERE"
  }
}
```

Available colors: `neutral`, `purple`, `blue`, `green`, `yellow`, `red`

### Info Callout (Indented)
Used for helpful tips and notes.

```json
{
  "type": "paragraph",
  "marks": [{"type": "indentation", "attrs": {"level": 1}}],
  "content": [{
    "type": "text",
    "text": "ℹ️ Traces are useful for tracking individual requests.",
    "marks": [
      {"type": "textColor", "attrs": {"color": "#666699"}},
      {"type": "strong"}
    ]
  }]
}
```

### Success Callout
Used for positive confirmations.

```json
{
  "type": "paragraph",
  "content": [{
    "type": "text",
    "text": "✅ Backwards compatible releases can be done at any time.",
    "marks": [
      {"type": "textColor", "attrs": {"color": "#000080"}},
      {"type": "strong"},
      {"type": "em"}
    ]
  }]
}
```

### Warning Panel
Built-in panel for warnings.

```json
{
  "type": "panel",
  "attrs": {"panelType": "warning"},
  "content": [{
    "type": "paragraph",
    "content": [{"type": "text", "text": "Warning message here."}]
  }]
}
```

Panel types: `info`, `note`, `warning`, `success`, `error`

### Note Panel with Title
Panel with emphasized title.

```json
{
  "type": "panel",
  "attrs": {"panelType": "note"},
  "content": [
    {
      "type": "paragraph",
      "content": [{
        "type": "text",
        "text": "Context on detecting not-yet-setup databases",
        "marks": [{"type": "strong"}]
      }]
    },
    {
      "type": "paragraph",
      "content": [{"type": "text", "text": "Body text explaining the context..."}]
    }
  ]
}
```

---

## Layout Patterns

### Two-Column Layout (33/66 Split)
Standard documentation layout with sidebar.

```json
{
  "type": "layoutSection",
  "marks": [{"type": "breakout", "attrs": {"mode": "wide", "width": 1800}}],
  "content": [
    {
      "type": "layoutColumn",
      "attrs": {"width": 33.33},
      "content": [/* Sidebar content: metadata table, TOC, links */]
    },
    {
      "type": "layoutColumn",
      "attrs": {"width": 66.66},
      "content": [/* Main content */]
    }
  ]
}
```

### Horizontal Rule
Section separator.

```json
{"type": "rule"}
```

---

## Code Patterns

### Code Block with Language
```json
{
  "type": "codeBlock",
  "attrs": {"language": "shell"},
  "content": [{
    "type": "text",
    "text": "aws-vault exec YOUR_AWS_ACCOUNT -- kubectl ..."
  }]
}
```

### Inline Code
```json
{
  "type": "text",
  "text": "helmfile",
  "marks": [{"type": "code"}]
}
```

---

## Link Patterns

### External Link
```json
{
  "type": "text",
  "text": "Display Text",
  "marks": [{
    "type": "link",
    "attrs": {"href": "https://external-url.com"}
  }]
}
```

### Internal Confluence Link
```json
{
  "type": "text",
  "text": "Page Title",
  "marks": [{
    "type": "link",
    "attrs": {
      "href": "https://mcghealth.atlassian.net/wiki/spaces/SPACE/pages/123456789",
      "__confluenceMetadata": {
        "linkType": "page",
        "contentTitle": "Page Title",
        "versionAtSave": "1"
      }
    }
  }]
}
```

### Inline Card (Smart Link)
Auto-renders page title and icon.

```json
{
  "type": "inlineCard",
  "attrs": {"url": "https://mcghealth.atlassian.net/wiki/spaces/SPACE/pages/123456789"}
}
```

---

## Other Elements

### Mention
```json
{
  "type": "mention",
  "attrs": {
    "id": "ATLASSIAN_ACCOUNT_ID",
    "text": "@Person Name"
  }
}
```

### Date
```json
{
  "type": "date",
  "attrs": {"timestamp": "1766016000000"}
}
```

### Emoji
```json
{
  "type": "emoji",
  "attrs": {
    "id": "atlassian-warning",
    "text": ":warning:",
    "shortName": ":warning:"
  }
}
```

Common emoji IDs: `atlassian-warning`, `atlassian-question_mark`, `atlassian-info`

### TOC Macro
```json
{
  "type": "extension",
  "attrs": {
    "extensionType": "com.atlassian.confluence.macro.core",
    "extensionKey": "toc",
    "parameters": {
      "macroParams": {
        "maxLevel": {"value": "1"},
        "minLevel": {"value": "1"}
      }
    }
  }
}
```

---

## Document Structure Template

Standard MCG documentation page structure:

```json
{
  "version": 1,
  "type": "doc",
  "content": [
    // Optional: Full-width rule
    {"type": "rule"},

    // Main layout section
    {
      "type": "layoutSection",
      "marks": [{"type": "breakout", "attrs": {"mode": "wide", "width": 1800}}],
      "content": [
        // Left column (33%)
        {
          "type": "layoutColumn",
          "attrs": {"width": 33.33},
          "content": [
            // Metadata table
            // "About" section header
            // "Contents" section with TOC
          ]
        },
        // Right column (66%)
        {
          "type": "layoutColumn",
          "attrs": {"width": 66.66},
          "content": [
            // Page title (H1, gray)
            // Main content sections
          ]
        }
      ]
    },

    // Footer section (change log)
    {
      "type": "layoutSection",
      "content": [
        {
          "type": "layoutColumn",
          "attrs": {"width": 100},
          "content": [
            // Centered "Change Log" header
            // Revision entries
          ]
        }
      ]
    }
  ]
}
```
