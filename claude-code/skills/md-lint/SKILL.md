---
name: md-lint
description: Format and lint markdown files using prettier and markdownlint-cli2. Always use the skill after writing markdown files (*.md) intended for humans.
---

STARTER_CHARACTER = 🔏


# Markdown Lint

Format and lint markdown files with auto-fix enabled.

## Usage

if $ARGUMENTS is empty, process all markdown files in the repository
if $ARGUMENTS is not empty, process only the markdown files specified as arguments


To fix all markdown files in the repository, run from the git root:

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT"
prettier --config ~/.prettierrc --write "**/*.md" --ignore-path .gitignore && markdownlint-cli2 --config ~/.config/markdownlint/.markdownlint-cli2.jsonc --fix "**/*.md"
```

To fix a specific file (can run from any directory):

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
prettier --config ~/.prettierrc --write "path/to/file.md" && markdownlint-cli2 --config ~/.config/markdownlint/.markdownlint-cli2.jsonc --fix "path/to/file.md"
```

## Notes

- Some markdownlint rules (like MD060) are not auto-fixable, but prettier handles them
- If an error cannot be fixed automatically by prettier, ask the user if you should fix them manually for the user.
