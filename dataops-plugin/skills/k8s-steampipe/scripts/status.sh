#!/usr/bin/env bash
set -uo pipefail

# k8s-steampipe status check
# Output: stderr = human-readable, stdout = JSON

SKILL_NAME="k8s-steampipe"
STEAMPIPE_DIR="$HOME/.dataops-assistant/steampipe-k8s"
KUBECONFIG_FILE="$HOME/.dataops-assistant/k8s/kubeconfig"

errors=()
cluster_count=0

# Check steampipe CLI
if ! command -v steampipe &>/dev/null; then
    printf "  ✗ steampipe CLI not installed\n" >&2
    errors+=("steampipe CLI missing")
else
    printf "  ✓ steampipe CLI\n" >&2
fi

# Check kubectl
if ! command -v kubectl &>/dev/null; then
    printf "  ✗ kubectl not installed\n" >&2
    errors+=("kubectl missing")
else
    printf "  ✓ kubectl\n" >&2
fi

# Check yq
if ! command -v yq &>/dev/null; then
    printf "  ✗ yq not installed (brew install yq)\n" >&2
    errors+=("yq missing")
else
    printf "  ✓ yq\n" >&2
fi

# Check bootstrap - kubeconfig
if [[ -f "$KUBECONFIG_FILE" ]]; then
    printf "  ✓ kubeconfig generated\n" >&2
    # Count contexts in kubeconfig
    if command -v yq &>/dev/null; then
        cluster_count=$(yq '.contexts | length' "$KUBECONFIG_FILE" 2>/dev/null || echo "0")
    fi
else
    printf "  ✗ kubeconfig not found (run bootstrap)\n" >&2
    errors+=("kubeconfig missing")
fi

# Check bootstrap - steampipe config
if [[ -f "$STEAMPIPE_DIR/config/kubernetes.spc" ]]; then
    printf "  ✓ steampipe kubernetes config\n" >&2
else
    printf "  ✗ steampipe config not found (run bootstrap)\n" >&2
    errors+=("steampipe config missing")
fi

# Output JSON
if [[ ${#errors[@]} -eq 0 ]]; then
    jq -n --arg name "$SKILL_NAME" --arg details "ready, $cluster_count clusters" \
        '{"available": true, "name": $name, "details": $details}'
else
    details=$(IFS=', '; echo "${errors[*]}")
    jq -n --arg name "$SKILL_NAME" --arg details "$details" \
        '{"available": false, "name": $name, "details": $details}'
fi
