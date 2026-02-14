#!/usr/bin/env bun
/**
 * md-to-adf.js - Convert styled markdown to Atlassian Document Format (ADF)
 *
 * Usage:
 *   echo "markdown" | md-to-adf.js
 *   md-to-adf.js < file.md
 *
 * Style Guide:
 *   :::context        - Context block (table with CONTEXT lozenge)
 *   ## H2             - Bold + Grey (#97a0af)
 *   ### H3            - Bold + Grey (#97a0af)
 *   #### H4           - Bold + Blue (#0747a6)
 *   {status:TEXT:color} - Status lozenge (colors: neutral, purple, blue, green, yellow, red)
 *   **bold**, *italic*, `code`
 *   ```lang ... ```   - Fenced code block with optional language
 *   - bullet, 1. numbered
 *   | tables |
 *   [link](url), PROJ-123 (auto inline card)
 */

const COLORS = {
  headingGrey: "#97a0af",
  headingBlue: "#0747a6",
};

// Generate UUID for status lozenges
function uuid() {
  return crypto.randomUUID();
}

// Parse inline elements (bold, italic, code, links, status, jira keys, mentions)
function parseInline(text) {
  const nodes = [];
  let remaining = text;

  while (remaining.length > 0) {
    // Mention: @email@domain.com (email format)
    // Outputs placeholder with email in id field - must be resolved before publish
    const mentionMatch = remaining.match(/^@([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/);
    if (mentionMatch) {
      const email = mentionMatch[1];
      nodes.push({
        type: "mention",
        attrs: {
          id: `__EMAIL__:${email}`,  // placeholder - publish skill must resolve
          text: `@${email}`,
          accessLevel: "",
        },
      });
      remaining = remaining.slice(mentionMatch[0].length);
      continue;
    }

    // Status lozenge: {status:TEXT:color}
    const statusMatch = remaining.match(/^\{status:([^:}]+):(\w+)\}/);
    if (statusMatch) {
      nodes.push({
        type: "status",
        attrs: {
          text: statusMatch[1],
          color: statusMatch[2],
          localId: uuid(),
          style: "",
        },
      });
      remaining = remaining.slice(statusMatch[0].length);
      continue;
    }

    // Bold: **text**
    const boldMatch = remaining.match(/^\*\*([^*]+)\*\*/);
    if (boldMatch) {
      nodes.push({
        type: "text",
        text: boldMatch[1],
        marks: [{ type: "strong" }],
      });
      remaining = remaining.slice(boldMatch[0].length);
      continue;
    }

    // Italic: *text*
    const italicMatch = remaining.match(/^\*([^*]+)\*/);
    if (italicMatch) {
      nodes.push({
        type: "text",
        text: italicMatch[1],
        marks: [{ type: "em" }],
      });
      remaining = remaining.slice(italicMatch[0].length);
      continue;
    }

    // Code: `text`
    const codeMatch = remaining.match(/^`([^`]+)`/);
    if (codeMatch) {
      nodes.push({
        type: "text",
        text: codeMatch[1],
        marks: [{ type: "code" }],
      });
      remaining = remaining.slice(codeMatch[0].length);
      continue;
    }

    // Link: [text](url)
    const linkMatch = remaining.match(/^\[([^\]]+)\]\(([^)]+)\)/);
    if (linkMatch) {
      nodes.push({
        type: "text",
        text: linkMatch[1],
        marks: [{ type: "link", attrs: { href: linkMatch[2] } }],
      });
      remaining = remaining.slice(linkMatch[0].length);
      continue;
    }

    // Jira issue key: PROJ-123 (but not inside words)
    const jiraMatch = remaining.match(/^([A-Z][A-Z0-9]+-\d+)/);
    if (jiraMatch) {
      const baseUrl = process.env.ATLASSIAN_BASE_URL || "https://atlassian.net";
      nodes.push({
        type: "inlineCard",
        attrs: {
          url: `${baseUrl.replace(/\/$/, "")}/browse/${jiraMatch[1]}`,
        },
      });
      remaining = remaining.slice(jiraMatch[0].length);
      continue;
    }

    // Plain text - consume until next special char (including @)
    const plainMatch = remaining.match(/^[^*`\[{A-Z@]+|^[A-Z](?![A-Z0-9]+-\d)|^@(?![a-zA-Z0-9._%+-]+@)/);
    if (plainMatch) {
      nodes.push({ type: "text", text: plainMatch[0] });
      remaining = remaining.slice(plainMatch[0].length);
      continue;
    }

    // Fallback - consume one char
    nodes.push({ type: "text", text: remaining[0] });
    remaining = remaining.slice(1);
  }

  // Merge adjacent text nodes without marks
  const merged = [];
  for (const node of nodes) {
    const last = merged[merged.length - 1];
    if (
      last &&
      last.type === "text" &&
      node.type === "text" &&
      !last.marks &&
      !node.marks
    ) {
      last.text += node.text;
    } else {
      merged.push(node);
    }
  }

  return merged;
}

// Create a paragraph node from a single line or array of lines
// When given an array, inserts hardBreak nodes between lines
function paragraph(textOrLines) {
  // Handle array of lines - insert hardBreaks between them
  if (Array.isArray(textOrLines)) {
    const lines = textOrLines.filter(line => line.trim() !== "");
    if (lines.length === 0) {
      return { type: "paragraph" };
    }
    if (lines.length === 1) {
      return paragraph(lines[0]);
    }
    // Multiple lines - join with hardBreak nodes
    const content = [];
    for (let i = 0; i < lines.length; i++) {
      content.push(...parseInline(lines[i]));
      if (i < lines.length - 1) {
        content.push({ type: "hardBreak" });
      }
    }
    return {
      type: "paragraph",
      content: content,
    };
  }

  // Single text string
  if (!textOrLines || textOrLines.trim() === "") {
    return { type: "paragraph" };
  }
  return {
    type: "paragraph",
    content: parseInline(textOrLines),
  };
}

// Create a heading node with style
function heading(level, text) {
  const color = level === 4 ? COLORS.headingBlue : COLORS.headingGrey;
  return {
    type: "heading",
    attrs: { level },
    content: [
      {
        type: "text",
        text: text,
        marks: [
          { type: "strong" },
          { type: "textColor", attrs: { color } },
        ],
      },
    ],
  };
}

// Create context block (single-cell table with CONTEXT lozenge)
function contextBlock(paragraphs, color = "purple") {
  const content = [
    {
      type: "paragraph",
      content: [
        {
          type: "status",
          attrs: {
            text: "CONTEXT",
            color: color,
            localId: uuid(),
            style: "",
          },
        },
        { type: "text", text: " " },
      ],
    },
    ...paragraphs.map((p) => paragraph(p)),
  ];

  return {
    type: "table",
    attrs: {
      isNumberColumnEnabled: false,
      layout: "align-start",
      localId: uuid(),
    },
    content: [
      {
        type: "tableRow",
        content: [
          {
            type: "tableCell",
            attrs: {},
            content: content,
          },
        ],
      },
    ],
  };
}

// Parse table from markdown lines
function parseTable(lines) {
  // lines[0] = header row, lines[1] = separator, lines[2+] = data rows
  const parseRow = (line) =>
    line
      .split("|")
      .slice(1, -1)
      .map((cell) => cell.trim());

  const headers = parseRow(lines[0]);
  const rows = lines.slice(2).map(parseRow);

  const tableContent = [];

  // Header row
  tableContent.push({
    type: "tableRow",
    content: headers.map((h) => ({
      type: "tableHeader",
      attrs: {},
      content: [
        {
          type: "paragraph",
          content: [{ type: "text", text: h, marks: [{ type: "strong" }] }],
        },
      ],
    })),
  });

  // Data rows
  for (const row of rows) {
    tableContent.push({
      type: "tableRow",
      content: row.map((cell) => ({
        type: "tableCell",
        attrs: {},
        content: [paragraph(cell)],
      })),
    });
  }

  return {
    type: "table",
    attrs: {
      isNumberColumnEnabled: false,
      layout: "align-start",
      localId: uuid(),
    },
    content: tableContent,
  };
}

// Parse list items
function parseList(lines, ordered = false) {
  const items = [];
  let currentItem = null;
  // Allow optional leading whitespace for list items
  const itemPattern = ordered ? /^\s*\d+\.\s+(.*)$/ : /^\s*[-*]\s+(.*)$/;

  for (const line of lines) {
    const match = line.match(itemPattern);
    if (match) {
      if (currentItem) items.push(currentItem);
      currentItem = [match[1]];
    } else if (currentItem && line.match(/^\s+/)) {
      // Continuation of current item
      currentItem.push(line.trim());
    }
  }
  if (currentItem) items.push(currentItem);

  const listNode = {
    type: ordered ? "orderedList" : "bulletList",
    content: items.map((item) => ({
      type: "listItem",
      content: [paragraph(item.join(" "))],  // join continuation lines with space
    })),
  };

  if (ordered) {
    listNode.attrs = { order: 1 };
  }

  return listNode;
}

// Strip YAML frontmatter if present
function stripFrontmatter(markdown) {
  const lines = markdown.split("\n");

  // Check if first line is --- (frontmatter delimiter)
  if (lines[0]?.trim() === "---") {
    // Find the closing ---
    for (let i = 1; i < lines.length; i++) {
      if (lines[i].trim() === "---") {
        // Return everything after the closing ---
        return lines.slice(i + 1).join("\n");
      }
    }
  }

  return markdown;
}

// Main parser
function parseMarkdown(markdown) {
  // Strip frontmatter before parsing
  markdown = stripFrontmatter(markdown);

  // Warn if content is empty after stripping frontmatter
  if (!markdown.trim()) {
    console.error(
      "Warning: No content after stripping frontmatter. The document body is empty.",
    );
  }

  const lines = markdown.split("\n");
  const content = [];
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];

    // Fenced code block: ```lang ... ```
    const codeBlockMatch = line.match(/^```(\w*)$/);
    if (codeBlockMatch) {
      const language = codeBlockMatch[1] || null;
      const codeLines = [];
      i++;
      while (i < lines.length && !lines[i].match(/^```$/)) {
        codeLines.push(lines[i]);
        i++;
      }
      i++; // skip closing ```
      const codeBlock = {
        type: "codeBlock",
        content: [{ type: "text", text: codeLines.join("\n") }],
      };
      if (language) {
        codeBlock.attrs = { language };
      }
      content.push(codeBlock);
      continue;
    }

    // Context block: :::context ... :::
    if (line.trim() === ":::context") {
      const contextLines = [];
      i++;
      while (i < lines.length && lines[i].trim() !== ":::") {
        contextLines.push(lines[i]);
        i++;
      }
      i++; // skip closing :::
      const paragraphs = contextLines
        .join("\n")
        .split("\n\n")
        .map((p) => p.replace(/\n/g, " ").trim())  // collapse single newlines to spaces
        .filter((p) => p);
      content.push(contextBlock(paragraphs));
      continue;
    }

    // Heading: ## H2, ### H3, #### H4
    const headingMatch = line.match(/^(#{2,4})\s+(.+)$/);
    if (headingMatch) {
      const level = headingMatch[1].length;
      content.push(heading(level, headingMatch[2]));
      i++;
      continue;
    }

    // Table: | header |
    if (line.match(/^\|.*\|$/)) {
      const tableLines = [];
      while (i < lines.length && lines[i].match(/^\|.*\|$/)) {
        tableLines.push(lines[i]);
        i++;
      }
      if (tableLines.length >= 2) {
        content.push(parseTable(tableLines));
      }
      continue;
    }

    // Bullet list: - item or * item (with optional leading whitespace)
    if (line.match(/^\s*[-*]\s+/)) {
      const listLines = [];
      while (i < lines.length && (lines[i].match(/^\s*[-*]\s+/) || lines[i].match(/^\s+\S/))) {
        listLines.push(lines[i]);
        i++;
      }
      content.push(parseList(listLines, false));
      continue;
    }

    // Numbered list: 1. item (with optional leading whitespace)
    if (line.match(/^\s*\d+\.\s+/)) {
      const listLines = [];
      while (i < lines.length && (lines[i].match(/^\s*\d+\.\s+/) || lines[i].match(/^\s+\S/))) {
        listLines.push(lines[i]);
        i++;
      }
      content.push(parseList(listLines, true));
      continue;
    }

    // Horizontal rule: ---, ***, ___
    if (line.match(/^(-{3,}|\*{3,}|_{3,})$/)) {
      content.push({ type: "rule" });
      i++;
      continue;
    }

    // Blockquote: > text
    if (line.match(/^>\s?/)) {
      const quoteLines = [];
      while (i < lines.length && lines[i].match(/^>\s?/)) {
        // Remove the > prefix and optional space
        quoteLines.push(lines[i].replace(/^>\s?/, ""));
        i++;
      }
      // Parse the blockquote content recursively to support nested formatting
      const quoteContent = parseMarkdown(quoteLines.join("\n")).content;
      content.push({
        type: "blockquote",
        content: quoteContent.length > 0 ? quoteContent : [{ type: "paragraph" }],
      });
      continue;
    }

    // Empty line
    if (line.trim() === "") {
      i++;
      continue;
    }

    // Regular paragraph
    const paraLines = [];
    while (i < lines.length && lines[i].trim() !== "" && !lines[i].match(/^#{2,4}\s/) && !lines[i].match(/^\|/) && !lines[i].match(/^\s*[-*]\s+/) && !lines[i].match(/^\s*\d+\.\s+/) && !lines[i].match(/^:::/) && !lines[i].match(/^(-{3,}|\*{3,}|_{3,})$/) && !lines[i].match(/^>\s/) && !lines[i].match(/^```/)) {
      paraLines.push(lines[i]);
      i++;
    }
    if (paraLines.length > 0) {
      content.push(paragraph(paraLines));  // Pass array to insert hardBreaks
    }
  }

  return {
    version: 1,
    type: "doc",
    content: content,
  };
}

// Main
async function main() {
  const input = await Bun.stdin.text();
  const adf = parseMarkdown(input);
  console.log(JSON.stringify(adf));
}

main().catch((err) => {
  console.error("Error:", err.message);
  process.exit(1);
});
