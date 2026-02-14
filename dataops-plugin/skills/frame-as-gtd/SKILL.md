---
description: "Reframe findings as GTD (Getting Things Done) output: Outcomes, Next Actions, Clarifications"
allowed-tools: []
model: sonnet
context: fork
---

# Frame as GTD

Reframe the provided findings using David Allen's Getting Things Done methodology.

## Input

The conversation context contains findings to reframe. This could be:
- Research results from `/research`
- Investigation findings
- Any analysis that might have actionable outcomes

## Output Format

```markdown
## Outcomes
*What about the world needs to be different?*

- [Desired end state 1]
- [Desired end state 2]

Note: Distinguish "GTD Projects" (multi-step outcomes requiring action) from "Corporate projects" (organizational units/labels).

## Next Actions
*The next physically visible step*

Only include if HIGH CONFIDENCE. Each action must be:
- **Specific**: Name the person, system, or artifact
- **Physical**: A visible activity (email, call, create, update)
- **Immediate**: The very next step, not a project plan

Examples:
- "Email jane.doe@company.com to confirm she is still the technical lead"
- "Create Jira ticket in PAY project for API timeout fix"
- "Update the team charter page (ID: 12345) with current members"

If uncertain about next steps, move items to "Needs Clarification" instead.

## Needs Clarification
*Ambiguities that block action*

- [Question or ambiguity that needs resolution before action can be taken]
- "Clarify: Is 'payment-service' the same as 'checkout-payments'?"
- "Clarify: John Smith listed as 'architect' in Confluence but 'tech lead' in Jira - which is current?"

## Reference Information
*Facts discovered that don't require action but are useful context*

- [Factual finding with source]
```

## Rules

1. **Don't invent actions** - Only list next actions when the findings clearly support them
2. **"Clarify X" is a valid action** - When something is ambiguous, the next action is to clarify it
3. **Be specific** - Vague actions like "follow up" or "investigate further" are not GTD-compliant
4. **Separate outcomes from actions** - Outcomes are end states; actions are steps toward them
5. **Preserve source attribution** - Keep references to where information came from

## When NOT to Use GTD Framing

If the original findings are purely informational with no actionable implications, say so:

```markdown
## GTD Assessment

These findings are **informational only** - no outcomes or actions identified.

### Summary
[Brief summary of the information]
```
