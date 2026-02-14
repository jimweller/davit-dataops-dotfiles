---
description: "Check DataOps Assistant plugin status - shows configured MCP servers, CLI tools, and verifies MCP authentication."
allowed-tools: ["Bash", "ToolSearch", "mcp__atlassian__atlassianUserInfo", "mcp__pagerduty__get_user_data", "mcp__azure-devops__core_list_projects"]
model: sonnet
context: fork
---


# DataOps Assistant Status

## Step 1: Run Configuration Check

Run the status script to check configured MCPs and CLI tools:

```bash
bash ~/.dataops-assistant/run skills/status/scripts/status.sh
```

Display the script output to the user.

## Step 2: Verify MCP Authentication

After the script runs, verify that configured MCPs are actually authenticated by making test calls.

**Load MCP tools first:**
```
ToolSearch query: "+atlassian atlassianUserInfo"
ToolSearch query: "+pagerduty get_user_data"
ToolSearch query: "+azure-devops core_list_projects"
```

**Run health checks (in parallel if possible):**

| MCP | Test Call | Success Indicator |
|-----|-----------|-------------------|
| atlassian | `mcp__atlassian__atlassianUserInfo()` | Returns user email |
| pagerduty | `mcp__pagerduty__get_user_data()` | Returns user email |
| azure-devops | `mcp__azure-devops__core_list_projects(top: 1)` | Returns project |

**Note**: Skip health check for any MCP not configured (shown in Step 1 output).

## Step 3: Report Results

Display a summary showing both configuration AND authentication status:

```
MCP Health Check:
  atlassian:    ✓ configured  ✓ authenticated (user@company.com)
  azure-devops: ✓ configured  ✓ authenticated
  pagerduty:    ✓ configured  ✓ authenticated

  OR for failures:

  atlassian:    ✓ configured  ✗ AUTH FAILED: invalid refresh token
```

If any MCP fails authentication, provide actionable next steps (re-authenticate, check credentials, etc.).
