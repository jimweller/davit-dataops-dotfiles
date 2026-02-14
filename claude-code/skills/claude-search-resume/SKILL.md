---
name: claude-search-resume
description: Search and load previous Claude Code conversations. Use when user wants to find or resume a past session.
---

# Claude Search & Resume

Search past conversations and help user resume them.

**Platforms:** Linux, macOS, Windows (Git Bash/WSL)

## When to use

- User asks to find/search a previous conversation
- User wants to resume work from another session
- User asks "where did we discuss X?"

## Usage

Run the script `scripts/claude-search-resume`:

```bash
# Search in current project
~/.claude/skills/claude-search-resume/scripts/claude-search-resume

# Search globally (all projects)
~/.claude/skills/claude-search-resume/scripts/claude-search-resume --global

# Search by keyword
~/.claude/skills/claude-search-resume/scripts/claude-search-resume "deploy" --global

# Search by date range
~/.claude/skills/claude-search-resume/scripts/claude-search-resume --from "2026-01-13 00:00" --to "2026-01-13 23:59"
```

## Output

```
1. [2026-01-14 10:27] /data/alexis/claude-tools (118 msgs)
   💬 j'aimerais ajouter au site front une librairie...
   ▶ claude --resume b8c31c5f-2739-4179-94ea-5b63ef4cabee
```

## Resume

Tell user to run:
```bash
claude --resume <session-id>
```

## Examples

| User says | Command |
|-----------|---------|
| "find my recent conversations" | `scripts/claude-search-resume` |
| "find conversations about auth" | `scripts/claude-search-resume "auth" --global` |
| "what did we work on yesterday?" | `scripts/claude-search-resume --global --from "2026-01-13"` |
| "find my CRM sessions" | `scripts/claude-search-resume "crm" --global` |
