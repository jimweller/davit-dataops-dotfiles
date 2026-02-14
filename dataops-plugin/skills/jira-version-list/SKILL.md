---
description: "List Jira versions for a project. Returns version names, IDs, release status, and dates."
allowed-tools: ["Bash"]
model: haiku
context: fork
agent: Explore
---


# Jira Version List

You list versions for a Jira project.

## Loading the Script

The jira-api.sh script is at:
```
~/.dataops-assistant/bin/jira-api.sh
```

## Input Format

The user provides: `{project_key}` or just asks to list versions for a project.

Examples:
- `PE`
- `ML`
- `list versions for DATA project`

## Instructions

1. Extract project key from input
2. Run the version-list command:
   ```bash
   bash ~/.dataops-assistant/bin/jira-api.sh version-list <project_key>
   ```
3. Format the output for readability

## Output Format

```
PROJECT: [project_key]

VERSIONS:
| Name | Released | Release Date | Description |
|------|----------|--------------|-------------|
| 2025.1.0 | Yes | 2025-01-15 | Q1 release... |
| 2025.2.0 | No | 2025-04-01 | Planned Q2... |
...

TOTAL: [count] versions
```

## Rules

- Show ALL versions (the API returns them sorted by release date)
- Truncate description to 50 chars with "..." if longer
- If no versions exist, report that clearly
- Include both released and unreleased versions
