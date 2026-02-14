#!/bin/bash
# Inject routing rules into Claude's context before every user prompt.
# This ensures Claude sees routing guidance prominently before responding.
# Rules are conditionally included based on capability availability.
#
# IMPORTANT: This runs on EVERY prompt - keep checks FAST (no subprocess calls where possible)

# --- Capability detection (fast checks only) ---

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

# Check if an MCP server is configured
collect_mcp_servers() {
    local result=""
    for f in "./.mcp.json" "$HOME/.claude/settings.json" "$HOME/.claude.json"; do
        [[ -f "$f" ]] && result="$result $(jq -r '.mcpServers // {} | keys[]' "$f" 2>/dev/null || true)"
    done
    printf "%s" "$result"
}

has_mcp() {
    local name="$1"
    local configured="$2"
    printf "%s" "$configured" | grep -qi "$name"
}

# Check Outlook availability (macOS only, Outlook must be running, Legacy mode required)
has_outlook() {
    [[ "$(uname)" != "Darwin" ]] && return 1
    pgrep -x "Microsoft Outlook" >/dev/null 2>&1 || return 1
    local is_new_outlook
    is_new_outlook=$(defaults read com.microsoft.Outlook IsRunningNewOutlook 2>/dev/null || echo "")
    [[ "$is_new_outlook" == "1" ]] || [[ "$is_new_outlook" == "true" ]] || [[ "$is_new_outlook" == "YES" ]] && return 1
    return 0
}

# Detect capabilities once (fast file/env checks only)
configured_mcps="$(collect_mcp_servers)"

# MCP-based capabilities
HAS_ATLASSIAN=false
HAS_ADO_MCP=false
HAS_PAGERDUTY=false

has_mcp "atlassian" "$configured_mcps" && HAS_ATLASSIAN=true
has_mcp "azure-devops" "$configured_mcps" && HAS_ADO_MCP=true
has_mcp "pagerduty" "$configured_mcps" && [[ -n "${PAGERDUTY_API_TOKEN:-}" ]] && HAS_PAGERDUTY=true

# Environment-based capabilities (fast)
HAS_OPENAI=false
HAS_SONARQUBE=false
HAS_ADO_CLI=false

[[ -n "${OPENAI_API_KEY:-}" ]] && HAS_OPENAI=true
[[ -n "${SONARQUBE_BASE_URL:-}" ]] && [[ -n "${SONARQUBE_USER_TOKEN:-}" ]] && HAS_SONARQUBE=true
[[ -n "${AZURE_DEVOPS_ORG:-}" ]] && command -v az &>/dev/null && HAS_ADO_CLI=true

# File-based capabilities (fast)
HAS_OUTLOOK=false
HAS_K8S=false
HAS_AWS=false
HAS_AZURE_STEAMPIPE=false

has_outlook && HAS_OUTLOOK=true
[[ -f "$HOME/.dataops-assistant/k8s/kubeconfig" ]] && HAS_K8S=true
[[ -f "$HOME/.dataops-assistant/steampipe-aws/config/aws.spc" ]] && HAS_AWS=true
[[ -d "$PLUGIN_ROOT/skills/azure-steampipe-query/assets/internal" ]] && HAS_AZURE_STEAMPIPE=true

# --- Output routing rules ---

cat << 'EOF'
ROUTING RULES - Check before responding:

| User asks about... | MUST use |
|--------------------|----------|
EOF

# Conditional: Atlassian (Confluence/Jira)
if $HAS_ATLASSIAN; then
    cat << 'EOF'
| Confluence search/explore (no page ID) | `dataops-assistant:confluence-advisor` agent |
| Confluence read page (has page ID like 12345678) | `/dataops-assistant:confluence-page-reader` skill |
| Jira search/explore (no issue key) | `dataops-assistant:jira-advisor` agent |
| Jira: what is X working on, X's tickets, assigned to X | `dataops-assistant:jira-advisor` agent |
| Jira: JQL query, search issues, find tickets | `dataops-assistant:jira-advisor` agent |
| Jira read issue (has key like PROJ-123) | `/dataops-assistant:jira-issue-reader` skill |
| Jira list versions, project versions | `/dataops-assistant:jira-version-list` skill |
EOF
fi

# Conditional: PagerDuty
if $HAS_PAGERDUTY; then
    echo "| PagerDuty search, on-call, who is paged, escalation | \`dataops-assistant:pagerduty-advisor\` agent |"
    echo "| PagerDuty read specific incident (has ID like Q0RIJJZL24RC6W) | \`/dataops-assistant:pagerduty-incident-reader\` skill |"
    echo "| PagerDuty read specific service (has ID like PG7CZUT) | \`/dataops-assistant:pagerduty-service-reader\` skill |"
fi

# Architects (always available - no external deps)
cat << 'EOF'
| Go code design, Go patterns, Go conventions | `dataops-assistant:golang-architect` agent |
| Bash/shell script design, shell patterns | `dataops-assistant:bash-architect` agent |
| Makefile design, make targets, build rules | `dataops-assistant:make-architect` agent |
| Terraform modules, HCL patterns, state management | `dataops-assistant:terraform-architect` agent |
| Change process, CI/CD design, documentation standards | `dataops-assistant:general-architect` agent |
| Writing skills, SKILL.md, custom slash commands | `dataops-assistant:skill-writing-advisor` agent |
| Multi-source internal research | `/dataops-assistant:research` skill |
EOF

# Conditional: OpenAI skills
if $HAS_OPENAI; then
    echo "| Web research, current info, technical docs | \`/dataops-assistant:openai-research\` skill |"
fi

# Conditional: Azure Steampipe
if $HAS_AZURE_STEAMPIPE; then
    echo "| Azure infrastructure queries | \`/dataops-assistant:azure-steampipe-query\` skill |"
fi

# Conditional: AWS Steampipe
if $HAS_AWS; then
    echo "| AWS infrastructure queries, S3, EC2, IAM, Lambda | \`/dataops-assistant:aws-steampipe-query\` skill |"
fi

# Conditional: ADO CLI skills
if $HAS_ADO_CLI; then
    echo "| ADO repos, pipelines, builds | \`/dataops-assistant:ado-query\` or \`/dataops-assistant:ado-build-reader\` skill |"
    echo "| ADO user activity, PRs by user, commits by user | \`/dataops-assistant:ado-query\` skill |"
fi

# Conditional: ADO MCP skills (code search, PR reader)
if $HAS_ADO_MCP; then
    echo "| Search ADO code, find code, grep repos | \`/dataops-assistant:ado-code-search\` skill |"
    echo "| Review ADO PR, PR feedback, PR comments, summarize PR | \`dataops-assistant:ado-pr-reader\` agent |"
fi

# Conditional: SonarQube
if $HAS_SONARQUBE; then
    echo "| SonarQube projects, issues, quality gates | \`/dataops-assistant:sonarqube-query\` skill |"
    echo "| Accept/reject SonarQube findings, mark false positive | \`/dataops-assistant:sonarqube-query\` skill |"
fi

# Conditional: K8s
if $HAS_K8S; then
    echo "| Kubernetes query, pods, deployments, k8s, EKS, AKS | \`/dataops-assistant:k8s-steampipe\` skill |"
    echo "| Pod logs, container logs, stern | \`/dataops-assistant:k8s-logs\` skill |"
fi

# Conditional: Outlook
if $HAS_OUTLOOK; then
    echo "| Search Outlook emails (macOS) | \`/dataops-assistant:read-macos-outlook\` skill |"
    echo "| Search Outlook calendar events (macOS) | \`/dataops-assistant:read-macos-outlook-calendar\` skill |"
fi

# Authoring skills (conditional on their backends)
if $HAS_ATLASSIAN; then
    cat << 'EOF'
| Create Confluence page | `/dataops-assistant:confluence-authoring` skill |
| Draft Jira issue content | `/dataops-assistant:jira-draft` skill |
| Review Jira draft | `/dataops-assistant:jira-advise` skill |
| Publish Jira draft to Jira | `/dataops-assistant:jira-publish` skill |
| Add comment to Jira issue | `/dataops-assistant:jira-publish` skill (draft first) |
| Draft Jira release notes | `/dataops-assistant:jira-release-draft` skill |
| Publish Jira release notes | `/dataops-assistant:jira-release-publish` skill |
| Read Jira version/release details | `/dataops-assistant:jira-release-reader` skill |
EOF
fi

if $HAS_ADO_MCP; then
    cat << 'EOF'
| Draft ADO PR content | `/dataops-assistant:ado-pr-draft` skill |
| Publish ADO PR draft | `/dataops-assistant:ado-pr-publish` skill |
| Draft ADO PR comment/reply/resolve | `/dataops-assistant:ado-pr-comment-draft` skill |
| Publish ADO PR comment draft | `/dataops-assistant:ado-pr-comment-publish` skill |
EOF
fi

# Always available
echo "| Reframe as GTD (outcomes/actions) | \`/dataops-assistant:frame-as-gtd\` skill |"
echo "| Sync architect memory repos | \`/dataops-assistant:sync-arch-memory\` skill |"
echo "| Plugin status, check configuration | \`/dataops-assistant:status\` skill |"

echo ""
echo "If a routing rule applies, DELEGATE to that tool. Do not answer directly."
echo ""

# --- MCP warnings (only for configured MCPs) ---
echo "**NEVER call these MCP tools directly** - they return huge responses (~20k tokens) that fill context:"

if $HAS_ATLASSIAN; then
    echo "- Jira search: \`searchJiraIssuesUsingJql\`, \`lookupJiraAccountId\` → use \`dataops-assistant:jira-advisor\` agent"
    echo "- Confluence search: \`searchConfluenceUsingCql\`, \`search\` → use \`dataops-assistant:confluence-advisor\` agent"
    echo "- Jira read: \`getJiraIssue\` → use \`/dataops-assistant:jira-issue-reader\` skill"
    echo "- Jira write: \`createJiraIssue\`, \`editJiraIssue\`, \`addCommentToJiraIssue\` → use \`/dataops-assistant:jira-publish\`"
fi

if $HAS_PAGERDUTY; then
    echo "- PagerDuty list: \`list_incidents\`, \`list_services\` → use \`dataops-assistant:pagerduty-advisor\` agent"
    echo "- PagerDuty read: \`get_incident\`, \`get_service\` → use \`/dataops-assistant:pagerduty-incident-reader\` or \`/dataops-assistant:pagerduty-service-reader\` skill"
fi

if $HAS_ADO_MCP; then
    echo "- ADO code: \`search_code\` → use \`/dataops-assistant:ado-code-search\` skill"
    echo "- ADO PR tools: \`repo_create_pull_request\`, \`repo_update_pull_request\` → use \`/dataops-assistant:ado-pr-publish\`"
fi

echo ""

if $HAS_ADO_MCP; then
    echo "**DANGER: \`search_code\` without repository scope WILL HANG and fill context.** Always specify a repo."
    echo ""
fi

if $HAS_ATLASSIAN; then
    echo "**ALL Jira write operations require draft approval.** Draft with \`/dataops-assistant:jira-draft\`, then publish."
    echo ""
fi

echo "The skills handle GUID lookups, validation, and error recovery that raw MCP calls don't."
echo ""

if $HAS_OPENAI; then
    echo "**ALWAYS SEARCH for libraries, packages, SDKs, APIs, CLI tools, and version info.**"
    echo "Your training data is outdated. Use \`/dataops-assistant:openai-research\` for current syntax, versions, and usage patterns."
fi
