#!/usr/bin/env bash
set -euo pipefail

# k8s-logs - Fetch pod logs from configured clusters
#
# Usage:
#   k8s-logs.sh <cluster> <namespace> <pod-query> [options]
#   k8s-logs.sh clusters                    # List configured clusters
#   k8s-logs.sh <cluster> namespaces        # List namespaces
#   k8s-logs.sh <cluster> pods <namespace>  # List pods in namespace
#
# Options:
#   --since <duration>    Show logs since (e.g., 5m, 1h, 30s). Default: 5m
#   --tail <lines>        Number of lines to tail. Default: 100
#   --container <name>    Container name (if pod has multiple)
#   --timestamps          Include timestamps
#   --previous            Show logs from previous container instance
#
# Examples:
#   k8s-logs.sh datascience-primary-cluster flyte "workflow-*"
#   k8s-logs.sh dss-eks-platform-dev kube-system "coredns-*" --since 10m
#   k8s-logs.sh mathom-primary-cluster default my-pod --tail 50

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../lib/k8s/common.sh"

# --- Check stern is installed ---
k8s::require_stern() {
    if ! command -v stern &>/dev/null; then
        k8s::error "stern CLI not installed. Install: brew install stern"
    fi
}

# --- Commands ---

show_usage() {
    cat << 'EOF'
Usage:
  k8s-logs.sh <cluster> <namespace> <pod-query> [options]
  k8s-logs.sh clusters                    # List configured clusters
  k8s-logs.sh <cluster> namespaces        # List namespaces
  k8s-logs.sh <cluster> pods <namespace>  # List pods in namespace

Options:
  --since <duration>    Show logs since (e.g., 5m, 1h, 30s). Default: 5m
  --tail <lines>        Number of lines to tail. Default: 100
  --container <name>    Container name (if pod has multiple)
  --timestamps          Include timestamps
  --previous            Show logs from previous container instance

Examples:
  k8s-logs.sh datascience-primary-cluster flyte "workflow-*"
  k8s-logs.sh dss-eks-platform-dev kube-system "coredns-*" --since 10m
EOF
}

list_clusters() {
    k8s::list_clusters
}

list_namespaces() {
    local cluster="$1"
    k8s::init "$cluster"

    export KUBECONFIG="$KUBECONFIG_PATH"
    kubectl --context "$cluster" get namespaces -o json | \
        jq '[.items[].metadata.name]'
}

list_pods() {
    local cluster="$1"
    local namespace="$2"
    k8s::init "$cluster"

    export KUBECONFIG="$KUBECONFIG_PATH"
    kubectl --context "$cluster" -n "$namespace" get pods -o json | \
        jq '[.items[] | {name: .metadata.name, status: .status.phase, containers: [.spec.containers[].name]}]'
}

fetch_logs() {
    local cluster="$1"
    local namespace="$2"
    local pod_query="$3"
    shift 3

    k8s::init "$cluster"
    k8s::require_stern

    # Parse options
    local since="5m"
    local tail="100"
    local container=""
    local timestamps=""
    local previous=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --since)
                since="$2"
                shift 2
                ;;
            --tail)
                tail="$2"
                shift 2
                ;;
            --container)
                container="$2"
                shift 2
                ;;
            --timestamps)
                timestamps="--timestamps"
                shift
                ;;
            --previous)
                previous="--previous"
                shift
                ;;
            *)
                k8s::error "Unknown option: $1"
                ;;
        esac
    done

    # Build stern command
    local stern_cmd=(
        stern
        --kubeconfig "$KUBECONFIG_PATH"
        --context "$cluster"
        --namespace "$namespace"
        --since "$since"
        --tail "$tail"
        --no-follow
        --output raw
    )

    [[ -n "$container" ]] && stern_cmd+=(--container "$container")
    [[ -n "$timestamps" ]] && stern_cmd+=($timestamps)
    [[ -n "$previous" ]] && stern_cmd+=($previous)

    stern_cmd+=("$pod_query")

    # Run stern
    "${stern_cmd[@]}" 2>/dev/null
}

# --- Main ---

if [[ $# -lt 1 ]]; then
    show_usage
    exit 1
fi

case "$1" in
    clusters)
        list_clusters
        ;;
    -h|--help|help)
        show_usage
        ;;
    *)
        cluster="$1"
        shift

        if [[ $# -lt 1 ]]; then
            k8s::error "Missing command. Use: namespaces, pods <ns>, or <namespace> <pod-query>"
        fi

        case "$1" in
            namespaces)
                list_namespaces "$cluster"
                ;;
            pods)
                if [[ $# -lt 2 ]]; then
                    k8s::error "Missing namespace. Usage: k8s-logs.sh <cluster> pods <namespace>"
                fi
                list_pods "$cluster" "$2"
                ;;
            *)
                # Assume: <namespace> <pod-query> [options]
                if [[ $# -lt 2 ]]; then
                    k8s::error "Missing pod query. Usage: k8s-logs.sh <cluster> <namespace> <pod-query>"
                fi
                fetch_logs "$cluster" "$@"
                ;;
        esac
        ;;
esac
