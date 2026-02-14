---
description: "Search Azure DevOps code and return relevant results for a research context. Returns max ~1000 token summary."
allowed-tools: ["ToolSearch", "mcp__azure-devops__search_code"]
model: haiku
context: fork
---

# ADO Code Search

Search Azure DevOps code repositories and return filtered, relevant results.

## CRITICAL: How To Execute This Skill

This skill uses exactly TWO tool calls. No Bash. No scripts.

### Step 1: Load the MCP tool

```
ToolSearch:
  query: "+azure-devops search_code"
```

### Step 2: Call the MCP tool directly

```
mcp__azure-devops__search_code:
  searchText: "your search query"
  repository: ["repo-name"]  # MUST be array, not string
  top: 25
```

**CRITICAL**: `repository` parameter MUST be an array of strings, even for single repo.

Examples:
- ✅ `repository: ["clinical-matching-workflow"]`
- ❌ `repository: "clinical-matching-workflow"`

**That's it.** Two tool calls. Both are TOOL CALLS, not Bash commands.

### WRONG (do not do these):
- `Bash(mcp__azure-devops__search_code ...)` - MCP tools are NOT bash commands
- `Bash(./scripts/...)` - There are NO scripts in this skill
- `Bash(cd ... && ...)` - No Bash at all

## Input Format

**REQUIRED:** You MUST specify a repository. Unscoped searches will hang and fill context.

```
{project}/{repo}:{search_query} | {research context}
```

Examples:
- `Platform Engineering/clinical-matching-service:retry_policy | understanding how retries are configured`
- `DataPlatform/etl-framework:ConnectionString | finding where connection strings are used`
- `Platform Engineering/worker-service:def handle_error | reviewing error handling patterns`

**If user doesn't specify a repo:** ASK which repository to search. Do NOT run unscoped searches.

## Instructions

1. **Load tool** - Call `ToolSearch` with query `+azure-devops search_code`
2. **Parse input** - Extract project, repository, search query, and research context
3. **VALIDATE SCOPE** - If no repository was specified, STOP and return error: "Repository required. Please specify which repo to search (e.g., 'Platform Engineering/my-repo:query')"
4. **Execute search** - Call `mcp__azure-devops__search_code` with:
   - `searchText`: the search query
   - `repository`: ["repo-name"] as ARRAY
   - `project`: ["project-name"] as ARRAY (optional but recommended)
   - `top`: 25 (limit results)
5. **Handle errors gracefully**:
   - If 400 Bad Request: query may be malformed, try simpler search text
   - If timeout: scope is too broad, ask user to narrow to specific repo
   - If validation error: check all array parameters are arrays, not strings
6. **Filter by relevance** - Only include results relevant to the research context
7. **Summarize results** - Return top matches with file paths and snippets
8. **Rate relevance** - Assess how well results answer the research question

**CRITICAL:** Step 3 is a HARD STOP. Never proceed without a specific repository.

**CRITICAL:** All filter parameters (repository, project, path, branch) MUST be arrays, not strings.

## Output Format

```
SEARCH: "{query}"
PROJECT: {project or "all projects"}
RESULTS: {total_count} matches across {repo_count} repos

RELEVANT FILES:
1. {project}/{repo}/{path}:{line}
   `{code snippet - max 100 chars}`
   Why relevant: {brief explanation}

2. {project}/{repo}/{path}:{line}
   `{code snippet - max 100 chars}`
   Why relevant: {brief explanation}

[Continue for top 5-10 most relevant results]

PATTERNS OBSERVED:
- {pattern 1 across results}
- {pattern 2 across results}

---
RESEARCH CONTEXT: {echoed from input}

RELEVANCE: high|medium|low - {explanation}

SUGGESTED FOLLOW-UP:
- {refined search if needed}
- {specific file to read}
```

## Rules

1. **Filter aggressively** - Don't dump all results, only what's relevant to research context
2. **~1000 tokens max** - Be concise, this feeds back to main context
3. **Include paths** - User needs file paths to navigate to code
4. **Truncate snippets** - Max 100 chars per snippet, show the relevant part
5. **Group patterns** - If multiple files show same pattern, summarize instead of listing all
6. **Note scope** - If search was project-scoped, mention it clearly
7. **Suggest refinements** - If results are too broad/narrow, suggest better queries

## Example Output

```
SEARCH: "retry_policy"
PROJECT: all projects
RESULTS: 23 matches across 5 repos

RELEVANT FILES:
1. Platform Engineering/clinical-matching-service/src/worker/config.py:42
   `retry_policy = RetryPolicy(max_attempts=3, backoff_multiplier=2)`
   Why relevant: Defines retry configuration

2. Platform Engineering/clinical-matching-service/src/worker/handler.py:15
   `@retry_policy.wrap`
   Why relevant: Shows how retry policy is applied

3. DataPlatform/etl-framework/lib/resilience.py:88
   `class RetryPolicy: """Configurable retry with exponential backoff"""`
   Why relevant: Base class definition

4. DataPlatform/etl-framework/tests/test_resilience.py:120
   `def test_retry_policy_respects_max_attempts():`
   Why relevant: Shows expected behavior

PATTERNS OBSERVED:
- RetryPolicy class from etl-framework is the common implementation
- Most services use max_attempts=3 with exponential backoff
- Retry logic is applied via decorator pattern

---
RESEARCH CONTEXT: understanding how retries are configured

RELEVANCE: high - Found both configuration and implementation patterns

SUGGESTED FOLLOW-UP:
- Read `DataPlatform/etl-framework/lib/resilience.py` for full RetryPolicy implementation
- Search `backoff_multiplier` to find different retry timings
```

## Handling Large Result Sets

If search returns many results:

1. **Prioritize by research context** - Only include files that answer the research question
2. **Group similar files** - "Found in 8 test files" instead of listing all 8
3. **Note omissions** - "12 additional matches in test files (omitted)"
4. **Suggest scoping** - If too broad, suggest adding project filter or refining query

## Handling No Results

If search returns no results:

```
SEARCH: "{query}"
RESULTS: 0 matches

No code found matching "{query}".

SUGGESTIONS:
- Try broader search: "{alternative query}"
- Check spelling/casing
- Search specific project if you know where code lives
```
