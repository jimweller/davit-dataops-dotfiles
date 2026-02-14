# Anti-Hallucination Architecture

This plugin implements a **3-layer defense** against agent hallucination of API results.

## The Problem

LLM agents can hallucinate plausible-looking API responses instead of actually calling tools:

```
User: "Find Jira issues for Ryan"
Bad Agent (0 tool calls): "Based on the team, Ryan is working on PAY-123..." ❌ FABRICATED
Good Agent (1+ tool calls): [Calls searchJiraIssuesUsingJql] → Returns actual results ✓
```

This is dangerous because:
- Users trust fabricated data
- Downstream agents operate on fake data
- Defeats the purpose of the research orchestration

## Defense Layers

### Layer 1: SubagentStop Hook (HARD BLOCK)

**File**: `hooks/require-advisor-tool-calls.sh`
**Config**: `.claude-plugin/plugin.json` → `SubagentStop`

This hook:
1. Runs when any `-advisor` agent tries to complete
2. Parses the agent transcript (JSONL)
3. Counts `tool_use` content blocks
4. **Blocks completion** if count = 0 with explicit error message

**How it works:**
```bash
TOOL_COUNT=$(jq -rs '[...] | add // 0' "$AGENT_TRANSCRIPT")
if [[ "${TOOL_COUNT:-0}" -lt 1 ]]; then
    echo '{"decision":"block","reason":"You MUST call tools..."}'
fi
```

**What happens when blocked:**
- Agent sees error: "CRITICAL: You have not called any tools (tool_uses: 0)"
- Agent is forced to retry with actual tool calls
- User never sees the fabricated results

**Applies to:**
- `jira-advisor`
- `confluence-advisor`
- `pagerduty-advisor`

### Layer 2: Prompt Engineering (SOFT GUARD)

**Files**: `agents/*-advisor.md`

Added explicit "No Fabrication" sections to all advisor agents:

```markdown
## CRITICAL: No Fabrication - Real Data Only

Rules:
1. Call tools FIRST
2. Return ONLY what tools return
3. If tools fail - Report error, do NOT make up results
4. If you can't search - Say you can't, do NOT guess
```

**Why this helps:**
- Sets clear expectations
- Gives permission to say "I don't know"
- Provides correct vs incorrect examples
- Reduces model tendency to "help" by guessing

### Layer 3: Result Validation (DETECTION)

**File**: `agents/result-validator.md`
**Usage**: Orchestrators invoke after synthesis

The validator:
1. Receives findings + source summaries
2. Checks every claim has a source citation
3. Verifies sources actually contain the claimed info
4. Flags unsupported claims, contradictions, ambiguities
5. Re-queries sources if needed (max 2 queries)

**Output:**
```json
{
  "validated": false,
  "corrections": [
    {
      "original": "John is the architect",
      "action": "REMOVED - no source supports this",
      "confidence": "high"
    }
  ],
  "unresolved": [...]
}
```

## Testing the Defense

### Good Case (should pass)
```bash
# Agent calls searchJiraIssuesUsingJql
# Returns actual results
# Hook sees tool_uses > 0 → allows completion ✓
```

### Bad Case (should block)
```bash
# Agent tries to return fabricated data
# Hook sees tool_uses = 0 → blocks with error
# Agent retries with actual tool call ✓
```

### Verification
Check the hook is registered:
```bash
jq '.hooks.SubagentStop' .claude-plugin/plugin.json
```

Test manually:
```bash
# Launch agent that should call tools
# If it returns without calling tools, hook should block
```

## Performance Impact

- **Hook execution**: ~50-100ms (parses JSONL transcript)
- **False positives**: None if agents are correctly designed
- **False negatives**: Agents that fabricate AFTER calling tools (Layer 3 catches this)

## Maintenance

### Adding new advisor agents

1. Name them `*-advisor` so the hook applies
2. Add "No Fabrication" section to prompt (copy from existing)
3. Ensure tools are listed in frontmatter
4. Test that agent calls tools before returning

### Updating the hook

The hook script is versioned with the plugin. To modify:
```bash
vim hooks/require-advisor-tool-calls.sh
# Test changes
./tests/lint.sh  # Verify hook exists
```

### Monitoring

Watch for:
- Blocked completions (appear in stderr)
- Agents with 0 tool calls that slip through (shouldn't happen)
- Validator flagging unsourced claims

## References

- [Claude Code Hooks Documentation](https://docs.anthropic.com/en/docs/claude-code/hooks)
- [Tool Use Best Practices](https://docs.anthropic.com/en/docs/agents-and-tools/tool-use)
- [Reducing Hallucinations](https://docs.claude.com/en/docs/test-and-evaluate/strengthen-guardrails/reduce-hallucinations)
