---
description: "Query AWS infrastructure via Steampipe SQL. Requires explicit account selection and aws-vault profiles."
allowed-tools: ["Bash", "Read"]
model: sonnet
context: fork
status-check: scripts/status.sh
---


# AWS Steampipe Query

Query AWS infrastructure using Steampipe SQL with explicit account selection.

## What This Skill Does

- **Bypasses MCP** - Calls `steampipe` CLI directly for portability
- **User-scoped environment** - Uses `~/.dataops-assistant/steampipe-aws/` (survives plugin updates)
- **Explicit account selection** - Specify which account to query, or use aggregator for all
- **Profile-based auth** - Uses AWS profiles with `credential_process` for aws-vault integration

## Prerequisites

1. `steampipe` CLI installed
2. `yq` CLI installed (`brew install yq`)
3. `aws-vault` configured with appropriate profiles
4. AWS profiles configured with `credential_process` (see Setup)

## Setup

### 1. Configure AWS Profiles with aws-vault

In `~/.aws/config`, add profiles that use `credential_process` to call aws-vault:

```ini
[profile mcg_dev_dev_access]
region = us-west-2
credential_process = /opt/homebrew/bin/aws-vault exec mcg_dev_dev_access --json

[profile mcg_prod_prod_access]
region = us-west-2
credential_process = /opt/homebrew/bin/aws-vault exec mcg_prod_prod_access --json
```

**Note:** Use the full path to `aws-vault`. The `--json` flag is required.

### 2. Create Account Mapping

Create `~/.dataops-assistant/aws/accounts.yaml` mapping accounts to your profile names:

```yaml
accounts:
  - name: dss-common-dev
    profile: mcg_dev_dev_access

  - name: dss-common-prod
    profile: mcg_prod_prod_access

  - name: build
    profile: mcg_build_access
    regions: ["us-west-2"]  # Optional: limit to specific regions
```

### 3. Bootstrap

Run bootstrap to generate steampipe config and install the AWS plugin:

```bash
~/.dataops-assistant/run skills/aws-steampipe-query/scripts/bootstrap.sh
```

## Available Accounts

| Name | Account ID | Description |
|------|------------|-------------|
| `security` | 321441910708 | Security account |
| `shared-infra-dev` | 106388581530 | Shared infrastructure (dev) |
| `dss-common-dev` | 159625199976 | DSS common development |
| `build` | 959940652052 | Build/CI account |
| `dss-common-prod` | 492132060394 | DSS common production |
| `management` | 808565370955 | Management account |
| `dss-sandbox` | 622191734775 | DSS sandbox/experimentation |
| `legacy-mcghealth` | 866954699517 | Legacy MCG Health account |
| `quansight` | 502435701988 | Quansight account |
| `hearst-bedrock` | 493888979299 | Hearst Bedrock account |

Use the `accounts` command to see which accounts are configured:

```bash
./scripts/aws-steampipe.sh accounts
./scripts/aws-steampipe.sh accounts --all  # Include unconfigured
```

## Schema

**Each account has its own schema** - names with dashes become underscores:

```sql
-- Query dev account
SELECT * FROM aws_dss_common_dev.aws_s3_bucket LIMIT 5

-- Query prod account
SELECT * FROM aws_dss_common_prod.aws_ec2_instance

-- Query all configured accounts (aggregator)
SELECT * FROM aws_all.aws_s3_bucket
```

## Commands

```bash
# List configured accounts
~/.dataops-assistant/bin/aws-steampipe.sh accounts

# List all accounts (including unconfigured)
~/.dataops-assistant/bin/aws-steampipe.sh accounts --all

# Run a SQL query
~/.dataops-assistant/bin/aws-steampipe.sh dss-common-dev query "SELECT name FROM aws_dss_common_dev.aws_s3_bucket LIMIT 5"

# List available tables (optionally filtered)
~/.dataops-assistant/bin/aws-steampipe.sh dss-common-dev tables
~/.dataops-assistant/bin/aws-steampipe.sh dss-common-dev tables s3

# Describe a table's columns
~/.dataops-assistant/bin/aws-steampipe.sh dss-common-dev describe aws_s3_bucket
```

## Common Query Patterns

### S3 Buckets

```sql
-- All buckets in account
SELECT name, region, creation_date
FROM aws_dss_common_dev.aws_s3_bucket

-- Buckets with versioning disabled
SELECT name, region, versioning_status
FROM aws_dss_common_dev.aws_s3_bucket
WHERE versioning_status != 'Enabled'
```

### EC2 Instances

```sql
-- Running instances
SELECT instance_id, instance_type, instance_state, private_ip_address
FROM aws_dss_common_dev.aws_ec2_instance
WHERE instance_state = 'running'

-- Instances by type
SELECT instance_type, count(*) as count
FROM aws_dss_common_dev.aws_ec2_instance
GROUP BY instance_type
ORDER BY count DESC
```

### IAM Roles

```sql
-- All roles
SELECT name, create_date, max_session_duration
FROM aws_dss_common_dev.aws_iam_role

-- Roles with inline policies
SELECT name, inline_policies
FROM aws_dss_common_dev.aws_iam_role
WHERE inline_policies IS NOT NULL
```

### Lambda Functions

```sql
-- All functions
SELECT name, runtime, memory_size, timeout
FROM aws_dss_common_dev.aws_lambda_function

-- Functions by runtime
SELECT runtime, count(*) as count
FROM aws_dss_common_dev.aws_lambda_function
GROUP BY runtime
```

### EKS Clusters

```sql
-- All clusters
SELECT name, status, version, endpoint
FROM aws_dss_common_dev.aws_eks_cluster
```

### Cross-Account Queries

```sql
-- S3 buckets across all accounts
SELECT account_id, name, region
FROM aws_all.aws_s3_bucket
ORDER BY account_id, name

-- EC2 instances across all accounts
SELECT account_id, instance_id, instance_type, instance_state
FROM aws_all.aws_ec2_instance
WHERE instance_state = 'running'
```

## Account Selection Hints

When user mentions keywords, suggest appropriate account:

| User says | Suggest |
|-----------|---------|
| "dev", "development" | `dss-common-dev` |
| "prod", "production" | `dss-common-prod` |
| "build", "CI", "pipelines" | `build` |
| "sandbox", "experiment" | `dss-sandbox` |
| "security", "IAM" | `security` |

## Workflow

1. **Identify account** - Ask user which account or use keyword hints
2. **List tables** - If unsure which table, use `tables` command
3. **Check columns** - Use `describe` to see available fields
4. **Run query** - Execute SQL with correct schema prefix
5. **Format output** - Present results as markdown table

## Output Format

```markdown
## AWS Query: {description}

**Account:** {account}

| Name | Region | Status |
|------|--------|--------|
| ... | ... | ... |

**Resources found:** {count}
```

For no results:
```markdown
## AWS Query: {description}

**Account:** {account}

No resources found matching query.

**Suggestions:**
- Check resource name spelling
- Verify account selection
- Try broader search pattern (use ILIKE '%partial%')
```

## Error Handling

**Not bootstrapped:**
```bash
~/.dataops-assistant/run skills/aws-steampipe-query/scripts/bootstrap.sh
```

**Account not configured:**
- Check available accounts: `aws-steampipe.sh accounts --all`
- Add to `~/.dataops-assistant/aws/accounts.yaml`
- Re-run bootstrap

**Auth errors:**
- Verify aws-vault profile: `aws-vault exec <profile> -- aws sts get-caller-identity`
- Check `credential_process` in `~/.aws/config`
- Ensure aws-vault has valid credentials: `aws-vault list`

**Table not found:**
- List tables: `aws-steampipe.sh <account> tables`
- Tables are prefixed with `aws_`
