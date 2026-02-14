# ADO Code Search Strategy

## Problem

Azure DevOps Code Search API has reliability issues:
1. **Type validation errors** - Expects arrays but easy to pass strings
2. **Timeouts** - Org-wide or project-wide searches hang indefinitely
3. **400 Bad Requests** - Complex queries fail silently
4. **No pagination control** - Large result sets crash Claude Code

## Industry Solutions

### 1. **Narrow Scope First** (Current approach - FIXED)

**Strategy**: Require explicit repository scope before searching.

**Implementation**: Updated `ado-code-search` skill to:
- REQUIRE repository parameter
- Validate parameter types (arrays, not strings)
- Add error handling for 400/timeout
- Limit results to 25

**Pros**:
- No infrastructure needed
- Works when you know which repo to search

**Cons**:
- Requires user to know repo name
- Still unreliable for complex queries
- Can't search across repos

### 2. **Local Clone + Ripgrep** (Recommended for reliability)

**Strategy**: Clone repos locally, use ripgrep for fast code search.

**Implementation Options**:

#### Option A: Manual Clone
User clones repos they frequently search:
```bash
cd ~/code/ado-repos
git clone https://dev.azure.com/org/project/_git/repo-name
```

Then use Claude Code's built-in `Grep` tool to search:
```bash
Grep(pattern: "retry_policy", path: "~/code/ado-repos/repo-name")
```

**Pros**:
- Lightning fast (ripgrep is 10-100x faster than API)
- No API limits or timeouts
- Full regex support
- Works offline

**Cons**:
- Manual clone required
- Repos can get stale (need git pull)

#### Option B: Auto-Clone Skill
Create a new skill that:
1. Maintains a local cache of repos (`~/.dataops-assistant/ado-cache/`)
2. Auto-clones repos on first search
3. Uses `git fetch` to check freshness (skip if < 1 hour old)
4. Falls back to API search if repo not cached

Example:
```bash
./skills/ado-code-search-local/scripts/search.sh \
  --repo "clinical-matching-workflow" \
  --query "duplicate" \
  --project "Platform Engineering"
```

Script would:
```bash
# Check cache
CACHE_DIR="$HOME/.dataops-assistant/ado-cache"
REPO_PATH="$CACHE_DIR/$PROJECT/$REPO"

# Clone if not exists or stale
if [ ! -d "$REPO_PATH" ] || [ $(find "$REPO_PATH/.git/FETCH_HEAD" -mmin +60) ]; then
  git clone --depth 1 "https://dev.azure.com/$ORG/$PROJECT/_git/$REPO" "$REPO_PATH"
fi

# Search with ripgrep
cd "$REPO_PATH"
rg --json "$QUERY" | head -25
```

**Pros**:
- Best of both: API discoverability + local search speed
- Automatic caching
- Fresher than manual clones

**Cons**:
- Disk space (shallow clones are ~10-50MB per repo)
- Initial clone latency
- Requires git credentials

#### Option C: Hybrid Approach (Best for production)
Combine approaches:
1. Use API search to discover which repos contain matches
2. Offer to clone repos locally for deeper search
3. Cache frequently-searched repos automatically

Workflow:
```
User: "Search for duplicate handling"
Claude: [Uses API to find 3 repos with matches]
Claude: "Found matches in: repo-A (12 hits), repo-B (5 hits), repo-C (2 hits).
        Clone repo-A locally for detailed search? (faster, more reliable)"
User: "Yes"
Claude: [Clones repo-A, uses ripgrep, returns detailed results]
```

### 3. **Pre-indexed Search** (For large orgs)

**Strategy**: Maintain a local Elasticsearch/Meilisearch index of repos.

**Implementation**: Too complex for this tool. Requires:
- Webhook to trigger re-index on push
- Background indexer process
- Search service running

**Skip this** - overkill for most use cases.

## Recommendation

Implement **Option B: Auto-Clone Skill** as a new skill alongside existing API-based search:

1. **Keep** `ado-code-search` (API-based) for:
   - Quick searches when you don't know which repo
   - Discovery across many repos
   - One-off searches

2. **Create** `ado-code-search-local` (clone-based) for:
   - Deep searches in known repos
   - Regex patterns
   - Large result sets
   - Repeated searches in same repo

3. **Add routing logic**:
   - If user specifies repo → use local clone skill
   - If user says "search across all repos" → use API skill (with warning)
   - If API search times out → suggest "clone this repo for better results"

## Implementation Plan

### Phase 1: Fix Current Skill (DONE)
- ✅ Fix parameter types (arrays not strings)
- ✅ Add error handling
- ✅ Document limits clearly

### Phase 2: Create Local Clone Skill
1. Create `skills/ado-code-search-local/`
2. Write `scripts/search.sh` with:
   - Auto-clone logic
   - Ripgrep search
   - Freshness checks
3. Update SKILL.md with usage instructions
4. Update routing rules to prefer local when repo is known

### Phase 3: Add Cache Management
1. Create `scripts/cache-status.sh` - Show cached repos, disk usage
2. Create `scripts/cache-prune.sh` - Remove stale repos
3. Add to `/dataops-assistant:status` skill

## Estimated Disk Usage

Assuming 50 repos, shallow clones:
- Small repo (< 10 files): ~5MB
- Medium repo (100-500 files): ~20MB
- Large repo (1000+ files): ~50MB

**Total for 50 repos**: ~1-2GB (manageable)

## Alternative: Just Ask Users to Clone

Simplest approach:
1. Keep API search as-is (with fixes)
2. When it fails/times out, tell user:
   ```
   ADO Code Search is unreliable for this query.

   For better results, clone the repo locally:

   cd ~/code/ado-repos
   git clone https://dev.azure.com/org/project/_git/repo-name

   Then I can use fast local search with:
   Grep(pattern: "your-query", path: "~/code/ado-repos/repo-name")
   ```

**This might be the best starting point** - no new tooling, leverages existing Claude Code capabilities.
