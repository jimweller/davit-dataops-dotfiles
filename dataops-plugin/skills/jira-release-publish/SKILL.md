---
description: "Publish a Jira release draft to create or update a version. Requires preview and approval."
allowed-tools: ["Bash", "Read", "Write", "AskUserQuestion"]
model: sonnet
context: fork
---


# Jira Release Publish

Publish a Jira release draft file to create a new version or update an existing version's description.

## CRITICAL: Preview Before All Mutations

**NEVER execute without showing the user a preview first.**

For every publish operation:
1. **Read** the draft file
2. **Validate** frontmatter completeness
3. **Show preview** with exact content
4. **Ask for approval** explicitly
5. **Only then** execute the command
6. **Update** draft file with published status

If the user hasn't approved, DO NOT execute.

---

## Workflow

1. **Read draft file** from provided path
2. **Parse frontmatter** and body content
3. **Validate** required fields (project, version_name, action)
4. **Show preview** in box format
5. **Ask** for explicit approval
6. **Execute** via jira-api.sh version-create or version-update
7. **Update draft** with `status: published` and `published_version_id`
8. **Return** version URL

---

## Input

User provides path to a draft file:
```
/dataops-assistant:jira-release-publish .jira-release-drafts/20250209-183000-2025-1-0.md
```

---

## Preview Format

### Create Version

```
+-----------------------------------------------------------+
| PREVIEW: Create Version                                    |
+-----------------------------------------------------------+
| Project: PE                                                |
| Version: 2025.1.0                                          |
| Release Date: 2025-02-15                                   |
| Mark Released: No                                          |
|                                                            |
| Description (first 500 chars):                             |
| -------------------------------------------                |
| ## Release 2025.1.0                                        |
|                                                            |
| Released: 2025-02-15                                       |
|                                                            |
| ### Features                                               |
| - [PE-1234]: Add user authentication flow                  |
| - [PE-1235]: Implement dashboard redesign...               |
+-----------------------------------------------------------+
```

### Update Version

```
+-----------------------------------------------------------+
| PREVIEW: Update Version                                    |
+-----------------------------------------------------------+
| Project: PE                                                |
| Version: 2025.1.0                                          |
| Mark Released: Yes                                         |
|                                                            |
| New Description (first 500 chars):                         |
| -------------------------------------------                |
| ## Release 2025.1.0                                        |
|                                                            |
| Released: 2025-02-15                                       |
|                                                            |
| ### Features                                               |
| - [PE-1234]: Add user authentication flow...               |
+-----------------------------------------------------------+
```

---

## Commands

**CRITICAL: Always use the bin wrapper.** Never call scripts by direct path.

```bash
# CORRECT — single unambiguous path
JIRA_API="$HOME/.dataops-assistant/bin/jira-api.sh"
```

### Create Version

```bash
# With description from stdin
echo "$description_content" | bash "$JIRA_API" version-create "$project" "$version_name" \
  --description - --md \
  --release-date "$release_date"  # if provided

# With --released flag
echo "$description_content" | bash "$JIRA_API" version-create "$project" "$version_name" \
  --description - --md --released
```

### Update Version

```bash
# Update description
echo "$description_content" | bash "$JIRA_API" version-update "$project" "$version_name" \
  --description - --md

# Update and mark released
echo "$description_content" | bash "$JIRA_API" version-update "$project" "$version_name" \
  --description - --md --released
```

---

## Validation Before Preview

### Required Fields

- `jira_release_version` must be "1"
- `action` must be "create" or "update"
- `project` must be present
- `version_name` must be present
- `status` must be "draft" (not already published)

### Validation Errors

```
X Cannot publish: Missing required field 'version_name'.
```

```
X Cannot publish: Draft already published (status: published).
   Use a new draft or reset status to 'draft'.
```

---

## Extracting Body Content

The draft file has YAML frontmatter followed by markdown body:

```bash
# Extract body (everything after second ---)
body_content=$(awk '/^---$/{n++; next} n>=2' "$draft_file")
```

Or in bash:

```bash
# Read file content
file_content=$(cat "$draft_file")

# Split on frontmatter delimiter
body_content="${file_content#*---}"  # Remove first ---
body_content="${body_content#*---}"  # Remove second ---
body_content="${body_content#$'\n'}" # Remove leading newline
```

---

## Post-Publish Updates

After successful publish, update the draft file:

1. Change `status: draft` to `status: published`
2. Add `published_version_id: 12345` (from API response)
3. Write updated file back

---

## Execution Flow

### For Create

```bash
# Build command
if [[ -n "$release_date" ]]; then
    date_flag="--release-date $release_date"
else
    date_flag=""
fi

if [[ "$mark_released" == "true" ]]; then
    released_flag="--released"
else
    released_flag=""
fi

# Execute
result=$(echo "$body_content" | bash "$JIRA_API" version-create \
    "$project" "$version_name" \
    --description - --md $date_flag $released_flag)

version_id=$(echo "$result" | jq -r '.version_id')
version_url=$(echo "$result" | jq -r '.version_url')
```

### For Update

```bash
if [[ "$mark_released" == "true" ]]; then
    released_flag="--released"
else
    released_flag=""
fi

result=$(echo "$body_content" | bash "$JIRA_API" version-update \
    "$project" "$version_name" \
    --description - --md $released_flag)

version_id=$(echo "$result" | jq -r '.version_id')
version_url=$(echo "$result" | jq -r '.version_url')
```

---

## Output

### Success

```
Published successfully!

Action: Create Version
Project: PE
Version: 2025.1.0
URL: https://mcghealth.atlassian.net/projects/PE/versions/12345

Draft updated: .jira-release-drafts/20250209-183000-2025-1-0.md
```

### Failure

```
X Publish failed:

Error: [error message from jira-api.sh]

Draft NOT modified. Fix the issue and try again.
```

---

## Example Session

**User:** `/dataops-assistant:jira-release-publish .jira-release-drafts/20250209-183000-2025-1-0.md`

**Response:**

```
+-----------------------------------------------------------+
| PREVIEW: Update Version                                    |
+-----------------------------------------------------------+
| Project: PE                                                |
| Version: 2025.1.0                                          |
| Release Date: 2025-02-15                                   |
| Mark Released: No                                          |
|                                                            |
| Description (first 500 chars):                             |
| -------------------------------------------                |
| ## Release 2025.1.0                                        |
|                                                            |
| Released: 2025-02-15                                       |
|                                                            |
| ### Features                                               |
| - [PE-1234]: Add user authentication flow                  |
| - [PE-1235]: Implement dashboard redesign                  |
|                                                            |
| ### Bug Fixes                                              |
| - [PE-1300]: Fix login timeout issue...                    |
+-----------------------------------------------------------+

Update this version in Jira?
```

**User:** Yes

**Response:**

```
Published successfully!

Action: Update Version
Project: PE
Version: 2025.1.0
URL: https://mcghealth.atlassian.net/projects/PE/versions/12345

Draft updated: .jira-release-drafts/20250209-183000-2025-1-0.md
```

---

## Rules

1. **ALWAYS preview before execution** - No exceptions
2. **ALWAYS ask for approval** - User must explicitly confirm
3. **Validate before preview** - Don't show preview if required fields missing
4. **Update draft after publish** - Mark as published with version ID
5. **Return URL** - User needs to verify the result
6. **Don't modify draft on failure** - Only update on success
7. **Check status field** - Refuse to publish already-published drafts
