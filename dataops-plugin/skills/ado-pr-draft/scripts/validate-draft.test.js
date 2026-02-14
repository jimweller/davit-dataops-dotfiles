#!/usr/bin/env bun
/**
 * Tests for validate-draft.js
 * Run with: bun test validate-draft.test.js
 */

import { describe, test, expect } from "bun:test";
import { parseFrontmatter, validateDraft } from "./validate-draft.js";

describe("parseFrontmatter", () => {
  test("parses valid frontmatter", () => {
    const content = `---
ado_draft_version: "1"
action: create_pr
project: "MyProject"
repository: "my-repo"
---

Body content here`;

    const result = parseFrontmatter(content);
    expect(result.frontmatter.ado_draft_version).toBe("1");
    expect(result.frontmatter.action).toBe("create_pr");
    expect(result.frontmatter.project).toBe("MyProject");
    expect(result.frontmatter.repository).toBe("my-repo");
    expect(result.body).toBe("Body content here");
  });

  test("handles missing opening delimiter", () => {
    const content = `action: create_pr
project: "MyProject"
---

Body`;

    const result = parseFrontmatter(content);
    expect(result.error).toContain("must start with YAML frontmatter");
  });

  test("handles missing closing delimiter", () => {
    const content = `---
action: create_pr
project: "MyProject"

Body without closing`;

    const result = parseFrontmatter(content);
    expect(result.error).toContain("not closed");
  });

  test("handles null values", () => {
    const content = `---
status: draft
published_url: null
---

Body`;

    const result = parseFrontmatter(content);
    expect(result.frontmatter.status).toBe("draft");
    expect(result.frontmatter.published_url).toBe(null);
  });

  test("handles boolean values", () => {
    const content = `---
is_draft: true
is_published: false
---

Body`;

    const result = parseFrontmatter(content);
    expect(result.frontmatter.is_draft).toBe(true);
    expect(result.frontmatter.is_published).toBe(false);
  });

  test("handles quoted strings", () => {
    const content = `---
title: "My PR: with special chars"
summary: 'Single quoted'
---

Body`;

    const result = parseFrontmatter(content);
    expect(result.frontmatter.title).toBe("My PR: with special chars");
    expect(result.frontmatter.summary).toBe("Single quoted");
  });
});

describe("validateDraft", () => {
  const validDraft = `---
ado_draft_version: "1"
action: create_pr
project: "clinical-matching"
repository: "cms-service"
source_branch: "feature/add-retry"
target_branch: "main"
title: "Add retry logic"
status: draft
---

## What's here

This PR adds retry logic.`;

  test("accepts valid draft", () => {
    const result = validateDraft(validDraft);
    expect(result.valid).toBe(true);
    expect(result.errors).toHaveLength(0);
  });

  test("rejects missing project (critical error)", () => {
    const draft = `---
ado_draft_version: "1"
action: create_pr
repository: "cms-service"
source_branch: "feature/add-retry"
target_branch: "main"
title: "Add retry logic"
---

## What's here

Content`;

    const result = validateDraft(draft);
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.includes("project"))).toBe(true);
    expect(result.errors.some(e => e.includes("CRITICAL"))).toBe(true);
  });

  test("rejects missing required fields", () => {
    const draft = `---
ado_draft_version: "1"
action: create_pr
project: "MyProject"
---

Body`;

    const result = validateDraft(draft);
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.includes("repository"))).toBe(true);
    expect(result.errors.some(e => e.includes("source_branch"))).toBe(true);
    expect(result.errors.some(e => e.includes("target_branch"))).toBe(true);
    expect(result.errors.some(e => e.includes("title"))).toBe(true);
  });

  test("rejects invalid action", () => {
    const draft = `---
ado_draft_version: "1"
action: invalid_action
project: "MyProject"
repository: "my-repo"
source_branch: "feature/x"
target_branch: "main"
title: "Title"
---

Body`;

    const result = validateDraft(draft);
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.includes("Invalid action"))).toBe(true);
  });

  test("warns about refs/heads prefix in branches", () => {
    const draft = `---
ado_draft_version: "1"
action: create_pr
project: "MyProject"
repository: "my-repo"
source_branch: "refs/heads/feature/x"
target_branch: "refs/heads/main"
title: "Title"
---

## What's here

Content`;

    const result = validateDraft(draft);
    expect(result.valid).toBe(true); // Still valid, just warnings
    expect(result.warnings.some(w => w.includes("refs/heads"))).toBe(true);
  });

  test("warns about missing 'What's here' section", () => {
    const draft = `---
ado_draft_version: "1"
action: create_pr
project: "MyProject"
repository: "my-repo"
source_branch: "feature/x"
target_branch: "main"
title: "Title"
---

Just some content without proper structure`;

    const result = validateDraft(draft);
    expect(result.valid).toBe(true); // Still valid, just warnings
    expect(result.warnings.some(w => w.includes("What's here"))).toBe(true);
  });

  test("warns about empty body", () => {
    const draft = `---
ado_draft_version: "1"
action: create_pr
project: "MyProject"
repository: "my-repo"
source_branch: "feature/x"
target_branch: "main"
title: "Title"
---

`;

    const result = validateDraft(draft);
    expect(result.valid).toBe(true);
    expect(result.warnings.some(w => w.includes("empty"))).toBe(true);
  });

  test("warns if jira_issue not found in body", () => {
    const draft = `---
ado_draft_version: "1"
action: create_pr
project: "MyProject"
repository: "my-repo"
source_branch: "feature/x"
target_branch: "main"
title: "Title"
jira_issue: "ML-1234"
---

## What's here

Content without the jira reference`;

    const result = validateDraft(draft);
    expect(result.valid).toBe(true);
    expect(result.warnings.some(w => w.includes("ML-1234"))).toBe(true);
  });

  test("no warning when jira_issue found in body", () => {
    const draft = `---
ado_draft_version: "1"
action: create_pr
project: "MyProject"
repository: "my-repo"
source_branch: "feature/x"
target_branch: "main"
title: "Title"
jira_issue: "ML-1234"
---

## What's here

> __See [ML-1234](https://...)__

Content`;

    const result = validateDraft(draft);
    expect(result.valid).toBe(true);
    expect(result.warnings.some(w => w.includes("ML-1234"))).toBe(false);
  });
});
