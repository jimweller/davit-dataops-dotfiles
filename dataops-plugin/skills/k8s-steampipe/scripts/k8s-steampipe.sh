#!/usr/bin/env bash
set -euo pipefail

# K8s Steampipe - Main entry point
#
# Query Kubernetes clusters via Steampipe SQL.
# Requires explicit cluster selection (no aggregator).
#
# Usage:
#   k8s-steampipe.sh <cluster> query "SELECT ..."
#   k8s-steampipe.sh <cluster> tables [filter]
#   k8s-steampipe.sh <cluster> describe <table>
#   k8s-steampipe.sh clusters              # List available clusters
#   k8s-steampipe.sh clusters --all        # List all clusters (including unconfigured)
#
# Examples:
#   k8s-steampipe.sh dss-eks-platform-dev tables
#   k8s-steampipe.sh dss-eks-platform-dev query "SELECT name, namespace FROM k8s_dss_eks_platform_dev.kubernetes_pod LIMIT 5"
#   k8s-steampipe.sh dss-eks-platform-dev describe kubernetes_pod

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/k8s-common.sh"

# --- Parse arguments ---
CLUSTER="${1:-}"
shift || true
COMMAND="${1:-}"
shift || true

# --- Handle cluster listing (no cluster required) ---
if [[ "$CLUSTER" == "clusters" ]]; then
    if [[ "$COMMAND" == "--all" ]]; then
        k8s::list_all_clusters
    else
        k8s::list_clusters
    fi
    exit 0
fi

# --- Validate cluster ---
if [[ -z "$CLUSTER" ]]; then
    echo '{"error": "Usage: k8s-steampipe.sh <cluster> <command> [args...]\n\nCommands:\n  query \"SQL\"     Execute SQL query\n  tables [filter]  List tables\n  describe <table> Show table columns\n  clusters         List available clusters"}' >&2
    exit 1
fi

# Initialize (validates cluster and checks bootstrap)
k8s::init "$CLUSTER"

# --- Set environment ---
export STEAMPIPE_INSTALL_DIR="$STEAMPIPE_DIR"
export KUBECONFIG="$KUBECONFIG_PATH"

# Ensure service is running
k8s::ensure_service

# Schema name (anchor with dashes converted to underscores)
SCHEMA="k8s_$(echo "$CLUSTER" | tr '-' '_')"

# --- Execute command ---
case "$COMMAND" in
    query)
        query="${1:-}"
        if [[ -z "$query" ]]; then
            k8s::error "Usage: k8s-steampipe.sh $CLUSTER query \"SELECT ...\""
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
            k8s::error "Usage: k8s-steampipe.sh $CLUSTER describe <table_name>"
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
        k8s::error "Command required. Use: query, tables, describe, or clusters"
        ;;

    *)
        k8s::error "Unknown command: $COMMAND. Use: query, tables, describe, or clusters"
        ;;
esac
