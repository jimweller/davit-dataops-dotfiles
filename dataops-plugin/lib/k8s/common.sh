#!/usr/bin/env bash
# Shared functions for k8s skills (k8s-steampipe, k8s-logs, etc.)
#
# Source this file from skill scripts:
#   source "$SCRIPT_DIR/../../../lib/k8s/common.sh"

set -euo pipefail

# --- Paths ---
# Shared k8s configuration lives in ~/.dataops-assistant/k8s/
# Tool-specific configs (steampipe, etc.) live in their own subdirs

K8S_COMMON_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATAOPS_DIR="$HOME/.dataops-assistant"
K8S_DIR="$DATAOPS_DIR/k8s"
KUBECONFIG_PATH="$K8S_DIR/kubeconfig"
USER_CLUSTERS="$K8S_DIR/clusters.yaml"
SHIPPED_REGISTRY="$K8S_COMMON_ROOT/cluster-registry.yaml"

# --- Output helpers ---

# Output JSON error and exit
# Usage: k8s::error "message"
k8s::error() {
    local msg="$1"
    echo "{\"error\": \"$msg\"}" >&2
    exit 1
}

# Output JSON warning (does not exit)
# Usage: k8s::warn "message"
k8s::warn() {
    local msg="$1"
    echo "{\"warning\": \"$msg\"}" >&2
}

# --- Dependency checks ---

# Check if yq is installed
k8s::require_yq() {
    if ! command -v yq &>/dev/null; then
        k8s::error "yq CLI not installed. Install: brew install yq"
    fi
}

# Check if kubectl is installed
k8s::require_kubectl() {
    if ! command -v kubectl &>/dev/null; then
        k8s::error "kubectl not installed. Install: brew install kubectl"
    fi
}

# --- Registry functions ---

# Merge shipped and user registries
# User entries override shipped entries by anchor
# Returns merged YAML on stdout
# Invalid user entries (missing anchor, anchor not in registry) are logged and skipped
k8s::merge_registries() {
    k8s::require_yq

    local shipped="$SHIPPED_REGISTRY"
    local user="$USER_CLUSTERS"

    # Start with shipped registry
    if [[ ! -f "$shipped" ]]; then
        k8s::error "Shipped registry not found: $shipped"
    fi

    # If no user file or empty file, return shipped as-is
    if [[ ! -f "$user" ]] || [[ ! -s "$user" ]]; then
        cat "$shipped"
        return 0
    fi

    # Check if user file has any clusters defined
    local user_cluster_count
    user_cluster_count=$(yq '.clusters | length // 0' "$user" 2>/dev/null || echo "0")
    if [[ "$user_cluster_count" -eq 0 ]]; then
        cat "$shipped"
        return 0
    fi

    # Build lookup of valid anchors from shipped registry
    local valid_anchors
    valid_anchors=$(yq -r '.clusters[].anchor' "$shipped" | tr '\n' '|')

    # Deep merge: user entries are deep-merged with shipped entries by anchor
    # Copy shipped to temp file, then merge each user entry
    local temp_merged="/tmp/k8s-merged-registry-$$.yaml"
    cp "$shipped" "$temp_merged"

    local idx_counter=0
    for idx_counter in $(seq 0 $((user_cluster_count - 1))); do
        local user_entry anchor idx

        # Get the entry
        user_entry=$(yq -o=json ".clusters[$idx_counter]" "$user")
        anchor=$(echo "$user_entry" | yq -p json -r '.anchor // "empty"')

        # Validate: anchor must exist
        if [[ -z "$anchor" ]]; then
            k8s::warn "user config entry $idx_counter: missing 'anchor' field, skipping"
            continue
        fi

        # Validate: anchor must be in shipped registry
        if ! echo "$valid_anchors" | grep -q "|${anchor}|" && ! echo "$valid_anchors" | grep -q "^${anchor}|" && ! echo "$valid_anchors" | grep -q "|${anchor}$"; then
            # More robust check
            if ! yq -e ".clusters[] | select(.anchor == \"$anchor\")" "$shipped" &>/dev/null; then
                k8s::warn "user config '$anchor': not found in cluster registry, skipping"
                continue
            fi
        fi

        # Find index in shipped registry and merge
        idx=$(yq ".clusters | to_entries | .[] | select(.value.anchor == \"$anchor\") | .key" "$temp_merged")
        if [[ -n "$idx" ]]; then
            export USER_ENTRY="$user_entry"
            yq -i ".clusters[$idx] *= env(USER_ENTRY)" "$temp_merged"
            unset USER_ENTRY
        fi
    done

    cat "$temp_merged"
    rm -f "$temp_merged"
}

# List all configured clusters (those with override defined)
# Outputs JSON array with anchor, description, keywords
k8s::list_clusters() {
    k8s::require_yq

    local merged
    merged=$(k8s::merge_registries)

    # Output clusters that have non-empty override (configured)
    echo "$merged" | yq -o=json '
        .clusters |
        map(select(.kubeconfig.override != {} and .kubeconfig.override != null)) |
        map({
            "anchor": .anchor,
            "description": .metadata.description,
            "keywords": .metadata.keywords,
            "provider": .metadata.provider
        })
    '
}

# List all available clusters (regardless of configuration status)
# Outputs JSON array with anchor, description, configured status
k8s::list_all_clusters() {
    k8s::require_yq

    local merged
    merged=$(k8s::merge_registries)

    echo "$merged" | yq -o=json '
        .clusters |
        map({
            "anchor": .anchor,
            "description": .metadata.description,
            "keywords": .metadata.keywords,
            "provider": .metadata.provider,
            "configured": (.kubeconfig.override != {} and .kubeconfig.override != null)
        })
    '
}

# Get a single cluster's config by anchor
# Usage: k8s::get_cluster "dev-usw2"
# Outputs YAML for that cluster
k8s::get_cluster() {
    local anchor="$1"
    k8s::require_yq

    local merged
    merged=$(k8s::merge_registries)

    local cluster
    cluster=$(echo "$merged" | yq ".clusters[] | select(.anchor == \"$anchor\")")

    if [[ -z "$cluster" ]]; then
        return 1
    fi

    echo "$cluster"
}

# --- Validation ---

# Validate cluster exists and is configured
# Usage: k8s::validate_cluster "dev-usw2"
k8s::validate_cluster() {
    local anchor="$1"

    local cluster
    if ! cluster=$(k8s::get_cluster "$anchor"); then
        local available
        available=$(k8s::list_all_clusters | yq -r '.[].anchor' | tr '\n' ', ' | sed 's/,$//')
        k8s::error "Cluster '$anchor' not found. Available: $available"
    fi

    # Check if override is configured
    local override
    override=$(echo "$cluster" | yq '.kubeconfig.override')

    if [[ "$override" == "{}" ]] || [[ "$override" == "null" ]]; then
        k8s::error "Cluster '$anchor' not configured. Add override to $USER_CLUSTERS"
    fi
}

# Check if kubeconfig is bootstrapped
k8s::check_bootstrap() {
    if [[ ! -f "$KUBECONFIG_PATH" ]]; then
        k8s::error "K8s not bootstrapped. Run: $K8S_COMMON_ROOT/scripts/bootstrap.sh"
    fi
}

# --- Initialization ---

# Full initialization for query scripts
# Usage: k8s::init "cluster-anchor"
k8s::init() {
    local cluster="${1:-}"

    if [[ -z "$cluster" ]]; then
        k8s::error "Cluster required. Use 'clusters' command to list available clusters."
    fi

    k8s::check_bootstrap
    k8s::validate_cluster "$cluster"
}
