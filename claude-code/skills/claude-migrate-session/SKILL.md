---
name: claude-migrate-session
description: Migrate a Claude Code session from another project folder to the current directory so claude --resume picks it up.
argument-hint: "[keyword]"
---

STARTER_CHARACTER = 🚚

# Claude Migrate Session

Migrate a conversation from another project to the current working directory.

## When to use

- User wants to continue a session that was started in a different project folder
- User wants to move a conversation to their current project

## Workflow

1. **Search** — Run the search script with `--global` (always global since migration implies cross-folder). Pass the user's keyword argument if provided. Multiple words are automatically OR-matched.

```bash
~/.claude/skills/claude-search-resume/scripts/claude-search-resume --global
~/.claude/skills/claude-search-resume/scripts/claude-search-resume "keyword" --global
```

2. **Filter & Display** — From the search results, discard any sessions whose project path matches the current working directory (these are already local and can't be migrated). Also discard the current active session. Show only the remaining results to the user. If only one foreign session remains, auto-select it. If multiple remain, ask the user which one to migrate (by number or session ID). If none remain, tell the user no migratable sessions were found.

3. **Migrate** — Run the migrate script with the chosen session ID:

```bash
~/.claude/skills/claude-migrate-session/scripts/claude-migrate-session --session-id <uuid>
```

4. **Instruct** — The script prints the new session UUID and a `claude --resume <new-id>` command. Tell the user to quit this session and run that exact `--resume` command. Do NOT suggest `--continue` — the current session will be newer and `--continue` would pick it up instead of the migrated one.

## Notes

- The migrate script copies (not moves) session files — the original session stays intact in the source project
- The destination gets a new UUID (via uuidgen) so source and destination sessions are fully independent
- The script handles both the `.jsonl` file and any subagents directory
