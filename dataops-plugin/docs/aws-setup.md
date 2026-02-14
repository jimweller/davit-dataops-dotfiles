# AWS Steampipe Setup

Query AWS accounts via Steampipe SQL with explicit account selection.

## Prerequisites

- `yq` - `brew install yq`
- `steampipe` - [https://steampipe.io/downloads](https://steampipe.io/downloads)
- AWS credentials via `aws-vault` or credential_process in `~/.aws/config`

## How It Works

The plugin ships an **account registry** with known AWS accounts. You create a config file that maps accounts to your local AWS profiles. The bootstrap script generates Steampipe configuration for each mapped account.

Queries use schema names like `aws_dss_common_dev.aws_s3_bucket` (account name with dashes converted to underscores).

## Setup

### 1. Create user config

Create `~/.dataops-assistant/aws/accounts.yaml`:

```yaml
accounts:
  - name: dss-common-dev
    profile: mcg_dev_dev_access

  - name: dss-common-prod
    profile: mcg_prod_prod_access
```

Each `name` must match an account in the shipped registry. The `profile` is your AWS profile name from `~/.aws/config`.

### 2. Configure AWS profiles

Your AWS profiles need to work with Steampipe. The easiest way is `credential_process` in `~/.aws/config`:

```ini
[profile mcg_dev_dev_access]
credential_process = aws-vault exec mcg_dev_dev_access --json
region = us-west-2
```

### 3. Run bootstrap

```bash
./skills/aws-steampipe-query/scripts/bootstrap.sh
```

This will:
- Validate your account config against the registry
- Generate Steampipe config at `~/.dataops-assistant/steampipe-aws/config/aws.spc`
- Install the AWS Steampipe plugin if needed

### 4. Verify

```bash
./skills/aws-steampipe-query/scripts/aws-steampipe.sh accounts
```
## Usage Examples

```bash
# List configured accounts
./skills/aws-steampipe-query/scripts/aws-steampipe.sh accounts

# List tables
./skills/aws-steampipe-query/scripts/aws-steampipe.sh dss-common-dev tables

# Query S3 buckets
./skills/aws-steampipe-query/scripts/aws-steampipe.sh dss-common-dev query \
  "SELECT name, region FROM aws_dss_common_dev.aws_s3_bucket LIMIT 5"
```
