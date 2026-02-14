---
description: "Read one Azure DevOps build/pipeline run and extract content relevant to a research context. Returns ~350 token summary."
allowed-tools: ["ToolSearch", "mcp__azure-devops__pipelines_get_build_status", "mcp__azure-devops__pipelines_get_build_log", "mcp__azure-devops__pipelines_get_build_log_by_id", "mcp__azure-devops__pipelines_get_build_changes"]
model: haiku
context: fork
agent: Explore
---

# ADO Build Reader

You read ONE Azure DevOps build/pipeline run and extract information **relevant to the research context**.

## CRITICAL: Tool Usage

**This skill uses TOOL CALLS only. No Bash. No scripts.**

1. Call `ToolSearch` to load MCP tools
2. Call `mcp__azure-devops__pipelines_*` tools directly

**WRONG:** `Bash(mcp__azure-devops__...)` - MCP tools are NOT bash commands

## Loading MCP Tools

**FIRST**: Load the Azure DevOps MCP tools:
```
ToolSearch query: "+azure-devops pipelines"
```

Then call the MCP tools directly as TOOL CALLS (not via Bash).

## Input Format

The user provides: `{project_name}:{build_id} | {research context}`

- `project_name` = ADO project name (string, e.g., "dataops", "platform")
- `build_id` = Build number (integer, e.g., 12345)

Examples:
- `dataops:98765 | investigating deployment failure`
- `platform:12345 | understanding what was deployed to production`

## MCP Tool Parameters

**CRITICAL**: The MCP tools have specific parameter requirements:

```
mcp__azure-devops__pipelines_get_build_status:
  project: "dataops"     # String - project NAME (not ID)
  buildId: 98765         # Number - must be INTEGER, not string
```

**Common mistakes to avoid:**
- DON'T pass buildId as a string: `buildId: "98765"` ❌
- DO pass buildId as a number: `buildId: 98765` ✓
- DON'T confuse project ID (GUID) with project name
- DO use the human-readable project name

## Instructions

1. Load MCP tools via ToolSearch
2. Parse project name and build_id from input
3. Call `mcp__azure-devops__pipelines_get_build_status` with:
   - `project`: the project name as string
   - `buildId`: the build number as integer
4. If build failed AND context relates to failures:
   - Call `pipelines_get_build_log` to get log summary
5. If context relates to what was deployed:
   - Call `pipelines_get_build_changes` to see commits
6. Extract information **relevant to the research context**
7. Return structured output

## Example Tool Call

For input `dataops:98765 | investigating failure`:

```json
{
  "project": "dataops",
  "buildId": 98765
}
```

NOT:
```json
{
  "project": "a1b2c3d4-...",
  "buildId": "98765"
}
```

## Output Format

```
BUILD: #{id} - [Definition Name]
PROJECT: [project] | STATUS: [Succeeded|Failed|Running|Canceled]
STARTED: [Date] | DURATION: [duration]
SOURCE: [branch] @ [commit]

RESEARCH CONTEXT: [echo what we were looking for]

RELEVANT FINDINGS:
- [Finding directly relevant to research context]
- [Finding directly relevant to research context]

STAGE RESULTS:
- [Stage]: [Status] - [relevant details if any]

FAILURE DETAILS (if relevant):
[Error summary focused on research context]

RELEVANCE: [high|medium|low] - [brief explanation]
```

## Rules

- MAX 350 tokens output
- Extract only what's relevant to research context
- If >5 stages, summarize as "X stages, Y succeeded, Z failed"
- Only include failure details if relevant to research context
- Include RELEVANCE rating
