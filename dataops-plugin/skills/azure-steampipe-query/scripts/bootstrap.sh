#!/usr/bin/env bash
set -euo pipefail

# One-time setup for azure-steampipe-query skill
# Creates isolated steampipe environment in ~/.dataops-assistant/steampipe-azure
#
# Usage: ./bootstrap.sh
#
# This downloads the azure plugin and initializes the steampipe
# database with certificates. Run once after cloning the repo.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(dirname "$SCRIPT_DIR")"

# Paths (can be overridden via env vars for testing)
DATAOPS_DIR="${DATAOPS_ASSISTANT_DIR:-$HOME/.dataops-assistant}"
STEAMPIPE_DIR="${DATAOPS_ASSISTANT_AZURE_STEAMPIPE_DIR:-$DATAOPS_DIR/steampipe-azure}"
STEAMPIPE_PORT="${DATAOPS_ASSISTANT_AZURE_STEAMPIPE_PORT:-29193}"

# Config is shipped with the skill (company-wide subscriptions)
SHIPPED_CONFIG_DIR="$SKILL_ROOT/config"

echo "=== Azure Steampipe Query - Bootstrap ==="
echo ""
echo "Steampipe dir: $STEAMPIPE_DIR"
echo "Config source: $SHIPPED_CONFIG_DIR"
echo ""

# Check steampipe CLI is installed
if ! command -v steampipe &> /dev/null; then
    echo "ERROR: steampipe CLI not installed"
    echo "Install from: https://steampipe.io/downloads"
    exit 1
fi

# Check Azure CLI auth
if ! az account show &> /dev/null 2>&1; then
    echo "WARNING: Azure CLI not authenticated"
    echo "Run 'az login' before using the skill"
fi

# Setup directories
mkdir -p "$STEAMPIPE_DIR/config"

# Copy shipped config files
echo "Copying steampipe config..."
cp "$SHIPPED_CONFIG_DIR"/*.spc "$STEAMPIPE_DIR/config/"

# Point steampipe to our isolated install
export STEAMPIPE_INSTALL_DIR="$STEAMPIPE_DIR"

# Check if already bootstrapped
if [[ -d "$STEAMPIPE_DIR/internal" ]] && [[ -d "$STEAMPIPE_DIR/plugins" ]]; then
    echo "Already bootstrapped. To re-bootstrap, run:"
    echo "  rm -rf $STEAMPIPE_DIR/{internal,db,plugins}"
    echo "  ./bootstrap.sh"
    exit 0
fi

echo "Bootstrapping steampipe environment..."
echo ""

# Install azure plugin
echo "Installing Azure plugin..."
steampipe plugin install azure

# Start service to initialize database and SSL certificates
echo ""
echo "Initializing database and certificates..."
steampipe service start --database-listen local --database-port "$STEAMPIPE_PORT"

# Wait for service to be ready
sleep 2

# Stop service (queries will auto-start it as needed)
steampipe service stop

echo ""
echo "=== Bootstrap Complete ==="
echo ""
echo "The skill is ready to use. Test with:"
echo "  ./scripts/steampipe-query.sh \"SELECT display_name FROM azure_company_all.azure_subscription LIMIT 3\""
