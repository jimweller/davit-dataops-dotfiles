---
description: "Query Azure DevOps projects, repos, pipelines, and service connections via az CLI. Portable bash scripts with JSON output."
allowed-tools: ["Bash"]
model: sonnet
context: fork
status-check: scripts/status.sh
---


# ADO Query

Query Azure DevOps resources using portable bash scripts that wrap the `az devops` CLI.

## CRITICAL: Do Not Set Environment Variables

**NEVER set or export `AZURE_DEVOPS_ORG`**. This variable is already configured in the user's shell environment and will be inherited automatically.

- Run scripts directly without any `export` statements
- If the variable is missing, scripts will fail with a clear error - that's the user's problem to fix
- **NEVER guess or fabricate organization URLs**

**WRONG** (do not do this):
```bash
export AZURE_DEVOPS_ORG="https://dev.azure.com/guessed-org" && script.sh
```

**CORRECT**:
```bash
~/.dataops-assistant/bin/ado-projects.sh
```

## CRITICAL: User Identity

When the user says "I", "me", "my", or "what am I working on":
- **Do NOT pass a user argument** - let scripts auto-detect
- Scripts check `MCG_EMAIL` env var first, then fall back to `az account show`

**WRONG** (guessing user email):
```bash
ado-assigned-prs-fast.sh "guessed.email@company.com"
```

**CORRECT** (let script auto-detect):
```bash
~/.dataops-assistant/bin/ado-assigned-prs-fast.sh --project Platform
```

Only pass an explicit email when the user asks about a **specific other person** by name or email.

### Identity Helper

Scripts can use this function from `ado-common.sh`:
```bash
source "$SCRIPT_DIR/ado-common.sh"
email=$(ado::current_user_email)  # MCG_EMAIL or az fallback
```

## Prerequisites (for the user, not the agent)

1. `az` CLI installed
2. `azure-devops` extension: `az extension add --name azure-devops`
3. Authenticated: `az login`
4. Environment variables in shell profile (e.g., `.bashrc` or `.zshrc`):
   ```bash
   # Required
   export AZURE_DEVOPS_ORG="https://dev.azure.com/your-org"

   # Required for "my PRs" queries (falls back to az account if not set)
   export MCG_EMAIL="user@mcg.com"
   ```

## Default Project Configuration

PR and commit scripts require `--project` to avoid excessive API calls. You can configure default projects to avoid specifying `--project` every time:

```bash
mkdir -p ~/.dataops-assistant/ado-query
cat > ~/.dataops-assistant/ado-query/projects.yaml << 'EOF'
# Projects to query when --project is not specified
# Use --all-projects to override and query everything
projects:
  - Data Science
  - Platform
  - MCG DevOps
EOF
```

Resolution order:
1. `--project "X"` — query single project
2. `--all-projects` — query all projects (with warning)
3. Config file — query configured projects
4. Error — tells user how to fix

## Commands

All scripts output JSON to stdout, errors to stderr.

### List Projects

```bash
~/.dataops-assistant/bin/ado-projects.sh
~/.dataops-assistant/bin/ado-projects.sh "Platform"  # filter by name
```

Output: `[{id, name, description, state}]`

### List Repos

```bash
~/.dataops-assistant/bin/ado-repos.sh <project>
~/.dataops-assistant/bin/ado-repos.sh Platform "payment"  # filter
```

Output: `[{id, name, defaultBranch, webUrl, size}]`

### List Project Members

```bash
~/.dataops-assistant/bin/ado-project-members.sh <project>
```

Output: `[{displayName, principalName, mailAddress, origin}]`

Note: Enumerates security groups - may be slow for large projects.

### Get Repo Activity

```bash
~/.dataops-assistant/bin/ado-repo-activity.sh <project> <repo>
~/.dataops-assistant/bin/ado-repo-activity.sh Platform payment-service --since 2025-01-01 --top 50
~/.dataops-assistant/bin/ado-repo-activity.sh Platform payment-service --author "user@company.com"
```

Options:
- `--author <email>` - Filter commits by author
- `--since <YYYY-MM-DD>` - Commits after date
- `--top <N>` - Number of commits (default: 20)

Output: `{commitCount, recentCommits[], contributors[]}`

### List Pipelines

```bash
~/.dataops-assistant/bin/ado-pipelines.sh <project>
~/.dataops-assistant/bin/ado-pipelines.sh Platform "deploy"  # filter
```

Output: `[{id, name, folder, queueStatus, revision}]`

### Get Pipeline Runs

```bash
~/.dataops-assistant/bin/ado-pipeline-runs.sh <project> <pipeline-id>
~/.dataops-assistant/bin/ado-pipeline-runs.sh Platform 123 --top 10 --status completed
~/.dataops-assistant/bin/ado-pipeline-runs.sh Platform 123 --since 2025-01-01 --until 2025-01-31
```

Options:
- `--top <N>` - Number of runs (default: 20)
- `--since <YYYY-MM-DD>` - Runs after date
- `--until <YYYY-MM-DD>` - Runs before date
- `--status <status>` - Filter by status (completed, inProgress, etc.)

Output: `[{id, buildNumber, status, result, startTime, finishTime, requestedFor, sourceBranch}]`

### List Service Endpoints

```bash
~/.dataops-assistant/bin/ado-service-endpoints.sh <project>
~/.dataops-assistant/bin/ado-service-endpoints.sh Platform "azure"  # filter
```

Output: `[{id, name, type, url, isShared, isReady}]`

### Get Service Endpoint Details

```bash
~/.dataops-assistant/bin/ado-service-endpoint.sh <project> <endpoint-id>
```

Output: Full endpoint details (credentials masked)

### Repo Cache Setup

Commit queries use a local bare repo cache for instant, zero-API-call results. The cache must be populated before querying commits.

**First-time setup** — sync repos for your project(s):
```bash
~/.dataops-assistant/bin/ado-repo-cache-sync.sh --project "Data Science"
```

**Periodic refresh** — re-run to fetch new commits:
```bash
~/.dataops-assistant/bin/ado-repo-cache-sync.sh  # syncs all configured projects
```

**Check cache status** (no network):
```bash
~/.dataops-assistant/bin/ado-repo-cache-sync.sh --check
```

Options:
- `--project <project>` - Sync a single project
- `--all-projects` - Sync all org projects (slow first time)
- `--force` - Fetch regardless of hash match
- `--check` - Compare local vs remote hash only (no fetch)
- `--quiet` - Suppress progress messages

Output: JSON summary with per-repo sync status.

**Cache configuration** (`~/.dataops-assistant/ado-query/repo-cache.yaml`):
```yaml
# Optional: override cache location (default: ~/.dataops-assistant/ado-query-repo-cache)
# cache_dir: /data/ado-repo-cache

# Exclude specific projects
exclude_projects:
  - Archived Project

# Exclude specific repos (format: "Project/repo-name")
exclude_repos:
  - "Data Science/huge-ml-models"
```

Cache uses bare blobless clones (`git clone --bare --filter=blob:none`) — only commit/tree metadata, no file content. Typical savings: 80-95% vs full clone.

### List Recent Commits by User (user-commits)

Queries commits from the local repo cache. **Requires cache to be populated first** (see Repo Cache Setup above).

```bash
~/.dataops-assistant/bin/ado-user-commits-cached.sh --project Platform           # current user, last 30 days
~/.dataops-assistant/bin/ado-user-commits-cached.sh --project Platform "user@company.com"  # specific user
~/.dataops-assistant/bin/ado-user-commits-cached.sh --project Platform --since 2025-01-01 --top 20
~/.dataops-assistant/bin/ado-user-commits-cached.sh --all-projects               # all cached projects (instant)
```

Options:
- `--project <project>` - Project to query from cache.
- `--all-projects` - Query all cached projects (instant, no API calls)
- `[user]` - User email (default: current authenticated user)
- `--since <YYYY-MM-DD>` - Commits after date (default: 30 days ago)
- `--top <N>` - Max total results (default: 50)

Output: `[{project, repository, commitId, fullCommitId, author, email, date, comment, webUrl}]`

Performance: Queries local git repos with `git log --all` — zero API calls, instant results. Searches ALL branches (feature, bugfix, etc.).

### List PRs Created by User (assigned-prs)

**IMPORTANT**: `--project` is required to avoid excessive API calls. Use `--all-projects` only when necessary.

```bash
~/.dataops-assistant/bin/ado-assigned-prs-fast.sh --project Platform                      # current user, active
~/.dataops-assistant/bin/ado-assigned-prs-fast.sh --project Platform "user@company.com"   # specific user
~/.dataops-assistant/bin/ado-assigned-prs-fast.sh --project Platform --status all         # include completed
~/.dataops-assistant/bin/ado-assigned-prs-fast.sh --project Platform --status all --since 2025-01-01  # completed after date
~/.dataops-assistant/bin/ado-assigned-prs-fast.sh --all-projects                          # org-wide (slow, many API calls)
```

Options:
- `--project <project>` - **Required.** Project to query.
- `--all-projects` - Query all projects (slow, may trigger API rate limiting)
- `[user]` - User email (default: current authenticated user)
- `--status <status>` - Filter by status (active, completed, all). Default: active
- `--since <YYYY-MM-DD>` - Only include PRs created on or after this date

Output: `[{project, pullRequestId, title, status, createdBy, creationDate, sourceRefName, targetRefName, repository, webUrl}]`

### List PRs Where User is Reviewer (reviewed-prs)

**IMPORTANT**: `--project` is required to avoid excessive API calls. Use `--all-projects` only when necessary.

```bash
~/.dataops-assistant/bin/ado-reviewed-prs-fast.sh --project Platform                      # current user, active
~/.dataops-assistant/bin/ado-reviewed-prs-fast.sh --project Platform "user@company.com"   # specific user
~/.dataops-assistant/bin/ado-reviewed-prs-fast.sh --project Platform --status all         # include completed
~/.dataops-assistant/bin/ado-reviewed-prs-fast.sh --project Platform --status all --since 2025-01-01  # completed after date
~/.dataops-assistant/bin/ado-reviewed-prs-fast.sh --all-projects                          # org-wide (slow, many API calls)
```

Options:
- `--project <project>` - **Required.** Project to query.
- `--all-projects` - Query all projects (slow, may trigger API rate limiting)
- `[user]` - User email (default: current authenticated user)
- `--status <status>` - Filter by status (active, completed, all). Default: active
- `--since <YYYY-MM-DD>` - Only include PRs created on or after this date

Output: `[{project, pullRequestId, title, status, createdBy, creationDate, sourceRefName, targetRefName, repository, webUrl}]`

### List PRs With User Activity (my-pr-activity)

Shows PRs where the user is either the creator or a reviewer. Uses parallel queries for performance.

**IMPORTANT**: `--project` is required to avoid excessive API calls. Use `--all-projects` only when necessary.

**NOTE**: Does not include PRs where user only commented (would require expensive per-PR queries).

```bash
~/.dataops-assistant/bin/ado-my-pr-activity.sh --project Platform                         # current user, active
~/.dataops-assistant/bin/ado-my-pr-activity.sh --project Platform "user@company.com"      # specific user
~/.dataops-assistant/bin/ado-my-pr-activity.sh --project Platform --status all            # include completed
~/.dataops-assistant/bin/ado-my-pr-activity.sh --project Platform --status all --since 2025-01-01  # completed after date
~/.dataops-assistant/bin/ado-my-pr-activity.sh --all-projects                             # org-wide (slow, many API calls)
```

Options:
- `--project <project>` - **Required.** Project to query.
- `--all-projects` - Query all projects (slow, may trigger API rate limiting)
- `[user]` - User email (default: current authenticated user)
- `--status <status>` - Filter by status (active, completed, all). Default: active
- `--since <YYYY-MM-DD>` - Only include PRs created on or after this date

Output: `[{project, pullRequestId, title, status, createdBy, creationDate, sourceRefName, targetRefName, repository, webUrl, activityTypes: ["creator"|"reviewer"]}]`

## Common Query Patterns

### Who owns a service?

```bash
# Find repos matching service name
~/.dataops-assistant/bin/ado-repos.sh Platform "payment"

# Get recent contributors
~/.dataops-assistant/bin/ado-repo-activity.sh Platform payment-service --top 50
```

### What's been deployed recently?

```bash
# Find the pipeline
~/.dataops-assistant/bin/ado-pipelines.sh Platform "deploy"

# Get recent runs
~/.dataops-assistant/bin/ado-pipeline-runs.sh Platform 456 --top 10
```

### What projects exist?

```bash
~/.dataops-assistant/bin/ado-projects.sh
```

### What service connections are available?

```bash
~/.dataops-assistant/bin/ado-service-endpoints.sh Platform
```

### What have I committed recently?

```bash
# First time: sync the repo cache
~/.dataops-assistant/bin/ado-repo-cache-sync.sh --project Platform

# My commits in a project (last 30 days, instant from cache)
~/.dataops-assistant/bin/ado-user-commits-cached.sh --project Platform

# Another person's commits
~/.dataops-assistant/bin/ado-user-commits-cached.sh --project Platform "colleague@company.com" --since 2025-01-15
```

### What PRs need my attention?

```bash
# PRs I created (waiting for review)
~/.dataops-assistant/bin/ado-assigned-prs-fast.sh --project Platform

# PRs I need to review
~/.dataops-assistant/bin/ado-reviewed-prs-fast.sh --project Platform

# All my PR activity (created + reviewing)
~/.dataops-assistant/bin/ado-my-pr-activity.sh --project Platform
```

## Workflow

1. **Identify the resource type** - projects, repos, pipelines, etc.
2. **Run the appropriate script** - start broad, then filter
3. **Format output** - Present results as markdown tables
4. **Follow up** - Use IDs from list commands to get details

## Output Format

Present results as markdown tables:

```markdown
## ADO Query: Pipelines in Platform

| ID | Name | Status |
|----|------|--------|
| 123 | payment-deploy | enabled |
| 456 | checkout-ci | enabled |

**Found:** 2 pipelines
```

For empty results:

```markdown
## ADO Query: Pipelines in Platform

No pipelines found matching "nonexistent".

**Suggestions:**
- Check project name spelling
- Try broader search pattern
- List all pipelines without filter
```

## Error Handling

**AZURE_DEVOPS_ORG not set:**
```bash
export AZURE_DEVOPS_ORG="https://dev.azure.com/your-org"
```

**Extension not installed:**
```bash
az extension add --name azure-devops
```

**Not authenticated:**
```bash
az login
```

**Project not found:**
- Check project name spelling
- Use `ado-projects.sh` to list available projects
