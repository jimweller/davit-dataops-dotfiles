#!/usr/bin/env bash
set -euo pipefail

# AWS Steampipe Query
#
# Query AWS accounts via Steampipe SQL with explicit account selection.
#
# Usage:
#   aws-steampipe.sh <account> query "SELECT ..."
#   aws-steampipe.sh <account> tables [filter]
#   aws-steampipe.sh <account> describe <table>
#   aws-steampipe.sh accounts              # List configured accounts
#   aws-steampipe.sh accounts --all        # List all accounts (including unconfigured)
#
# Examples:
#   aws-steampipe.sh dss-common-dev tables
#   aws-steampipe.sh dss-common-dev query "SELECT name FROM aws_dss_common_dev.aws_s3_bucket LIMIT 5"
#   aws-steampipe.sh dss-common-dev describe aws_s3_bucket

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(dirname "$SCRIPT_DIR")"

# Paths (can be overridden via env vars for testing)
DATAOPS_DIR="${DATAOPS_ASSISTANT_DIR:-$HOME/.dataops-assistant}"
AWS_DIR="${DATAOPS_ASSISTANT_AWS_DIR:-$DATAOPS_DIR/aws}"
STEAMPIPE_DIR="${DATAOPS_ASSISTANT_AWS_STEAMPIPE_DIR:-$DATAOPS_DIR/steampipe-aws}"
STEAMPIPE_PORT="${DATAOPS_ASSISTANT_AWS_STEAMPIPE_PORT:-29195}"

SHIPPED_REGISTRY="$SKILL_ROOT/config/account-registry.yaml"
USER_CONFIG="$AWS_DIR/accounts.yaml"
SPC_FILE="$STEAMPIPE_DIR/config/aws.spc"

# --- Output helpers ---
error_json() {
    echo "{\"error\": \"$1\"}" >&2
    exit 1
}

# --- Dependency checks ---
require_yq() {
    if ! command -v yq &>/dev/null; then
        error_json "yq CLI not installed. Install: brew install yq"
    fi
}

require_steampipe() {
    if ! command -v steampipe &>/dev/null; then
        error_json "steampipe CLI not installed. Install from https://steampipe.io/downloads"
    fi
}

check_bootstrap() {
    if [[ ! -f "$SPC_FILE" ]]; then
        error_json "Not bootstrapped. Run: $SKILL_ROOT/scripts/bootstrap.sh"
    fi
    if [[ ! -d "$STEAMPIPE_DIR/plugins" ]]; then
        error_json "AWS plugin not installed. Run: $SKILL_ROOT/scripts/bootstrap.sh"
    fi
}

# --- Account listing ---
list_configured_accounts() {
    require_yq
    if [[ ! -f "$USER_CONFIG" ]]; then
        echo "[]"
        return
    fi

    # Get configured accounts with their profiles
    yq -o=json '
        .accounts |
        map(select(.name != null and .profile != null)) |
        map({
            "name": .name,
            "profile": .profile,
            "schema": ("aws_" + (.name | split("-") | join("_")))
        })
    ' "$USER_CONFIG"
}

list_all_accounts() {
    require_yq

    # Get list of configured account names
    local configured_names=""
    if [[ -f "$USER_CONFIG" ]]; then
        configured_names=$(yq -r '.accounts[].name // ""' "$USER_CONFIG" 2>/dev/null | tr '\n' ' ')
    fi

    # Output all accounts with configured status
    yq -o=json '
        .accounts |
        map({
            "name": .name,
            "account_id": .account_id,
            "description": .description,
            "schema": ("aws_" + (.name | split("-") | join("_")))
        })
    ' "$SHIPPED_REGISTRY" | jq --arg configured "$configured_names" '
        map(. as $item | . + {"configured": ($configured | split(" ") | any(. == $item.name))})
    '
}

# --- Validate account ---
validate_account() {
    local account="$1"
    require_yq

    if [[ ! -f "$USER_CONFIG" ]]; then
        error_json "No accounts configured. Create $USER_CONFIG"
    fi

    # Check if account is configured
    local found
    found=$(yq -r ".accounts[] | select(.name == \"$account\") | .name" "$USER_CONFIG" 2>/dev/null || echo "")

    if [[ -z "$found" ]]; then
        local available
        available=$(yq -r '.accounts[].name // ""' "$USER_CONFIG" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
        error_json "Account '$account' not configured. Available: $available"
    fi
}

# --- Ensure service running ---
ensure_service() {
    export STEAMPIPE_INSTALL_DIR="$STEAMPIPE_DIR"

    if ! lsof -i ":$STEAMPIPE_PORT" &>/dev/null; then
        steampipe service start \
            --database-listen local \
            --database-port "$STEAMPIPE_PORT" \
            &>/dev/null
        sleep 2
    fi
}

# --- Parse arguments ---
ACCOUNT="${1:-}"
shift || true
COMMAND="${1:-}"
shift || true

# --- Handle account listing (no account required) ---
if [[ "$ACCOUNT" == "accounts" ]]; then
    if [[ "$COMMAND" == "--all" ]]; then
        list_all_accounts
    else
        list_configured_accounts
    fi
    exit 0
fi

# --- Validate inputs ---
if [[ -z "$ACCOUNT" ]]; then
    cat >&2 << 'USAGE'
{"error": "Usage: aws-steampipe.sh <account> <command> [args...]\n\nCommands:\n  query \"SQL\"      Execute SQL query\n  tables [filter]   List tables\n  describe <table>  Show table columns\n  accounts          List configured accounts\n  accounts --all    List all available accounts"}
USAGE
    exit 1
fi

require_steampipe
check_bootstrap
validate_account "$ACCOUNT"

# --- Set environment ---
export STEAMPIPE_INSTALL_DIR="$STEAMPIPE_DIR"

# Ensure service is running
ensure_service

# Schema name (account with dashes converted to underscores)
SCHEMA="aws_$(echo "$ACCOUNT" | tr '-' '_')"

# --- Execute command ---
case "$COMMAND" in
    query)
        query="${1:-}"
        if [[ -z "$query" ]]; then
            error_json "Usage: aws-steampipe.sh $ACCOUNT query \"SELECT ...\""
        fi
        steampipe query "$query" --output json
        ;;

    tables)
        filter="${1:-}"
        if [[ -n "$filter" ]]; then
            steampipe query "
                SELECT table_name
                FROM information_schema.tables
                WHERE table_schema = '$SCHEMA'
                  AND table_name ILIKE '%${filter}%'
                ORDER BY table_name
            " --output json
        else
            steampipe query "
                SELECT table_name
                FROM information_schema.tables
                WHERE table_schema = '$SCHEMA'
                ORDER BY table_name
            " --output json
        fi
        ;;

    describe)
        table="${1:-}"
        if [[ -z "$table" ]]; then
            error_json "Usage: aws-steampipe.sh $ACCOUNT describe <table_name>"
        fi
        steampipe query "
            SELECT column_name, data_type
            FROM information_schema.columns
            WHERE table_schema = '$SCHEMA'
              AND table_name = '${table}'
            ORDER BY ordinal_position
        " --output json
        ;;

    "")
        error_json "Command required. Use: query, tables, describe, or accounts"
        ;;

    *)
        error_json "Unknown command: $COMMAND. Use: query, tables, describe, or accounts"
        ;;
esac
