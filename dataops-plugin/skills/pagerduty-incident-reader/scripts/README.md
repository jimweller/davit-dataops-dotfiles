# PagerDuty Reader Scripts

Test utilities for the PagerDuty reader skills.

## Files

| File | Purpose |
|------|---------|
| `pagerduty-id.js` | ID format detection utilities |
| `pagerduty-id.test.js` | Unit tests for ID detection |
| `integration-test.sh` | Integration tests against live PagerDuty API |

## Running Tests

### Unit Tests

```bash
bun test pagerduty-id.test.js
```

### Integration Tests

Requires `PAGERDUTY_API_TOKEN` to be set:

```bash
export PAGERDUTY_API_TOKEN=your_token_here
./integration-test.sh
```

Dry run (no API calls):

```bash
./integration-test.sh --dry-run
```

## ID Format Patterns

Based on observed PagerDuty IDs:

| Type | Length | Pattern | Examples |
|------|--------|---------|----------|
| Service | 5-8 chars | Often starts with `P` | `PG7CZUT`, `PABC123` |
| Incident | 12-16 chars | Often starts with `Q` | `Q0RIJJZL24RC6W` |

These patterns are heuristic - the API is the source of truth.

## Shared Utility

Both `pagerduty-incident-reader` and `pagerduty-service-reader` skills use the ID detection logic documented here. The skills themselves are LLM-executed (following SKILL.md instructions), so these utilities serve as:

1. **Documentation** of the expected ID patterns
2. **Test suite** to verify patterns against real PagerDuty data
3. **Reference implementation** that could be used by future scripted skills
