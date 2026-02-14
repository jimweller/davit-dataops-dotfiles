#!/usr/bin/env bash
# Steampipe-specific k8s functions
#
# Extends the shared k8s-common with steampipe service management

set -euo pipefail

# Source shared k8s functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../lib/k8s/common.sh"

# --- Steampipe-specific paths ---
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STEAMPIPE_DIR="${DATAOPS_ASSISTANT_K8S_STEAMPIPE_DIR:-$DATAOPS_DIR/steampipe-k8s}"
STEAMPIPE_PORT="${DATAOPS_ASSISTANT_K8S_STEAMPIPE_PORT:-29194}"

# --- Steampipe dependency check ---
k8s::require_steampipe() {
    if ! command -v steampipe &>/dev/null; then
        k8s::error "steampipe CLI not installed. Install from https://steampipe.io/downloads"
    fi
}

# --- Steampipe service management ---

# Ensure steampipe service is running
k8s::ensure_service() {
    k8s::require_steampipe

    # Set environment for isolated steampipe
    export STEAMPIPE_INSTALL_DIR="$STEAMPIPE_DIR"
    export KUBECONFIG="$KUBECONFIG_PATH"

    # Check if service is already running on our port
    if ! lsof -i ":$STEAMPIPE_PORT" &>/dev/null; then
        steampipe service start \
            --database-listen local \
            --database-port "$STEAMPIPE_PORT" \
            &>/dev/null
        sleep 2
    fi
}

# Check if steampipe is bootstrapped
k8s::check_steampipe_bootstrap() {
    k8s::check_bootstrap  # Check shared kubeconfig first

    if [[ ! -d "$STEAMPIPE_DIR/config" ]]; then
        k8s::error "Steampipe config missing. Run: $SKILL_ROOT/scripts/bootstrap.sh"
    fi
}

# Override init to check steampipe bootstrap too
k8s::init() {
    local cluster="${1:-}"

    if [[ -z "$cluster" ]]; then
        k8s::error "Cluster required. Use 'clusters' command to list available clusters."
    fi

    k8s::check_steampipe_bootstrap
    k8s::validate_cluster "$cluster"
}
