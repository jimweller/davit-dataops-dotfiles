#!/usr/bin/env bun
/**
 * confluence-md-to-adf.js - Convert styled markdown to Confluence ADF
 *
 * Usage:
 *   echo "markdown" | confluence-md-to-adf.js
 *   confluence-md-to-adf.js < file.md
 *
 * Style Guide:
 *   :::metadata owner="@Name" date="YYYY-MM-DD" :::     - Metadata table
 *   :::toc maxLevel=2 :::                               - Table of contents
 *   :::callout title="TITLE" color=red :::              - Callout box with lozenge
 *   # H1                - Bold + Grey (#97a0af)
 *   ## H2               - Bold + Grey (#97a0af)
 *   ##! H2              - Bold + Blue (#0747a6) for action sections
 *   ### H3              - Bold + Green (#003300)
 *   #### H4             - Bold + Grey (#97a0af)
 *   ##### H5            - Grey only (#97a0af)
 *   {status:TEXT:color} - Status lozenge
 *   **bold**, *italic*, `code`, [link](url)
 *   - bullets, 1. numbered
 *   | tables |
 *   ---                 - Horizontal rule
 *   {pageCard:url}      - Inline card for Confluence page
 */

const COLORS = {
  grey: "#97a0af",
  blue: "#0747a6",
  green: "#003300",
  headerBg: "#42526e",
  white: "#FFFFFF",
};

function uuid() {
  return crypto.randomUUID();
}

// Parse inline elements
function parseInline(text) {
  const nodes = [];
  let remaining = text;

  while (remaining.length > 0) {
    // Status lozenge: {status:TEXT:color}
    const statusMatch = remaining.match(/^\{status:([^:}]+):(\w+)\}/);
    if (statusMatch) {
      nodes.push({
        type: "status",
        attrs: {
          text: statusMatch[1],
          color: statusMatch[2],
          localId: uuid(),
          style: "bold",
        },
      });
      remaining = remaining.slice(statusMatch[0].length);
      continue;
    }

    // Page card: {pageCard:url}
    const pageCardMatch = remaining.match(/^\{pageCard:([^}]+)\}/);
    if (pageCardMatch) {
      nodes.push({
        type: "inlineCard",
        attrs: { url: pageCardMatch[1] },
      });
      remaining = remaining.slice(pageCardMatch[0].length);
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

    // Plain text - consume until next special char
    const plainMatch = remaining.match(/^[^*`\[{]+/);
    if (plainMatch) {
      nodes.push({ type: "text", text: plainMatch[0] });
      remaining = remaining.slice(plainMatch[0].length);
      continue;
    }

    // Fallback
    nodes.push({ type: "text", text: remaining[0] });
    remaining = remaining.slice(1);
  }

  // Merge adjacent plain text nodes
  const merged = [];
  for (const node of nodes) {
    const last = merged[merged.length - 1];
    if (last?.type === "text" && node.type === "text" && !last.marks && !node.marks) {
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
      return { type: "paragraph", attrs: { localId: uuid() } };
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
      attrs: { localId: uuid() },
      content: content,
    };
  }

  // Single text string
  if (!textOrLines || textOrLines.trim() === "") {
    return { type: "paragraph", attrs: { localId: uuid() } };
  }
  return {
    type: "paragraph",
    attrs: { localId: uuid() },
    content: parseInline(textOrLines),
  };
}

// Heading with style based on level
function heading(level, text, isBlue = false) {
  let color = COLORS.grey;
  let bold = true;

  if (isBlue) {
    color = COLORS.blue;
  } else if (level === 3) {
    color = COLORS.green;
  } else if (level === 5) {
    bold = false;
  }

  const marks = [{ type: "textColor", attrs: { color } }];
  if (bold) {
    marks.unshift({ type: "strong" });
  }

  return {
    type: "heading",
    attrs: { level, localId: uuid() },
    content: [{
      type: "text",
      text: text,
      marks: marks,
    }],
  };
}

// Metadata table (owner, date)
function metadataTable(owner, date) {
  const rows = [];

  if (owner) {
    rows.push({
      type: "tableRow",
      attrs: { localId: uuid() },
      content: [{
        type: "tableHeader",
        attrs: { colspan: 1, rowspan: 1, background: COLORS.headerBg, localId: uuid() },
        content: [paragraph("Content Owner")],
      }, {
        type: "tableCell",
        attrs: { colspan: 1, rowspan: 1, localId: uuid() },
        content: [paragraph(owner)],
      }],
    });
    // Style the header text white
    rows[rows.length - 1].content[0].content[0].content = [{
      type: "text",
      text: "Content Owner",
      marks: [{ type: "textColor", attrs: { color: COLORS.white } }],
    }];
  }

  if (date) {
    rows.push({
      type: "tableRow",
      attrs: { localId: uuid() },
      content: [{
        type: "tableHeader",
        attrs: { colspan: 1, rowspan: 1, background: COLORS.headerBg, localId: uuid() },
        content: [{
          type: "paragraph",
          attrs: { localId: uuid() },
          content: [{
            type: "text",
            text: "Last Update",
            marks: [{ type: "textColor", attrs: { color: COLORS.white } }],
          }],
        }],
      }, {
        type: "tableCell",
        attrs: { colspan: 1, rowspan: 1, localId: uuid() },
        content: [paragraph(date)],
      }],
    });
  }

  return {
    type: "table",
    attrs: { layout: "default", localId: uuid() },
    content: rows,
  };
}

// Table of contents macro
function tocMacro(maxLevel = 2) {
  return {
    type: "extension",
    attrs: {
      layout: "default",
      extensionType: "com.atlassian.confluence.macro.core",
      extensionKey: "toc",
      parameters: {
        macroParams: {
          maxLevel: { value: String(maxLevel) },
        },
        macroMetadata: {
          macroId: { value: uuid() },
          schemaVersion: { value: "1" },
          title: "Table of Contents",
        },
      },
      localId: uuid(),
    },
  };
}

// Callout box (table with status lozenge)
function calloutBox(title, color, content) {
  return {
    type: "table",
    attrs: { layout: "default", localId: uuid() },
    content: [{
      type: "tableRow",
      attrs: { localId: uuid() },
      content: [{
        type: "tableCell",
        attrs: { colspan: 1, rowspan: 1, localId: uuid() },
        content: [
          {
            type: "paragraph",
            attrs: { localId: uuid() },
            content: [
              { type: "status", attrs: { text: title, color, style: "bold", localId: uuid() } },
              { type: "text", text: " " },
            ],
          },
          ...content.map(p => paragraph(p)),
        ],
      }],
    }],
  };
}

// Horizontal rule
function rule() {
  return { type: "rule" };
}

// Parse table from markdown
function parseTable(lines) {
  const parseRow = (line) =>
    line.split("|").slice(1, -1).map((cell) => cell.trim());

  const headers = parseRow(lines[0]);
  const rows = lines.slice(2).map(parseRow);

  const tableContent = [];

  // Header row
  tableContent.push({
    type: "tableRow",
    attrs: { localId: uuid() },
    content: headers.map((h) => ({
      type: "tableHeader",
      attrs: { colspan: 1, rowspan: 1, localId: uuid() },
      content: [{
        type: "paragraph",
        attrs: { localId: uuid() },
        content: [{ type: "text", text: h, marks: [{ type: "strong" }] }],
      }],
    })),
  });

  // Data rows
  for (const row of rows) {
    tableContent.push({
      type: "tableRow",
      attrs: { localId: uuid() },
      content: row.map((cell) => ({
        type: "tableCell",
        attrs: { colspan: 1, rowspan: 1, localId: uuid() },
        content: [paragraph(cell)],
      })),
    });
  }

  return {
    type: "table",
    attrs: { layout: "default", localId: uuid() },
    content: tableContent,
  };
}

// Parse list
function parseList(lines, ordered = false) {
  const items = [];
  let currentItem = null;
  const itemPattern = ordered ? /^\d+\.\s+(.*)$/ : /^[-*]\s+(.*)$/;

  for (const line of lines) {
    const match = line.match(itemPattern);
    if (match) {
      if (currentItem) items.push(currentItem);
      currentItem = [match[1]];
    } else if (currentItem && line.match(/^\s+/)) {
      currentItem.push(line.trim());
    }
  }
  if (currentItem) items.push(currentItem);

  const listNode = {
    type: ordered ? "orderedList" : "bulletList",
    attrs: { localId: uuid() },
    content: items.map((item) => ({
      type: "listItem",
      attrs: { localId: uuid() },
      content: item.map((text) => paragraph(text)),
    })),
  };

  if (ordered) {
    listNode.attrs.order = 1;
  }

  return listNode;
}

// Main parser
function parseMarkdown(markdown) {
  const lines = markdown.split("\n");
  const content = [];
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];

    // Metadata block: :::metadata owner="@Name" date="YYYY-MM-DD" :::
    if (line.trim().startsWith(":::metadata")) {
      const ownerMatch = line.match(/owner="([^"]+)"/);
      const dateMatch = line.match(/date="([^"]+)"/);
      content.push(metadataTable(ownerMatch?.[1], dateMatch?.[1]));
      i++;
      continue;
    }

    // TOC block: :::toc maxLevel=2 :::
    if (line.trim().startsWith(":::toc")) {
      const maxMatch = line.match(/maxLevel=(\d+)/);
      content.push(tocMacro(maxMatch ? parseInt(maxMatch[1]) : 2));
      i++;
      continue;
    }

    // Callout block: :::callout title="TITLE" color=red
    if (line.trim().startsWith(":::callout")) {
      const titleMatch = line.match(/title="([^"]+)"/);
      const colorMatch = line.match(/color=(\w+)/);
      const calloutContent = [];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith(":::")) {
        if (lines[i].trim()) calloutContent.push(lines[i].trim());
        i++;
      }
      i++; // skip closing :::
      content.push(calloutBox(
        titleMatch?.[1] || "NOTE",
        colorMatch?.[1] || "blue",
        calloutContent
      ));
      continue;
    }

    // Horizontal rule: ---
    if (line.trim() === "---") {
      content.push(rule());
      i++;
      continue;
    }

    // Heading with blue marker: ##! H2
    const blueHeadingMatch = line.match(/^(#{2,4})!\s+(.+)$/);
    if (blueHeadingMatch) {
      const level = blueHeadingMatch[1].length;
      content.push(heading(level, blueHeadingMatch[2], true));
      i++;
      continue;
    }

    // Regular heading: # H1, ## H2, etc.
    const headingMatch = line.match(/^(#{1,5})\s+(.+)$/);
    if (headingMatch) {
      const level = headingMatch[1].length;
      content.push(heading(level, headingMatch[2], false));
      i++;
      continue;
    }

    // Table
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

    // Bullet list
    if (line.match(/^[-*]\s+/)) {
      const listLines = [];
      while (i < lines.length && (lines[i].match(/^[-*]\s+/) || lines[i].match(/^\s+\S/))) {
        listLines.push(lines[i]);
        i++;
      }
      content.push(parseList(listLines, false));
      continue;
    }

    // Numbered list
    if (line.match(/^\d+\.\s+/)) {
      const listLines = [];
      while (i < lines.length && (lines[i].match(/^\d+\.\s+/) || lines[i].match(/^\s+\S/))) {
        listLines.push(lines[i]);
        i++;
      }
      content.push(parseList(listLines, true));
      continue;
    }

    // Empty line
    if (line.trim() === "") {
      i++;
      continue;
    }

    // Regular paragraph
    const paraLines = [];
    while (i < lines.length &&
           lines[i].trim() !== "" &&
           !lines[i].match(/^#{1,5}\s/) &&
           !lines[i].match(/^\|/) &&
           !lines[i].match(/^[-*]\s/) &&
           !lines[i].match(/^\d+\.\s/) &&
           !lines[i].match(/^:::/) &&
           lines[i].trim() !== "---") {
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
