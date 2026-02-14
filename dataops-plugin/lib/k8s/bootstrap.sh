#!/usr/bin/env bash
set -euo pipefail

# Bootstrap shared Kubernetes configuration
#
# This script:
# 1. Merges shipped cluster-registry.yaml with user's clusters.yaml
# 2. For each configured cluster (has override), runs obtain → applies override
# 3. Produces a multi-context kubeconfig at ~/.dataops-assistant/k8s/kubeconfig
#
# Usage: ./bootstrap.sh
#
# Prerequisites:
# - yq CLI installed (brew install yq)
# - kubectl installed
# - aws-vault and/or kubelogin configured for auth (depending on cluster type)
#
# User overrides (for EKS aws-vault profiles) go in:
#   ~/.dataops-assistant/k8s/clusters.yaml

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo "=== K8s Bootstrap ==="
echo "Kubeconfig: $KUBECONFIG_PATH"
echo ""

# --- Dependency checks ---
k8s::require_yq
k8s::require_kubectl

# --- Merge registries ---
echo "Merging cluster registries..."
merged=$(k8s::merge_registries)

# --- Setup directories ---
mkdir -p "$K8S_DIR"

# --- Initialize empty kubeconfig ---
echo "apiVersion: v1
kind: Config
clusters: []
contexts: []
users: []
current-context: \"\"" > "$KUBECONFIG_PATH"

# --- Process each cluster ---
echo ""
echo "Processing clusters..."
echo ""

configured_count=0
skipped_count=0
failed_count=0

# Get list of anchors
anchors=$(echo "$merged" | yq -r '.clusters[].anchor')

for anchor in $anchors; do
    cluster=$(echo "$merged" | yq ".clusters[] | select(.anchor == \"$anchor\")")

    # Get override config
    override=$(echo "$cluster" | yq '.kubeconfig.override')

    # Skip if no override configured
    if [[ "$override" == "{}" ]] || [[ "$override" == "null" ]] || [[ -z "$override" ]]; then
        echo "  skip $anchor (no override configured)"
        ((skipped_count++))
        continue
    fi

    # Validate override structure: must have users[0].name
    override_user_name=$(echo "$cluster" | yq -r '.kubeconfig.override.users[0].name // "empty"')
    if [[ -z "$override_user_name" ]] || [[ "$override_user_name" == "empty" ]]; then
        echo "  skip $anchor (override missing users[0].name)"
        ((skipped_count++))
        continue
    fi

    # Validate obtain command exists
    obtain_cmd=$(echo "$cluster" | yq -o=json '.kubeconfig.obtain')
    if [[ "$obtain_cmd" == "null" ]] || [[ "$obtain_cmd" == "[]" ]]; then
        echo "  skip $anchor (missing obtain command)"
        ((skipped_count++))
        continue
    fi

    echo "  conf $anchor"

    # Temp file for this cluster's kubeconfig
    temp_kubeconfig="/tmp/k8s-bootstrap-$anchor.yaml"

    # Run obtain command - it outputs kubeconfig YAML to stdout
    echo "       -> running obtain..."
    obtain_cmd_str=$(echo "$obtain_cmd" | yq -r 'join(" ")')

    # Run obtain, capture stdout only (stderr goes to console for visibility)
    if ! eval "$obtain_cmd_str" > "$temp_kubeconfig" 2>/dev/null; then
        echo "       -> ERROR: obtain command failed"
        rm -f "$temp_kubeconfig"
        ((failed_count++))
        continue
    fi

    # Verify the obtain command produced valid kubeconfig
    if ! yq '.clusters | length' "$temp_kubeconfig" &>/dev/null; then
        echo "       -> ERROR: obtain did not produce valid YAML"
        rm -f "$temp_kubeconfig"
        ((failed_count++))
        continue
    fi

    cluster_count=$(yq '.clusters | length' "$temp_kubeconfig")
    if [[ "$cluster_count" -eq 0 ]]; then
        echo "       -> ERROR: obtain produced empty kubeconfig"
        rm -f "$temp_kubeconfig"
        ((failed_count++))
        continue
    fi

    # Apply override (merge into temp kubeconfig)
    echo "       -> applying override..."

    # Get the user override
    user_override=$(echo "$cluster" | yq '.kubeconfig.override.users[0]')

    if [[ -n "$user_override" ]] && [[ "$user_override" != "null" ]]; then
        # Get the user name from override
        export OVERRIDE_USER_NAME=$(echo "$user_override" | yq '.name')

        # Write the override user config to a temp file
        override_file="/tmp/k8s-override-$anchor.yaml"
        echo "$user_override" | yq '.user' > "$override_file"

        # Find matching user in temp kubeconfig and replace user config
        yq -i '(.users[] | select(.name == strenv(OVERRIDE_USER_NAME))).user = load("'"$override_file"'")' "$temp_kubeconfig"

        rm -f "$override_file"
        unset OVERRIDE_USER_NAME
    fi

    # Rename context to match anchor (EKS uses full ARN, we want short anchor name)
    echo "       -> renaming context to '$anchor'..."
    kubectl --kubeconfig "$temp_kubeconfig" config rename-context \
        "$(kubectl --kubeconfig "$temp_kubeconfig" config current-context)" \
        "$anchor" 2>/dev/null || true

    # Merge into main kubeconfig
    echo "       -> merging..."
    KUBECONFIG="$KUBECONFIG_PATH:$temp_kubeconfig" kubectl config view --flatten > /tmp/k8s-merged.yaml
    mv /tmp/k8s-merged.yaml "$KUBECONFIG_PATH"

    # Cleanup
    rm -f "$temp_kubeconfig"

    ((configured_count++))
    echo "       -> done"
done

echo ""
echo "Cluster summary: $configured_count configured, $skipped_count skipped, $failed_count failed"

if [[ $configured_count -eq 0 ]]; then
    echo ""
    echo "WARNING: No clusters configured."
    echo ""
    echo "For EKS clusters, add aws-vault overrides to: $USER_CLUSTERS"
    echo "AKS clusters are pre-configured (kubelogin with azurecli)."
    echo ""
    echo "Example $USER_CLUSTERS:"
    cat << 'EXAMPLE'
clusters:
  - anchor: dss-eks-platform-dev
    kubeconfig:
      override:
        users:
          - name: dss-eks-platform-dev
            user:
              exec:
                apiVersion: client.authentication.k8s.io/v1
                command: aws-vault
                args: [exec, your_profile, --, aws, eks, get-token, --region, us-west-2, --cluster-name, dss-eks-platform-dev]
EXAMPLE
    exit 1
fi

# --- Summary ---
echo ""
echo "=== Bootstrap Complete ==="
echo ""
echo "Kubeconfig: $KUBECONFIG_PATH"
echo "Contexts:"
kubectl --kubeconfig "$KUBECONFIG_PATH" config get-contexts -o name | sed 's/^/  - /'
echo ""
echo "Use with kubectl:"
echo "  KUBECONFIG=$KUBECONFIG_PATH kubectl --context <cluster> get pods"
echo ""
echo "Use with stern:"
echo "  KUBECONFIG=$KUBECONFIG_PATH stern --context <cluster> -n <namespace> <pod-query>"
