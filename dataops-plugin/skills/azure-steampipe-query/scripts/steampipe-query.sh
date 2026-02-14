#!/usr/bin/env bash
set -euo pipefail

# Azure Steampipe Query Proxy
# Uses skill-embedded config for portable, predictable schema names
# Runs on port 29193 (configurable via DATAOPS_ASSISTANT_AZURE_STEAMPIPE_PORT)
#
# Usage: steampipe-query.sh "<SQL query>"
# Usage: steampipe-query.sh tables [filter]
# Usage: steampipe-query.sh describe <table_name>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(dirname "$SCRIPT_DIR")"

# Paths (can be overridden via env vars for testing)
DATAOPS_DIR="${DATAOPS_ASSISTANT_DIR:-$HOME/.dataops-assistant}"
STEAMPIPE_DIR="${DATAOPS_ASSISTANT_AZURE_STEAMPIPE_DIR:-$DATAOPS_DIR/steampipe-azure}"
STEAMPIPE_PORT="${DATAOPS_ASSISTANT_AZURE_STEAMPIPE_PORT:-29193}"

# Point steampipe to our isolated install
export STEAMPIPE_INSTALL_DIR="$STEAMPIPE_DIR"

# Verify bootstrapped
if [[ ! -d "$STEAMPIPE_DIR/internal" ]] || [[ ! -d "$STEAMPIPE_DIR/plugins" ]]; then
    echo '{"error": "Skill not bootstrapped. Run: ./skills/azure-steampipe-query/scripts/bootstrap.sh"}' >&2
    exit 1
fi

# Check steampipe is installed
if ! command -v steampipe &> /dev/null; then
    echo '{"error": "steampipe CLI not installed. Install from https://steampipe.io/downloads"}' >&2
    exit 1
fi

# Check Azure CLI auth (steampipe azure plugin uses az login credentials)
if ! az account show &> /dev/null 2>&1; then
    echo '{"error": "Azure CLI not authenticated. Run: az login"}' >&2
    exit 1
fi

# Ensure our isolated steampipe service is running on custom port
if ! lsof -i ":$STEAMPIPE_PORT" &>/dev/null; then
    steampipe service start --database-listen local --database-port "$STEAMPIPE_PORT" &>/dev/null
    sleep 2
fi

command="${1:-}"

case "$command" in
    tables)
        # List available tables, optionally filtered
        filter="${2:-}"
        if [[ -n "$filter" ]]; then
            steampipe query "SELECT table_name FROM information_schema.tables WHERE table_schema = 'azure_company_all' AND table_name ILIKE '%${filter}%' ORDER BY table_name" --output json
        else
            steampipe query "SELECT table_name FROM information_schema.tables WHERE table_schema = 'azure_company_all' ORDER BY table_name" --output json
        fi
        ;;
    describe)
        # Describe a table's columns
        table="${2:-}"
        if [[ -z "$table" ]]; then
            echo '{"error": "Usage: steampipe-query.sh describe <table_name>"}' >&2
            exit 1
        fi
        steampipe query "SELECT column_name, data_type FROM information_schema.columns WHERE table_schema = 'azure_company_all' AND table_name = '${table}' ORDER BY ordinal_position" --output json
        ;;
    *)
        # Execute SQL query
        if [[ -z "$command" ]]; then
            echo '{"error": "Usage: steampipe-query.sh \"<SQL query>\""}' >&2
            exit 1
        fi
        steampipe query "$command" --output json
        ;;
esac
