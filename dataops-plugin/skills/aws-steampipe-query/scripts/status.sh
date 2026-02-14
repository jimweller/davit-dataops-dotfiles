#!/usr/bin/env bash
set -uo pipefail

# aws-steampipe-query status check
# Output: stderr = human-readable, stdout = JSON

SKILL_NAME="aws-steampipe-query"
STEAMPIPE_DIR="$HOME/.dataops-assistant/steampipe-aws"
ACCOUNTS_FILE="$HOME/.dataops-assistant/aws/accounts.yaml"

errors=()
account_count=0

# Check steampipe CLI
if ! command -v steampipe &>/dev/null; then
    printf "  ✗ steampipe CLI not installed\n" >&2
    errors+=("steampipe CLI missing")
else
    printf "  ✓ steampipe CLI\n" >&2
fi

# Check aws CLI
if ! command -v aws &>/dev/null; then
    printf "  ✗ aws CLI not installed\n" >&2
    errors+=("aws CLI missing")
else
    printf "  ✓ aws CLI\n" >&2
fi

# Check yq
if ! command -v yq &>/dev/null; then
    printf "  ✗ yq not installed (brew install yq)\n" >&2
    errors+=("yq missing")
else
    printf "  ✓ yq\n" >&2
fi

# Check accounts config
if [[ -f "$ACCOUNTS_FILE" ]]; then
    printf "  ✓ accounts.yaml found\n" >&2
    if command -v yq &>/dev/null; then
        account_count=$(yq '.accounts | length' "$ACCOUNTS_FILE" 2>/dev/null || echo "0")
    fi
else
    printf "  ✗ accounts.yaml not found (~/.dataops-assistant/aws/accounts.yaml)\n" >&2
    errors+=("accounts.yaml missing")
fi

# Check bootstrap - steampipe config
if [[ -f "$STEAMPIPE_DIR/config/aws.spc" ]]; then
    printf "  ✓ steampipe aws config\n" >&2
else
    printf "  ✗ steampipe config not found (run bootstrap)\n" >&2
    errors+=("steampipe config missing")
fi

# Output JSON
if [[ ${#errors[@]} -eq 0 ]]; then
    jq -n --arg name "$SKILL_NAME" --arg details "ready, $account_count accounts" \
        '{"available": true, "name": $name, "details": $details}'
else
    details=$(IFS=', '; echo "${errors[*]}")
    jq -n --arg name "$SKILL_NAME" --arg details "$details" \
        '{"available": false, "name": $name, "details": $details}'
fi
