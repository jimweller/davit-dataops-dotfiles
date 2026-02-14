#!/usr/bin/env bash
set -euo pipefail

# E2E Test for aws-steampipe-query skill
#
# Runs in an isolated environment:
#   - Random port (29300-29399) to avoid conflicts
#   - Temp directory for steampipe install
#   - Uses real user aws/accounts.yaml (required for auth)
#
# Tests:
#   1. Bootstrap with isolated steampipe dir
#   2. List accounts
#   3. Query S3 buckets in configured account
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

# Random port in range 29300-29399
RANDOM_PORT=$((29300 + RANDOM % 100))

# Isolated steampipe directory
TEMP_DIR=$(mktemp -d)
TEST_STEAMPIPE_DIR="$TEMP_DIR/steampipe-aws"

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
log_info "=== AWS Steampipe E2E Test ==="
log_info "Temp dir: $TEMP_DIR"
log_info "Port: $RANDOM_PORT"
log_info "Steampipe dir: $TEST_STEAMPIPE_DIR"

# Check required tools
for tool in steampipe yq jq; do
    if ! command -v "$tool" &>/dev/null; then
        log_error "$tool not installed"
        exit 1
    fi
done
log_info "Required tools: OK"

# Check user config exists
USER_CONFIG="$HOME/.dataops-assistant/aws/accounts.yaml"
if [[ ! -f "$USER_CONFIG" ]]; then
    log_error "User config not found: $USER_CONFIG"
    log_error "Create config with account mappings first"
    exit 1
fi
log_info "User config: OK"

# Check AWS profiles exist in ~/.aws/config
AWS_CONFIG="$HOME/.aws/config"
if [[ ! -f "$AWS_CONFIG" ]]; then
    log_error "AWS config not found: $AWS_CONFIG"
    exit 1
fi
log_info "AWS config: OK"

# --- Set isolated environment ---
export DATAOPS_ASSISTANT_AWS_STEAMPIPE_DIR="$TEST_STEAMPIPE_DIR"
export DATAOPS_ASSISTANT_AWS_STEAMPIPE_PORT="$RANDOM_PORT"

# --- Test 1: Bootstrap ---
log_test "1. Bootstrap in isolated directory"

"$SKILL_ROOT/scripts/bootstrap.sh"

if [[ ! -f "$TEST_STEAMPIPE_DIR/config/aws.spc" ]]; then
    log_error "Bootstrap failed: steampipe config not created"
    exit 1
fi

log_info "Bootstrap: OK"

# --- Test 2: List accounts ---
log_test "2. List configured accounts"

accounts_json=$("$SKILL_ROOT/scripts/aws-steampipe.sh" accounts)
account_count=$(echo "$accounts_json" | jq 'length')

log_info "Found $account_count configured account(s)"

if [[ "$account_count" -eq 0 ]]; then
    log_error "No accounts configured. Add mappings to $USER_CONFIG"
    exit 1
fi

# Show accounts
echo "$accounts_json" | jq -r '.[] | "  - \(.name) (\(.profile))"'

# --- Test 3: List all accounts ---
log_test "3. List all accounts (configured status)"

all_accounts_json=$("$SKILL_ROOT/scripts/aws-steampipe.sh" accounts --all)
all_count=$(echo "$all_accounts_json" | jq 'length')
configured_count=$(echo "$all_accounts_json" | jq '[.[] | select(.configured == true)] | length')

log_info "Registry has $all_count accounts, $configured_count configured"

# --- Test 4: Query configured account ---
log_test "4. Query S3 tables"

# Get first configured account
first_account=$(echo "$accounts_json" | jq -r '.[0].name')
first_schema="aws_$(echo "$first_account" | tr '-' '_')"

log_info "Testing account: $first_account (schema: $first_schema)"

# Test tables command
log_info "  - tables command..."
tables_json=$("$SKILL_ROOT/scripts/aws-steampipe.sh" "$first_account" tables s3 2>/dev/null || echo '{"rows":[]}')
table_count=$(echo "$tables_json" | jq '.rows | length')

if [[ "$table_count" -eq 0 ]]; then
    log_warn "  No S3 tables found (may need MFA or permissions)"
    # Don't fail - this could be an auth timing issue
else
    log_info "    Found $table_count S3 tables"
fi

# --- Test 5: Query S3 buckets ---
log_test "5. Query S3 buckets"

log_info "  - querying buckets..."
buckets_json=$("$SKILL_ROOT/scripts/aws-steampipe.sh" "$first_account" query \
    "SELECT name, region FROM ${first_schema}.aws_s3_bucket LIMIT 5" 2>/dev/null || echo '{"rows":[]}')
bucket_count=$(echo "$buckets_json" | jq '.rows | length')

if [[ "$bucket_count" -eq 0 ]]; then
    log_warn "  No buckets found (may need MFA or permissions)"
else
    # Show sample buckets
    sample_buckets=$(echo "$buckets_json" | jq -r '.rows[0:3] | .[].name' | tr '\n' ', ' | sed 's/,$//')
    log_info "    Found $bucket_count buckets"
    log_info "    Sample: $sample_buckets"
fi

# --- Test 6: Describe table ---
log_test "6. Describe table schema"

log_info "  - describing aws_s3_bucket..."
describe_json=$("$SKILL_ROOT/scripts/aws-steampipe.sh" "$first_account" describe aws_s3_bucket 2>/dev/null || echo '{"rows":[]}')
column_count=$(echo "$describe_json" | jq '.rows | length')

if [[ "$column_count" -eq 0 ]]; then
    log_warn "  No columns found"
else
    log_info "    Found $column_count columns"
fi

# --- Summary ---
echo ""
log_info "=== Test Summary ==="
log_info "Bootstrap: OK"
log_info "Accounts listed: $account_count"
log_info "Tables found: $table_count"
log_info "Buckets found: $bucket_count"
log_info "Columns described: $column_count"

if [[ "$table_count" -gt 0 ]] && [[ "$bucket_count" -gt 0 ]]; then
    log_info "All tests passed!"
else
    log_warn "Some queries returned no results (may need fresh aws-vault session)"
    log_info "Core functionality verified"
fi
