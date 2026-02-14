#!/usr/bin/env bun
/**
 * validate-draft.js - Validate ADO PR draft files
 *
 * Usage:
 *   validate-draft.js <path-to-draft.md>
 *   cat draft.md | validate-draft.js -
 *
 * Returns JSON:
 *   { "valid": true, "frontmatter": {...}, "body": "..." }
 *   { "valid": false, "errors": ["..."], "warnings": ["..."] }
 */

const REQUIRED_FIELDS = [
  "ado_draft_version",
  "action",
  "project",
  "repository",
  "source_branch",
  "target_branch",
  "title",
];

const VALID_ACTIONS = ["create_pr"];

function parseFrontmatter(content) {
  const lines = content.split("\n");

  // Check for opening ---
  if (lines[0].trim() !== "---") {
    return { error: "Draft must start with YAML frontmatter (---)" };
  }

  // Find closing ---
  let endIndex = -1;
  for (let i = 1; i < lines.length; i++) {
    if (lines[i].trim() === "---") {
      endIndex = i;
      break;
    }
  }

  if (endIndex === -1) {
    return { error: "Frontmatter not closed (missing ---)" };
  }

  // Parse YAML (simple key: value parsing)
  const frontmatter = {};
  const yamlLines = lines.slice(1, endIndex);

  for (const line of yamlLines) {
    if (line.trim() === "" || line.trim().startsWith("#")) continue;

    const colonIndex = line.indexOf(":");
    if (colonIndex === -1) continue;

    const key = line.slice(0, colonIndex).trim();
    let value = line.slice(colonIndex + 1).trim();

    // Handle quoted strings
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }

    // Handle null
    if (value === "null" || value === "") {
      value = null;
    }

    // Handle booleans
    if (value === "true") value = true;
    if (value === "false") value = false;

    frontmatter[key] = value;
  }

  // Extract body (everything after frontmatter)
  const body = lines.slice(endIndex + 1).join("\n").trim();

  return { frontmatter, body };
}

function validateDraft(content) {
  const errors = [];
  const warnings = [];

  // Parse frontmatter
  const parsed = parseFrontmatter(content);

  if (parsed.error) {
    return { valid: false, errors: [parsed.error], warnings: [] };
  }

  const { frontmatter, body } = parsed;

  // Check required fields
  for (const field of REQUIRED_FIELDS) {
    if (!frontmatter[field]) {
      errors.push(`Missing required field: ${field}`);
    }
  }

  // Validate action
  if (frontmatter.action && !VALID_ACTIONS.includes(frontmatter.action)) {
    errors.push(`Invalid action: ${frontmatter.action}. Must be one of: ${VALID_ACTIONS.join(", ")}`);
  }

  // Check project specifically (common error)
  if (!frontmatter.project) {
    errors.push("CRITICAL: 'project' is missing - MCP call will fail without projectId");
  }

  // Validate branch names don't have refs/heads prefix (we add it during publish)
  if (frontmatter.source_branch?.startsWith("refs/heads/")) {
    warnings.push("source_branch should not include 'refs/heads/' prefix - it's added during publish");
  }
  if (frontmatter.target_branch?.startsWith("refs/heads/")) {
    warnings.push("target_branch should not include 'refs/heads/' prefix - it's added during publish");
  }

  // Check body has content
  if (!body || body.length < 10) {
    warnings.push("PR description is empty or very short");
  }

  // Check for "What's here" section (from style guide)
  if (body && !body.includes("What's here") && !body.includes("What's Here")) {
    warnings.push("Missing '## What's here' section (recommended by style guide)");
  }

  // Check for Jira link if jira_issue is specified
  if (frontmatter.jira_issue && body) {
    const jiraPattern = new RegExp(frontmatter.jira_issue, "i");
    if (!jiraPattern.test(body)) {
      warnings.push(`jira_issue '${frontmatter.jira_issue}' specified but not found in body`);
    }
  }

  return {
    valid: errors.length === 0,
    errors,
    warnings,
    frontmatter,
    body,
  };
}

// Export for testing
export { parseFrontmatter, validateDraft };

// Main - only run when executed directly
async function main() {
  let content;

  const arg = process.argv[2];

  if (!arg) {
    console.error("Usage: validate-draft.js <path-to-draft.md> | -");
    process.exit(1);
  }

  if (arg === "-") {
    content = await Bun.stdin.text();
  } else {
    const file = Bun.file(arg);
    if (!(await file.exists())) {
      console.error(JSON.stringify({ valid: false, errors: [`File not found: ${arg}`], warnings: [] }));
      process.exit(1);
    }
    content = await file.text();
  }

  const result = validateDraft(content);
  console.log(JSON.stringify(result, null, 2));

  // Exit with error code if invalid
  process.exit(result.valid ? 0 : 1);
}

// Only run main() when executed directly (not when imported)
if (import.meta.main) {
  main().catch((err) => {
    console.error(JSON.stringify({ valid: false, errors: [err.message], warnings: [] }));
    process.exit(1);
  });
}
