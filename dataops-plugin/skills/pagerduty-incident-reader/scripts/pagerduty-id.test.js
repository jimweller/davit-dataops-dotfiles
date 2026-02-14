#!/usr/bin/env bun
/**
 * Tests for PagerDuty ID detection utilities.
 * Run with: bun test pagerduty-id.test.js
 */

import { describe, test, expect } from "bun:test";
import {
  identifyIdType,
  looksLikeServiceId,
  looksLikeIncidentId,
  generateIdMismatchError,
  parseSkillInput,
} from "./pagerduty-id.js";

describe("identifyIdType", () => {
  describe("service IDs", () => {
    test("identifies typical service ID (PG7CZUT)", () => {
      const result = identifyIdType("PG7CZUT");
      expect(result.type).toBe("service");
      expect(result.confidence).toBe("high");
    });

    test("identifies service ID with different letters (PABC123)", () => {
      const result = identifyIdType("PABC123");
      expect(result.type).toBe("service");
      expect(result.confidence).toBe("high");
    });

    test("identifies short ID without P prefix as likely service", () => {
      const result = identifyIdType("ABC1234");
      expect(result.type).toBe("service");
      expect(result.confidence).toBe("medium");
    });

    test("handles lowercase input", () => {
      const result = identifyIdType("pg7czut");
      expect(result.type).toBe("service");
      expect(result.confidence).toBe("high");
    });

    test("handles whitespace", () => {
      const result = identifyIdType("  PG7CZUT  ");
      expect(result.type).toBe("service");
      expect(result.confidence).toBe("high");
    });
  });

  describe("incident IDs", () => {
    test("identifies typical incident ID (Q0RIJJZL24RC6W)", () => {
      const result = identifyIdType("Q0RIJJZL24RC6W");
      expect(result.type).toBe("incident");
      expect(result.confidence).toBe("high");
    });

    test("identifies incident ID without Q prefix as likely incident", () => {
      const result = identifyIdType("P0RIJJZL24RC6W");
      expect(result.type).toBe("incident");
      expect(result.confidence).toBe("medium");
    });

    test("handles lowercase incident ID", () => {
      const result = identifyIdType("q0rijjzl24rc6w");
      expect(result.type).toBe("incident");
      expect(result.confidence).toBe("high");
    });
  });

  describe("edge cases", () => {
    test("handles null input", () => {
      const result = identifyIdType(null);
      expect(result.type).toBe("unknown");
      expect(result.confidence).toBe("low");
    });

    test("handles undefined input", () => {
      const result = identifyIdType(undefined);
      expect(result.type).toBe("unknown");
      expect(result.confidence).toBe("low");
    });

    test("handles empty string", () => {
      const result = identifyIdType("");
      expect(result.type).toBe("unknown");
      expect(result.confidence).toBe("low");
    });

    test("rejects IDs with special characters", () => {
      const result = identifyIdType("PG7-CZUT");
      expect(result.type).toBe("unknown");
      expect(result.reason).toContain("invalid characters");
    });

    test("handles ambiguous length IDs", () => {
      const result = identifyIdType("PABCDEFGHIJ"); // 11 chars
      expect(result.confidence).toBe("low");
    });

    test("handles very short IDs", () => {
      const result = identifyIdType("ABC");
      expect(result.type).toBe("unknown");
    });

    test("handles very long IDs", () => {
      const result = identifyIdType("ABCDEFGHIJKLMNOPQRSTUVWXYZ");
      expect(result.type).toBe("unknown");
    });
  });
});

describe("looksLikeServiceId", () => {
  test("returns true for service-like IDs", () => {
    expect(looksLikeServiceId("PG7CZUT")).toBe(true);
    expect(looksLikeServiceId("PABC123")).toBe(true);
  });

  test("returns false for incident-like IDs", () => {
    expect(looksLikeServiceId("Q0RIJJZL24RC6W")).toBe(false);
  });
});

describe("looksLikeIncidentId", () => {
  test("returns true for incident-like IDs", () => {
    expect(looksLikeIncidentId("Q0RIJJZL24RC6W")).toBe(true);
  });

  test("returns false for service-like IDs", () => {
    expect(looksLikeIncidentId("PG7CZUT")).toBe(false);
  });
});

describe("generateIdMismatchError", () => {
  test("returns empty string when ID matches expected type", () => {
    const error = generateIdMismatchError("PG7CZUT", "service");
    expect(error).toBe("");
  });

  test("generates error when service ID passed to incident reader", () => {
    const error = generateIdMismatchError("PG7CZUT", "incident", "root cause");
    expect(error).toContain("ID format mismatch");
    expect(error).toContain("SERVICE ID");
    expect(error).toContain("pagerduty-service-reader");
    expect(error).toContain("root cause");
  });

  test("generates error when incident ID passed to service reader", () => {
    const error = generateIdMismatchError("Q0RIJJZL24RC6W", "service");
    expect(error).toContain("ID format mismatch");
    expect(error).toContain("INCIDENT ID");
    expect(error).toContain("pagerduty-incident-reader");
  });

  test("generates error for unknown ID format", () => {
    const error = generateIdMismatchError("???", "incident");
    expect(error).toContain("Unrecognized ID format");
  });

  test("includes context in suggestion", () => {
    const error = generateIdMismatchError(
      "PG7CZUT",
      "incident",
      "investigating outage"
    );
    expect(error).toContain("investigating outage");
  });
});

describe("parseSkillInput", () => {
  test("parses ID and context", () => {
    const result = parseSkillInput("Q0RIJJZL24RC6W | investigating root cause");
    expect(result.id).toBe("Q0RIJJZL24RC6W");
    expect(result.context).toBe("investigating root cause");
    expect(result.error).toBeUndefined();
  });

  test("handles ID without context", () => {
    const result = parseSkillInput("Q0RIJJZL24RC6W");
    expect(result.id).toBe("Q0RIJJZL24RC6W");
    expect(result.context).toBe("general information");
  });

  test("handles context with multiple pipes", () => {
    const result = parseSkillInput("PG7CZUT | context | more context");
    expect(result.id).toBe("PG7CZUT");
    // Note: spaces around internal pipes are preserved in original join
    expect(result.context).toContain("context");
    expect(result.context).toContain("more context");
  });

  test("handles whitespace", () => {
    const result = parseSkillInput("  PG7CZUT  |  context  ");
    expect(result.id).toBe("PG7CZUT");
    expect(result.context).toBe("context");
  });

  test("handles empty input", () => {
    const result = parseSkillInput("");
    expect(result.error).toBeDefined();
  });

  test("handles null input", () => {
    const result = parseSkillInput(null);
    expect(result.error).toBeDefined();
  });
});

describe("real-world ID examples", () => {
  // Add real IDs here as you encounter them for regression testing
  const knownServiceIds = [
    "PG7CZUT", // From screenshot - Mathom Guideline Recommendation Production
  ];

  const knownIncidentIds = [
    "Q0RIJJZL24RC6W", // From screenshot - incident #42727
  ];

  test("correctly identifies known service IDs", () => {
    for (const id of knownServiceIds) {
      const result = identifyIdType(id);
      expect(result.type).toBe("service");
      expect(["high", "medium"]).toContain(result.confidence);
    }
  });

  test("correctly identifies known incident IDs", () => {
    for (const id of knownIncidentIds) {
      const result = identifyIdType(id);
      expect(result.type).toBe("incident");
      expect(["high", "medium"]).toContain(result.confidence);
    }
  });
});
