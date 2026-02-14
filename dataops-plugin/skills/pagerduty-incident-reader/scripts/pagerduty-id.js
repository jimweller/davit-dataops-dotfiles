#!/usr/bin/env bun
/**
 * PagerDuty ID format detection and validation utilities.
 * Used by pagerduty-incident-reader and pagerduty-service-reader skills.
 *
 * PagerDuty ID patterns (observed):
 * - Service IDs: ~7 chars, uppercase alphanumeric, often start with P (e.g., PG7CZUT, PABC123)
 * - Incident IDs: ~14 chars, uppercase alphanumeric, often start with Q (e.g., Q0RIJJZL24RC6W)
 *
 * These patterns are heuristic - the API is the source of truth.
 */

/**
 * Identifies the likely type of a PagerDuty ID based on format heuristics.
 * @param {string} id - The PagerDuty ID to analyze
 * @returns {{type: 'service'|'incident'|'unknown', confidence: 'high'|'medium'|'low', reason: string}}
 */
export function identifyIdType(id) {
  if (!id || typeof id !== "string") {
    return { type: "unknown", confidence: "low", reason: "Invalid or empty ID" };
  }

  const trimmed = id.trim().toUpperCase();

  // Check for obviously invalid IDs
  if (!/^[A-Z0-9]+$/.test(trimmed)) {
    return {
      type: "unknown",
      confidence: "low",
      reason: `ID contains invalid characters: "${id}"`,
    };
  }

  const len = trimmed.length;
  const startsWithP = trimmed.startsWith("P");
  const startsWithQ = trimmed.startsWith("Q");

  // Short IDs (5-8 chars) that start with P are likely services
  if (len >= 5 && len <= 8 && startsWithP) {
    return {
      type: "service",
      confidence: "high",
      reason: `Short ID (${len} chars) starting with P matches service pattern`,
    };
  }

  // Long IDs (12-16 chars) that start with Q are likely incidents
  if (len >= 12 && len <= 16 && startsWithQ) {
    return {
      type: "incident",
      confidence: "high",
      reason: `Long ID (${len} chars) starting with Q matches incident pattern`,
    };
  }

  // Short IDs without P prefix - likely service but less confident
  if (len >= 5 && len <= 8) {
    return {
      type: "service",
      confidence: "medium",
      reason: `Short ID (${len} chars) likely a service, but doesn't start with P`,
    };
  }

  // Long IDs without Q prefix - likely incident but less confident
  if (len >= 12 && len <= 16) {
    return {
      type: "incident",
      confidence: "medium",
      reason: `Long ID (${len} chars) likely an incident, but doesn't start with Q`,
    };
  }

  // Ambiguous length (9-11 chars) - could be either
  if (len >= 9 && len <= 11) {
    if (startsWithP) {
      return {
        type: "service",
        confidence: "low",
        reason: `Medium-length ID (${len} chars) starting with P - could be service`,
      };
    }
    if (startsWithQ) {
      return {
        type: "incident",
        confidence: "low",
        reason: `Medium-length ID (${len} chars) starting with Q - could be incident`,
      };
    }
    return {
      type: "unknown",
      confidence: "low",
      reason: `Ambiguous ID length (${len} chars) - could be service or incident`,
    };
  }

  // Very short or very long - unknown
  return {
    type: "unknown",
    confidence: "low",
    reason: `Unusual ID length (${len} chars) - doesn't match known patterns`,
  };
}

/**
 * Checks if an ID looks like a service ID.
 * @param {string} id
 * @returns {boolean}
 */
export function looksLikeServiceId(id) {
  const result = identifyIdType(id);
  return result.type === "service";
}

/**
 * Checks if an ID looks like an incident ID.
 * @param {string} id
 * @returns {boolean}
 */
export function looksLikeIncidentId(id) {
  const result = identifyIdType(id);
  return result.type === "incident";
}

/**
 * Generates an error message suggesting the correct skill when wrong ID type is detected.
 * @param {string} id - The ID that was provided
 * @param {'incident'|'service'} expectedType - What type of ID was expected
 * @param {string} researchContext - The research context provided by the user
 * @returns {string} Error message with guidance
 */
export function generateIdMismatchError(id, expectedType, researchContext = "") {
  const detected = identifyIdType(id);

  if (detected.type === "unknown") {
    return `ERROR: Unrecognized ID format

The ID "${id}" doesn't match known PagerDuty ID patterns.
- Service IDs: ~7 chars, start with P (e.g., PG7CZUT)
- Incident IDs: ~14 chars, start with Q (e.g., Q0RIJJZL24RC6W)

Please verify the ID is correct.`;
  }

  if (detected.type === expectedType) {
    return ""; // No error - ID matches expected type
  }

  const contextSuffix = researchContext ? ` | ${researchContext}` : "";

  if (expectedType === "incident" && detected.type === "service") {
    return `ERROR: ID format mismatch

The ID "${id}" appears to be a SERVICE ID, not an incident ID.
- Service IDs: ~7 chars, start with P (e.g., PG7CZUT)
- Incident IDs: longer, often start with Q (e.g., Q0RIJJZL24RC6W)

To read service details, use:
/dataops-assistant:pagerduty-service-reader ${id}${contextSuffix}

To find incidents for this service, use:
pagerduty-advisor agent with "incidents for service ${id}"`;
  }

  if (expectedType === "service" && detected.type === "incident") {
    return `ERROR: ID format mismatch

The ID "${id}" appears to be an INCIDENT ID, not a service ID.
- Service IDs: ~7 chars, start with P (e.g., PG7CZUT)
- Incident IDs: longer, often start with Q (e.g., Q0RIJJZL24RC6W)

To read incident details, use:
/dataops-assistant:pagerduty-incident-reader ${id}${contextSuffix}`;
  }

  return "";
}

/**
 * Parses skill input in the format: {id} | {research context}
 * @param {string} input - Raw input string
 * @returns {{id: string, context: string, error?: string}}
 */
export function parseSkillInput(input) {
  if (!input || typeof input !== "string") {
    return { id: "", context: "", error: "No input provided" };
  }

  const parts = input.split("|").map((p) => p.trim());

  if (parts.length < 1 || !parts[0]) {
    return { id: "", context: "", error: "No ID provided in input" };
  }

  return {
    id: parts[0],
    context: parts.slice(1).join("|").trim() || "general information",
  };
}
