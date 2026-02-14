---
name: md-syntax
description: Guidelines for markdown syntax and formatting rules
user-invocable: false
---

STARTER_CHARACTER = 🔏

# Markdown Authoring Guidelines

Follow these rules when creating or editing markdown files.

## Rules

- **Always specify language on code blocks** - Use `bash`, `yaml`, `json`, `text`, `hcl`, `go`, etc. Never use bare ` ``` `
- **No AI slop** - Never use Emojis or emdashes
- **Use headings, not bold for section titles** - Use proper heading levels (`##`, `###`, etc.) not `**Bold**` on its own line
- **One H1 per file** - Only one `# Title` at the top
- **First line should be H1** - Start files with `# Title`
- **Run md-lint skill** - Use `/md-lint` to format and lint after writing the file

## Examples

### Code Blocks

Always specify language

CORRECT with language
```bash
#!/bin/bash
```

INCORRECT without language
```
#!/bin/bash
```

### Headings vs Bold

INCORRECT bold as headding
```markdown
**Status: Not Implemented**
Some description...
```

CORRECT use appropriate heading level
```markdown
### Status

Not Implemented

Some description...

```

### Trailing New Line

Always include a single trailing newline so the file ends in a blank line

INCORRECT no trailing newline
```markdown
The End.
```

CORRECT trailing newline
```markdown
The End.

```

### Empty Line Between Markdown Styles

Always add an empty line between different markdown styles like paragraphs, headings, lists, codeb blocks, block quotes etc

INCORRECT no empty line after headding
```markdown
## Hello
There
```

CORRECT empty line after headding
```markdown
## Hello

There
```

INCORRECT no empty line before list
```markdown
Hello there
- thing 1
- thing 2
```

CORRECT empty line after headding
```markdown
Hello there

- thing 1
- thing 2
```
