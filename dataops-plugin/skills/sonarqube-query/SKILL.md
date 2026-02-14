---
description: "Query SonarQube projects, issues, quality gates. Transition issues (accept, won't fix, false positive). Portable bash scripts with JSON output."
allowed-tools: ["Bash"]
model: sonnet
context: fork
---


# SonarQube Query

Query SonarQube code analysis findings using portable bash scripts that wrap the SonarQube Web API.

## CRITICAL: Do Not Set Environment Variables

**NEVER set or export `SONARQUBE_BASE_URL` or `SONARQUBE_USER_TOKEN`**. These variables are already configured in the user's shell environment and will be inherited automatically.

- Run scripts directly without any `export` statements
- If variables are missing, scripts will fail with a clear error - that's the user's problem to fix
- **NEVER guess or fabricate SonarQube URLs or tokens**

**WRONG** (do not do this):
```bash
export SONARQUBE_BASE_URL="https://guessed.com" && script.sh
```

**CORRECT**:
```bash
~/.dataops-assistant/bin/sonarqube-projects.sh
```

## Prerequisites (for the user, not the agent)

1. SonarQube instance (version 9.x, 10.x, or 2025.x)
2. **User token** (not analysis token) - generate at `${SONARQUBE_BASE_URL}account/security`
3. Environment variables in shell profile:
   ```bash
   export SONARQUBE_BASE_URL="https://sonar.example.com/"
   export SONARQUBE_USER_TOKEN="your-user-token"
   ```

**Note:** Analysis tokens have limited permissions. User tokens are required for browsing issues and performing transitions.

## Commands

All scripts output JSON to stdout, errors to stderr. All issue outputs include `uiUrl` for direct links.

### List Projects

```bash
~/.dataops-assistant/bin/sonarqube-projects.sh
~/.dataops-assistant/bin/sonarqube-projects.sh "payment"  # filter by name
```

Output: `{count, projects: [{key, name, qualifier}]}`

### Search Issues

```bash
~/.dataops-assistant/bin/sonarqube-issues.sh <project-key>
~/.dataops-assistant/bin/sonarqube-issues.sh <project-key> --severity CRITICAL
~/.dataops-assistant/bin/sonarqube-issues.sh <project-key> --branch develop
~/.dataops-assistant/bin/sonarqube-issues.sh <project-key> --pr 123
```

Options:
- `--branch <name>` - Filter by branch
- `--pr <id>` - Filter by pull request ID
- `--status <list>` - Filter by status: OPEN, CONFIRMED, REOPENED, RESOLVED, CLOSED
- `--severity <list>` - Filter: BLOCKER, CRITICAL, MAJOR, MINOR, INFO
- `--type <list>` - Filter: BUG, VULNERABILITY, CODE_SMELL
- `--top <N>` - Limit results (default: 100, max: 500)

Output: `{project, total, returned, issues: [{key, severity, status, type, message, component, line, rule, transitions, uiUrl}]}`

### Transition Issue

Change issue status (accept, reject as false positive, etc).

```bash
~/.dataops-assistant/bin/sonarqube-issue-transition.sh <issue-key> accept
~/.dataops-assistant/bin/sonarqube-issue-transition.sh <issue-key> falsepositive
~/.dataops-assistant/bin/sonarqube-issue-transition.sh <issue-key> wontfix
~/.dataops-assistant/bin/sonarqube-issue-transition.sh <issue-key> reopen
```

Valid transitions:
- `accept` - Mark as accepted (won't fix, by design)
- `wontfix` - Mark as won't fix
- `falsepositive` - Mark as false positive
- `confirm` - Confirm the issue exists
- `resolve` - Mark as resolved
- `reopen` - Reopen a closed/accepted issue

**Note:** `accept`, `wontfix`, `falsepositive` require "Administer Issues" permission.

Output: `{issue, transition, previousStatus, newStatus, availableTransitions, project, uiUrl}`

### Quality Gate Status

```bash
~/.dataops-assistant/bin/sonarqube-quality-gate.sh <project-key>
~/.dataops-assistant/bin/sonarqube-quality-gate.sh <project-key> --branch develop
~/.dataops-assistant/bin/sonarqube-quality-gate.sh <project-key> --pr 123
```

Output: `{project, branch, status, failedConditions, conditions: [{metric, status, threshold, actual}], uiUrl}`

## Common Patterns

### Find blocking issues across a project

```bash
~/.dataops-assistant/bin/sonarqube-issues.sh my-project --severity BLOCKER,CRITICAL --status OPEN
```

### Review findings for a PR

```bash
~/.dataops-assistant/bin/sonarqube-issues.sh my-project --pr 456
~/.dataops-assistant/bin/sonarqube-quality-gate.sh my-project --pr 456
```

### Accept a false positive

```bash
# First review the issue
~/.dataops-assistant/bin/sonarqube-issues.sh my-project --top 1 | jq '.issues[0]'

# Then transition
~/.dataops-assistant/bin/sonarqube-issue-transition.sh <issue-key> falsepositive
```

### Find project by name, then get issues

```bash
# Find project key
~/.dataops-assistant/bin/sonarqube-projects.sh "clinical" | jq '.projects[0].key'

# Use key for issues
~/.dataops-assistant/bin/sonarqube-issues.sh <project-key>
```

## Version Compatibility

Tested with SonarQube 2025.5.x. Compatible with 9.x and 10.x.

- **9.x/10.x:** Statuses include OPEN, CONFIRMED, RESOLVED, REOPENED, CLOSED
- **10.x+:** Adds ACCEPTED status (replaces Won't Fix resolution)
- **2025.x:** Uses `issueStatus` field, supports all transitions
