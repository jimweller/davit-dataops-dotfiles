# Global Claude Code Instructions

This file contains user-level preferences and instructions that apply to all
Claude Code sessions.

## Dotfiles Project Context

- This repo IS the dotfiles repo. When asked to change Claude Code settings, edit the files in `dotfiles/claude-code/` (both AWS and Azure variants), NOT the global `~/.claude/settings.json`.

## General Preferences

- Prefer concise, direct responses, almost robotic
- Never praise me or say that I am right
- Always be critical and present objective perspectives
- Avoid unnecessary verbosity or over-explanation
- Use existing code patterns and conventions when modifying projects
- Prefer current research over model training data

## Code Style

- Follow existing project/repo conventions when present
- Prefer simple, readable solutions over clever ones
- Avoid over-engineering or adding unnecessary abstractions
- Do not add comments to production code. Keep it clean unless asked.
- In docs, never add parenthetical clarifications like "(not X)" or "(NOT X)". State the correct value only.
- In bash scripts, never use `$'\uNNNN'` for Unicode characters. Bash `$'...'` only supports `\xHH` byte escapes. Use UTF-8 byte sequences instead (e.g., `$'\xEF\x8A\xBB'` for U+F2BB).

## Git Workflow

- Only commit when explicitly asked
- Use conventional commit message style when appropriate
- Use semanic branch and PR style
- Never force push without explicit permission

## Environment Sourcing

- ALWAYS source .envrc using the project CLAUDE.md pattern: `PROJECT_ROOT=$(git rev-parse --show-toplevel) && source "$PROJECT_ROOT/.envrc"`
- NEVER use `source .envrc` with a relative path
- This must happen before any operation that depends on environment variables

## Development Workflow

- Before writing any code, describe your approach and wait for approval
- Always ask clarifying questions before writing any code if requirements are ambiguous
- If a task requires changes to more than 3 files, stop and break it into smaller tasks first
- After writing code, list what could break and suggest tests to cover it
- When there's a bug, start by writing a test that reproduces it, then fix it until the test passes
- Every time the user corrects you, add a new rule to the CLAUDE.md file so it never happens again

## Claude Skills

### STARTER_CHARACTER Rules

- EVERY response must begin with STARTER_CHARACTER - NO EXCEPTIONS
- Default STARTER_CHARACTER is ✳️
- When a skill defines its own STARTER_CHARACTER, concatenate it after the default with a space (e.g., ✳️ 🎟️ when Jira skill is loaded)
- A skill is "active" when:
  - Invoked via the Skill tool
  - Its SKILL.md file is read to follow its guidelines
- Multiple skills can be active simultaneously (e.g., ✳️ 🎟️ 📝 for Jira + readme)
- This applies to ALL responses including:
  - After tool calls complete
  - Error messages
  - Follow-up questions
  - Acknowledgments
  - Short replies (e.g., "Done." becomes "✳️ Done.")
