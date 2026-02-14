#!/usr/bin/env bash
set -euo pipefail

# E2E Test for k8s-steampipe skill
#
# Runs in an isolated environment:
#   - Random port (29200-29299) to avoid conflicts
#   - Temp directory for steampipe install
#   - Uses real user k8s/clusters.yaml (required for auth)
#
# Tests:
#   1. Bootstrap with isolated steampipe dir
#   2. Query EKS cluster (if configured)
#   3. Query AKS cluster (if configured)
#   4. Cleanup
#
# Usage:
#   ./scripts/e2e-test.sh           # Run all tests
#   ./scripts/e2e-test.sh --keep    # Keep temp dir for debugging

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Configuration ---
KEEP_TEMP=false
[[ "${1:-}" == "--keep" ]] && KEEP_TEMP=true

# Random port in range 29200-29299
RANDOM_PORT=$((29200 + RANDOM % 100))

# Isolated steampipe directory
TEMP_DIR=$(mktemp -d)
TEST_STEAMPIPE_DIR="$TEMP_DIR/steampipe-k8s"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# --- Helpers ---
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_test() { echo -e "${GREEN}[TEST]${NC} $1"; }

cleanup() {
    local exit_code=$?
    log_info "Cleaning up..."

    # Stop steampipe service if running
    if [[ -d "$TEST_STEAMPIPE_DIR" ]]; then
        export STEAMPIPE_INSTALL_DIR="$TEST_STEAMPIPE_DIR"
        steampipe service stop &>/dev/null || true
    fi

    if $KEEP_TEMP; then
        log_info "Keeping temp dir for debugging: $TEMP_DIR"
    else
        rm -rf "$TEMP_DIR"
        log_info "Removed temp dir: $TEMP_DIR"
    fi

    exit $exit_code
}
trap cleanup EXIT

# --- Preflight checks ---
log_info "=== K8s Steampipe E2E Test ==="
log_info "Temp dir: $TEMP_DIR"
log_info "Port: $RANDOM_PORT"
log_info "Steampipe dir: $TEST_STEAMPIPE_DIR"

# Check required tools
for tool in steampipe yq kubectl; do
    if ! command -v "$tool" &>/dev/null; then
        log_error "$tool not installed"
        exit 1
    fi
done
log_info "Required tools: OK"

# Check user config exists
USER_CONFIG="$HOME/.dataops-assistant/k8s/clusters.yaml"
if [[ ! -f "$USER_CONFIG" ]]; then
    log_error "User config not found: $USER_CONFIG"
    log_error "Create config with cluster overrides first"
    exit 1
fi
log_info "User config: OK"

# --- Set isolated environment ---
export DATAOPS_ASSISTANT_K8S_STEAMPIPE_DIR="$TEST_STEAMPIPE_DIR"
export DATAOPS_ASSISTANT_K8S_STEAMPIPE_PORT="$RANDOM_PORT"

# --- Test 1: Bootstrap ---
log_test "1. Bootstrap in isolated directory"

"$SKILL_ROOT/scripts/bootstrap.sh"

# Kubeconfig is now in shared location
SHARED_KUBECONFIG="$HOME/.dataops-assistant/k8s/kubeconfig"
if [[ ! -f "$SHARED_KUBECONFIG" ]]; then
    log_error "Bootstrap failed: kubeconfig not created at $SHARED_KUBECONFIG"
    exit 1
fi

if [[ ! -f "$TEST_STEAMPIPE_DIR/config/kubernetes.spc" ]]; then
    log_error "Bootstrap failed: steampipe config not created"
    exit 1
fi

log_info "Bootstrap: OK"

# --- Get configured clusters ---
log_test "2. List configured clusters"

clusters_json=$("$SKILL_ROOT/scripts/k8s-steampipe.sh" clusters)
cluster_count=$(echo "$clusters_json" | jq 'length')

log_info "Found $cluster_count configured cluster(s)"

if [[ "$cluster_count" -eq 0 ]]; then
    log_error "No clusters configured. Add overrides to $USER_CONFIG"
    exit 1
fi

# --- Test each configured cluster ---
test_cluster() {
    local anchor="$1"
    local schema="k8s_$(echo "$anchor" | tr '-' '_')"

    log_test "Testing cluster: $anchor"

    # Test tables command
    log_info "  - tables command..."
    tables_json=$("$SKILL_ROOT/scripts/k8s-steampipe.sh" "$anchor" tables 2>/dev/null || echo '{"rows":[]}')
    table_count=$(echo "$tables_json" | jq '.rows | length')

    if [[ "$table_count" -eq 0 ]]; then
        log_warn "  No tables found (cluster may not be accessible)"
        return 1
    fi
    log_info "    Found $table_count tables"

    # Test query - namespace list
    log_info "  - query namespaces..."
    ns_json=$("$SKILL_ROOT/scripts/k8s-steampipe.sh" "$anchor" query \
        "SELECT name FROM ${schema}.kubernetes_namespace LIMIT 5" 2>/dev/null || echo '{"rows":[]}')
    ns_count=$(echo "$ns_json" | jq '.rows | length')

    if [[ "$ns_count" -eq 0 ]]; then
        log_warn "  No namespaces found (permissions issue?)"
        return 1
    fi

    # Show sample namespaces
    sample_ns=$(echo "$ns_json" | jq -r '.rows[0:3] | .[].name' | tr '\n' ', ' | sed 's/,$//')
    log_info "    Sample namespaces: $sample_ns"

    log_info "  Cluster $anchor: OK"
    return 0
}

# Track test results
passed=0
failed=0

# Test EKS cluster (dss-eks-platform-dev)
if echo "$clusters_json" | jq -e '.[] | select(.anchor == "dss-eks-platform-dev")' &>/dev/null; then
    if test_cluster "dss-eks-platform-dev"; then
        ((passed++))
    else
        ((failed++))
    fi
else
    log_warn "EKS cluster (dss-eks-platform-dev) not configured, skipping"
fi

# Test AKS cluster (mathom-primary-cluster)
if echo "$clusters_json" | jq -e '.[] | select(.anchor == "mathom-primary-cluster")' &>/dev/null; then
    if test_cluster "mathom-primary-cluster"; then
        ((passed++))
    else
        ((failed++))
    fi
else
    log_warn "AKS cluster (mathom-primary-cluster) not configured, skipping"
fi

# --- Summary ---
echo ""
log_info "=== Test Summary ==="
log_info "Passed: $passed"
log_info "Failed: $failed"

if [[ "$failed" -gt 0 ]]; then
    log_error "Some tests failed"
    exit 1
fi

if [[ "$passed" -eq 0 ]]; then
    log_warn "No clusters were tested"
    exit 1
fi

log_info "All tests passed!"
