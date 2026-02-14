#!/usr/bin/env bun
/**
 * Tests for md-to-adf.js
 * Run with: bun test md-to-adf.test.js
 */

import { describe, test, expect } from "bun:test";
import { $ } from "bun";

const SCRIPT = import.meta.dir + "/md-to-adf.js";

async function convert(markdown) {
  const result = await $`echo ${markdown} | ${SCRIPT}`.text();
  return JSON.parse(result);
}

describe("md-to-adf", () => {
  describe("bullet lists", () => {
    test("basic bullet list", async () => {
      const md = `- item one
- item two
- item three`;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("bulletList");
      expect(adf.content[0].content).toHaveLength(3);
      expect(adf.content[0].content[0].type).toBe("listItem");
    });

    test("bullet list with leading whitespace", async () => {
      const md = ` - item one
 - item two`;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("bulletList");
      expect(adf.content[0].content).toHaveLength(2);
    });

    test("bullet list with asterisks", async () => {
      const md = `* item one
* item two`;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("bulletList");
    });

    test("bullet list with inline formatting", async () => {
      const md = `- **bold item**
- item with \`code\`
- item with [link](http://example.com)`;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("bulletList");
      // Check bold item
      const boldContent = adf.content[0].content[0].content[0].content[0];
      expect(boldContent.marks[0].type).toBe("strong");
    });
  });

  describe("numbered lists", () => {
    test("basic numbered list", async () => {
      const md = `1. first item
2. second item
3. third item`;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("orderedList");
      expect(adf.content[0].content).toHaveLength(3);
      expect(adf.content[0].attrs.order).toBe(1);
    });

    test("numbered list with leading whitespace", async () => {
      const md = ` 1. Fix: Reliable CMS Version
 2. Enhancement: Add Agent Version
 3. Enhancement: Add Agent to OTEL`;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("orderedList");
      expect(adf.content[0].content).toHaveLength(3);
      // Verify content is correct
      const firstItem = adf.content[0].content[0].content[0].content[0].text;
      expect(firstItem).toBe("Fix: Reliable CMS Version");
    });
  });

  describe("lists with context", () => {
    test("list after heading", async () => {
      const md = `## Section

- item one
- item two`;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("heading");
      expect(adf.content[1].type).toBe("bulletList");
    });

    test("list between paragraphs", async () => {
      const md = `Some text before

- bullet one
- bullet two

Some text after`;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("paragraph");
      expect(adf.content[1].type).toBe("bulletList");
      expect(adf.content[2].type).toBe("paragraph");
    });
  });

  describe("headings", () => {
    test("h2 heading", async () => {
      const md = `## Section Title`;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("heading");
      expect(adf.content[0].attrs.level).toBe(2);
    });

    test("h3 heading", async () => {
      const md = `### Subsection`;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("heading");
      expect(adf.content[0].attrs.level).toBe(3);
    });

    test("h4 heading with blue color", async () => {
      const md = `#### Detail`;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("heading");
      expect(adf.content[0].attrs.level).toBe(4);
      const marks = adf.content[0].content[0].marks;
      const colorMark = marks.find(m => m.type === "textColor");
      expect(colorMark.attrs.color).toBe("#0747a6");
    });
  });

  describe("inline elements", () => {
    test("bold text", async () => {
      const md = `This is **bold** text`;
      const adf = await convert(md);

      const content = adf.content[0].content;
      const boldNode = content.find(n => n.marks?.[0]?.type === "strong");
      expect(boldNode.text).toBe("bold");
    });

    test("italic text", async () => {
      const md = `This is *italic* text`;
      const adf = await convert(md);

      const content = adf.content[0].content;
      const italicNode = content.find(n => n.marks?.[0]?.type === "em");
      expect(italicNode.text).toBe("italic");
    });

    test("code inline", async () => {
      const md = `Use the \`command\` here`;
      const adf = await convert(md);

      const content = adf.content[0].content;
      const codeNode = content.find(n => n.marks?.[0]?.type === "code");
      expect(codeNode.text).toBe("command");
    });

    test("links", async () => {
      const md = `Check [this link](http://example.com) out`;
      const adf = await convert(md);

      const content = adf.content[0].content;
      const linkNode = content.find(n => n.marks?.[0]?.type === "link");
      expect(linkNode.text).toBe("this link");
      expect(linkNode.marks[0].attrs.href).toBe("http://example.com");
    });
  });

  describe("context blocks", () => {
    test("basic context block", async () => {
      const md = `:::context
This is context information.
:::`;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("table");
      // First paragraph should have the CONTEXT status lozenge
      const firstPara = adf.content[0].content[0].content[0].content[0];
      expect(firstPara.content[0].type).toBe("status");
      expect(firstPara.content[0].attrs.text).toBe("CONTEXT");
    });
  });

  describe("blockquotes", () => {
    test("basic blockquote", async () => {
      const md = `> This is a quote`;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("blockquote");
    });
  });

  describe("horizontal rules", () => {
    test("dashes rule", async () => {
      const md = `---`;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("rule");
    });
  });

  describe("fenced code blocks", () => {
    test("basic code block without language", async () => {
      const md = `\`\`\`
const x = 1;
\`\`\``;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("codeBlock");
      expect(adf.content[0].content[0].text).toBe("const x = 1;");
      expect(adf.content[0].attrs).toBeUndefined();
    });

    test("code block with language", async () => {
      const md = `\`\`\`javascript
const x = 1;
\`\`\``;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("codeBlock");
      expect(adf.content[0].attrs.language).toBe("javascript");
    });

    test("code block with multiple lines", async () => {
      const md = `\`\`\`bash
echo "line 1"
echo "line 2"
echo "line 3"
\`\`\``;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("codeBlock");
      expect(adf.content[0].content[0].text).toContain("line 1");
      expect(adf.content[0].content[0].text).toContain("line 2");
      expect(adf.content[0].content[0].text).toContain("line 3");
    });

    test("code block preserves indentation", async () => {
      const md = `\`\`\`python
def foo():
    return 42
\`\`\``;
      const adf = await convert(md);

      expect(adf.content[0].content[0].text).toContain("    return 42");
    });

    test("code block between other elements", async () => {
      const md = `## Section

\`\`\`bash
echo "hello"
\`\`\`

Some text after.`;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("heading");
      expect(adf.content[1].type).toBe("codeBlock");
      expect(adf.content[2].type).toBe("paragraph");
    });
  });

  describe("line breaks in paragraphs", () => {
    test("single line break preserved as hardBreak", async () => {
      const md = `**Before:** Warning logged when directory is created
**After:** Log directories at info level`;
      const adf = await convert(md);

      // Should be a single paragraph with hardBreak between lines
      expect(adf.content[0].type).toBe("paragraph");
      const content = adf.content[0].content;
      // Should contain a hardBreak node
      const hasHardBreak = content.some(n => n.type === "hardBreak");
      expect(hasHardBreak).toBe(true);
    });

    test("multiple line breaks in paragraph", async () => {
      const md = `Line one
Line two
Line three`;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("paragraph");
      const content = adf.content[0].content;
      // Should have 2 hardBreaks (between 3 lines)
      const hardBreaks = content.filter(n => n.type === "hardBreak");
      expect(hardBreaks).toHaveLength(2);
    });

    test("behavior change format preserved", async () => {
      const md = `## Behavior Change

**Before:** Warning logged when directory is created in monitored folder
**After:** Log directories that are noticed at the info level (would be nice to know about them)`;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("heading");
      expect(adf.content[1].type).toBe("paragraph");

      const paraContent = adf.content[1].content;
      // Check that "Before:" and "After:" are separated by hardBreak
      const hasHardBreak = paraContent.some(n => n.type === "hardBreak");
      expect(hasHardBreak).toBe(true);

      // Check that both Before and After text appear
      const textContent = paraContent.filter(n => n.type === "text").map(n => n.text).join("");
      expect(textContent).toContain("Warning logged");
      expect(textContent).toContain("Log directories");
    });

    test("empty line creates separate paragraphs", async () => {
      const md = `First paragraph

Second paragraph`;
      const adf = await convert(md);

      // Should be two separate paragraphs
      expect(adf.content).toHaveLength(2);
      expect(adf.content[0].type).toBe("paragraph");
      expect(adf.content[1].type).toBe("paragraph");
    });

    test("line break after bold text", async () => {
      const md = `**Bold line**
Normal line after`;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("paragraph");
      const content = adf.content[0].content;
      const hasHardBreak = content.some(n => n.type === "hardBreak");
      expect(hasHardBreak).toBe(true);
    });
  });

  describe("frontmatter stripping", () => {
    test("strips YAML frontmatter", async () => {
      const md = `---
action: create
project: ML
summary: "Test issue"
---

## Heading

Content here.`;
      const adf = await convert(md);

      // Should start with heading, not rule or paragraph from frontmatter
      expect(adf.content[0].type).toBe("heading");
      expect(adf.content[0].content[0].text).toBe("Heading");
    });

    test("handles content without frontmatter", async () => {
      const md = `## Heading

Content here.`;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("heading");
    });

    test("preserves horizontal rules after frontmatter", async () => {
      const md = `---
status: draft
---

## Section

---

More content.`;
      const adf = await convert(md);

      expect(adf.content[0].type).toBe("heading");
      expect(adf.content[1].type).toBe("rule");
      expect(adf.content[2].type).toBe("paragraph");
    });
  });
});
