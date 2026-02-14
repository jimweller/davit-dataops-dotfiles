#!/usr/bin/env bash
# ado-service-endpoint.sh - Get service connection details
# Usage: ado-service-endpoint.sh <project> <endpoint-id>
# Output: JSON with full endpoint properties (credentials masked)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ado-common.sh"

ado::init

project="${1:-}"
endpoint_id="${2:-}"

if [[ -z "$project" ]] || [[ -z "$endpoint_id" ]]; then
    ado::error "Usage: ado-service-endpoint.sh <project> <endpoint-id>"
fi

# Get endpoint details
result=$(az devops service-endpoint show --organization "$AZURE_DEVOPS_ORG" --project "$project" --id "$endpoint_id" --output json 2>/dev/null) || ado::error "Service endpoint '$endpoint_id' not found in project '$project'"

# Mask any sensitive fields that might be present
# authorization.parameters may contain secrets
echo "$result" | jq '
    if .authorization.parameters then
        .authorization.parameters = (.authorization.parameters | to_entries | map(
            if (.key | test("password|secret|key|token"; "i")) then
                .value = "***MASKED***"
            else
                .
            end
        ) | from_entries)
    else
        .
    end |
    {
        id,
        name,
        type,
        url,
        description,
        isShared,
        isReady,
        owner: .owner,
        createdBy: .createdBy.displayName,
        authorization: {
            scheme: .authorization.scheme,
            parameters: .authorization.parameters
        },
        serviceEndpointProjectReferences: [.serviceEndpointProjectReferences[]? | {
            projectReference: .projectReference.name,
            name
        }]
    }
'
