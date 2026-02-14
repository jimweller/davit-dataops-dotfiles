# Pull Request Writing Guide

This guide documents the PR writing conventions and style patterns to follow when creating pull requests. These patterns are derived from established PR history and should be followed for consistency.

---

## PR Title Conventions

Use a descriptive prefix that categorizes the change:

| Prefix | When to Use | Example |
|--------|-------------|---------|
| `Bug fix:` | Fixing broken functionality | `Bug fix: Enable job retries for arq` |
| `Temporary fix:` | A hack or workaround (not ideal long-term) | `Temporary fix: Event Loop CPU Delay Fix` |
| `[TICKET-ID] -` | When the ticket number is the key context | `ML-889 - Helmchart support for payload capture` |
| None | Features, refactors, or dependency updates | `Bump to v0.1.5 of the workflow` |
| Scope qualifier | When changes are isolated | `Chart-Only Changes: Env Var Additions` |

**Key points:**
- Keep titles concise but descriptive
- Include ticket ID in title only if it's the primary context (otherwise link in body)
- Use sentence case, not Title Case

---

## JIRA Issue Link

When there is an associated JIRA issue, include a link **at the very top** of the PR description in this exact format:

```markdown
> __See [ML-XXXX](https://mcghealth.atlassian.net/browse/ML-XXXX)__
```

**Variations:**
- For releases: `> __See [Release vX.X.X](https://mcghealth.atlassian.net/projects/ML/versions/XXXXX/tab/release-report-all-issues)__`
- For related (not primary) issues: `> **See Also: [ML-XXXX](https://mcghealth.atlassian.net/browse/ML-XXXX)**`

**When to omit:**
- Organic bug fixes discovered during development
- Refactors not tied to a ticket
- Simple dependency bumps

---

## Description Structure

### Standard PR (small to medium changes)

```markdown
> __See [ML-XXXX](https://mcghealth.atlassian.net/browse/ML-XXXX)__

## What's here

[Brief explanation of the change and why it was needed]

- Bullet point describing key change 1
- Bullet point describing key change 2

## How to test it

[Testing instructions - keep terse if obvious]
```

### Large/Complex PR

```markdown
> __See [ML-XXXX](https://mcghealth.atlassian.net/browse/ML-XXXX)__

## What's here

[Overview paragraph]

#### Risk Mitigation

[Explain how risk is managed for large changes - e.g., "no functional changes to core code"]

#### The Big Things

- **Feature A**: Description of major change
- **Feature B**: Description of major change

#### The Little Things

- Minor change 1
- Minor change 2

---

## How to test it

[Detailed testing instructions]
```

### Bug Fix PR

```markdown
> __See [ML-XXXX](https://mcghealth.atlassian.net/browse/ML-XXXX)__

## What's here

[Brief description of the bug and the fix]

- Change 1 that fixes the issue
- Change 2 (if applicable)

## How to test it

[How to verify the fix works]
```

---

## Section Headers

Use these standard section headers:

| Header | Purpose |
|--------|---------|
| `## What's here` | Main description of changes (required) |
| `## What is not here` | Clarify scope, mention related work in other PRs |
| `## How to test it` | Testing instructions (required unless trivial) |
| `## How to See it` | For observability/UI changes - how to view in action |
| `#### The Big Things` / `#### The Little Things` | For large refactors, categorize by impact |
| `#### Risk Mitigation` | For risky changes, explain safeguards |
| `## High Level Changes` | For very large PRs, organized by category |

**Capitalization:** Use sentence case (`What's here`) or title case (`What's Here`) consistently - both are acceptable.

---

## Content Style

### Tone
- Conversational and practical
- Explain the "why" not just the "what"
- Be direct, not verbose
- It's okay to use first person ("I had to...", "I know it's a jump...")

### Formatting
- Use bullet points (`-`) for lists of changes
- Use numbered lists (`1. 2. 3.`) for ordered steps
- Use `**bold**` for key terms or component names
- Use backticks for code, commands, file paths, env vars
- Use code blocks with language hints for multi-line code:

```bash
export SOME_VAR=value
make test
```

### Links
- Link to related PRs: `[PR-XXXXX](URL)`
- Link to README sections when relevant
- Link to external docs (Datadog, Confluence) when helpful
- @ mention team members when referencing their work

---

## Testing Instructions

### Simple changes
Keep it terse:
```markdown
## How to test it

The existing tests cover this. Run `make test`.
```

Or even:
```markdown
## How to test it

The existing tests just have to be good enough!
```

### Complex changes
Provide detailed steps:
```markdown
## How to test it

1. Deploy with the harness enabled:
   ```bash
   make dv-install
   ```

2. Port-forward the service:
   ```bash
   kubectl port-forward -n namespace svc/service-name 8888:8888
   ```

3. Send a test request:
   ```bash
   curl -X POST http://localhost:8888/endpoint
   ```
```

### Deployment verification
Point to existing documentation:
```markdown
## How to test it

See the [README](./deploy/chart/README.md) for deployment verification steps.

Quick version:
- `make test` - unit tests
- `make dv-test` - deployment verification
```

---

## What NOT to Do

1. **Don't enumerate files changed** - This is already visible in the PR diff
2. **Don't re-state the JIRA issue verbatim** - Just link to it
3. **Don't be overly verbose** when tests are self-explanatory
4. **Don't add empty sections** - Omit "How to test it" only if truly trivial
5. **Don't use time estimates** - Focus on what, not when

---

## Examples by PR Type

### Minimal PR (dependency bump)
```markdown
> __See [Release v0.11.3](https://mcghealth.atlassian.net/projects/ML/versions/17400)__

# What's here

Update the `clinical-matching-workflow` dependency to version `0.1.5`. The main reason to bring this in is [ML-1195](https://mcghealth.atlassian.net/browse/ML-1195).

This is supposed to be a no-op change from the vantage point of the CMS service.

# How to test it

The existing tests just have to be good enough!
```

### Standard Bug Fix
```markdown
> __See [ML-1285](https://mcghealth.atlassian.net/browse/ML-1285)__

## What's here

Adds `app.kubernetes.io/component: api` label to API deployment and service selectors to distinguish API pods from harness pods. Previously, the ingress was routing some requests to harness pods.

## How to test it

- `make test` - run unit tests including new selector tests
- `make dv-test` - full deployment verification
```

### Infrastructure/Chart Change
```markdown
> __See [ML-929](https://mcghealth.atlassian.net/browse/ML-929)__

# What's here

The addition of several env vars to the `clinical-matching-service` container in the chart. All of these simply forward existing information from the chart or the k8s pod fieldspec as env vars. The intent is to make them available for the OTEL library reference as additional trace attributes.

# How to Test It

- For regressions: `make lint` and `make test`
- To see it locally: smoke install and `kubectl get pods -o yaml`

# How to See it

Check this [DD query](https://mcg.datadoghq.com/...) once you have access.
```

### No JIRA Issue
```markdown
## What's here

Harness was not working in chart deployments when auth was enabled due to a configuration problem. This PR updates the chart so that:

1. A service is always defined with access to the unauthenticated CMS service port
2. The network policy allows free communication between all pods
3. The envoy config for auth can be customized for harness & deployment

## How to test it

Deploy with harness and auth enabled:

```bash
export DV_ENABLE_AUTH_PROXY=true
make dv-install
```
```

---

## Quick Reference

```
> __See [ML-XXXX](https://mcghealth.atlassian.net/browse/ML-XXXX)__

## What's here

[Changes and why]

## How to test it

[Testing steps or reference to docs]
```
