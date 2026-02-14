# Developing the DataOps Assistant Plugin

This is the contributor guide for developing the plugin itself. Claude Code automatically loads development rules from `.claude/rules/` when working in relevant directories.

## Quick Start

```bash
# Run structural validation
./tests/lint.sh

# Run all unit tests
bats tests/

# Run a specific test file
bats tests/bootstrap.bats
```

## Development Rules (`.claude/rules/`)

When Claude Code is working in this repo, it auto-loads rules from `.claude/rules/`. These are path-scoped so you get relevant guidance based on what you're editing:

| File | Applies to | Covers |
|------|-----------|--------|
| `development.md` | All files | Adding skills/agents, script conventions, doc sync requirements |
| `testing.md` | `tests/**` | Bats patterns, test layers, `--separate-stderr`, skip guards |
| `scripts.md` | `skills/*/scripts/**` | Common library pattern, output conventions, error handling |
| `hooks.md` | `hooks/**`, `plugin.json` | Hook types, performance, conditional routing, anti-hallucination |

These files are committed to git so all contributors get them.

## Adding a New Skill or Agent

Update two places (detailed in `.claude/rules/development.md`):

1. **Create** `skills/<name>/SKILL.md` or `agents/<name>.md`
2. **Route** in `hooks/inject-routing-rules.sh` (with capability guards if needed)

Run `./tests/lint.sh` after any structural change.

## Environment and Script Conventions

See `.claude/rules/development.md` for full conventions. Key points:

- Bootstrap generates per-script wrappers in `~/.dataops-assistant/bin/`
- SKILL.md files invoke scripts via bin wrappers (`~/.dataops-assistant/bin/<script>.sh`)
- Scripts use `BASH_SOURCE` for path derivation, never `DATAOPS_ASSISTANT_ROOT`
- Bash is the default; Bun/JS available for complex string handling (already a dependency)

For background on `CLAUDE_PLUGIN_ROOT` vs `DATAOPS_ASSISTANT_ROOT`, see `docs/CLAUDE_PLUGIN_ROOT_KNOWLEDGE.md`.

## Testing

See `.claude/rules/testing.md` for detailed conventions (bats patterns, `--separate-stderr`, skip guards).

```bash
./tests/lint.sh     # Structural validation (fast, no auth)
bats tests/         # All unit tests
./tests/run-all.sh  # Golden tests (invokes Claude Code, slower)
```

## Personal Dev Notes

Create `CLAUDE.local.md` in the repo root for personal shortcuts and local environment notes. This file is gitignored.
