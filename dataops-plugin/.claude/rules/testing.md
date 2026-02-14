---
paths:
  - "tests/**"
---
# Testing Rules

## Test Framework

Tests use [bats-core](https://github.com/bats-core/bats-core) (Bash Automated Testing System). Minimum version: 1.5.0.

```bash
# Run all bats tests
bats tests/

# Run a specific test file
bats tests/bootstrap.bats

# Run tests matching a name filter
bats tests/ado-query-fast.bats --filter "returns valid JSON"

# Run lint (structural validation, no Claude invocation)
./tests/lint.sh
```

## Test Layers

| Layer | Files | What it checks |
|-------|-------|---------------|
| Lint | `tests/lint.sh` | plugin.json valid, hook scripts exist, SKILL.md references valid |
| Unit (bats) | `tests/*.bats` | Script behavior, argument parsing, error handling, JSON output |
| Golden | `tests/golden/*.yaml` | End-to-end agent behavior via Claude Code `--print` mode |
| Manual | `tests/manual/*.yaml` | Write operations requiring cleanup (pre-release only) |

## Writing Bats Tests

### Structured Output (JSON)

When testing scripts that output JSON on stdout and diagnostics on stderr, use `run --separate-stderr` so stderr doesn't corrupt `$output`:

```bash
setup() {
    bats_require_minimum_version 1.5.0
    # ...
}

@test "script: returns valid JSON" {
    run --separate-stderr "$SCRIPT" --project "Foo" --top 5
    [[ "$status" -eq 0 ]]
    echo "$output" | jq empty  # Validates JSON
}
```

Without `--separate-stderr`, bats merges stderr into `$output`, breaking `jq` parsing.

### Error Message Tests

When testing error output (which typically goes to stderr), the default `run` (merged streams) is fine:

```bash
@test "script: rejects unknown options" {
    run "$SCRIPT" --bad-flag
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Unknown option"* ]]
}
```

### Integration Tests

Tests that hit live services should have skip guards:

```bash
skip_without_ado_auth() {
    [[ -z "${AZURE_DEVOPS_ORG:-}" ]] && skip "AZURE_DEVOPS_ORG not set"
    az account show &>/dev/null || skip "az CLI not authenticated"
}
```

## Adding Tests for a New Skill

1. Create `tests/<skill-name>.bats`
2. Test error handling first (no auth needed, fast)
3. Add integration tests with skip guards for live service calls
4. If it produces JSON, validate structure with `jq`
5. Run `bats tests/<skill-name>.bats` to verify
