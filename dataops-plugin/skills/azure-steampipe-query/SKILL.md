---
description: "Query Azure infrastructure via Steampipe SQL. Uses embedded config for portable, predictable schema names. Requires steampipe CLI and az login."
allowed-tools: ["Bash"]
model: sonnet
context: fork
status-check: scripts/status.sh
---


# Azure Steampipe Query

Query Azure infrastructure using Steampipe SQL with a portable, skill-embedded configuration.

## What This Skill Does

- **Bypasses MCP** - Calls `steampipe` CLI directly for portability
- **Isolated environment** - Uses its own steampipe install in `assets/` (doesn't touch `~/.steampipe`)
- **Embedded config** - Bundled config with predictable `azure_company_all` schema
- **Azure-scoped** - Queries across all company Azure subscriptions via aggregator

## Prerequisites

1. `steampipe` CLI installed
2. `az login` authenticated
3. **One-time bootstrap** (creates isolated steampipe environment):

```bash
~/.dataops-assistant/run skills/azure-steampipe-query/scripts/bootstrap.sh
```

This downloads the Azure plugin and initializes the database in `assets/`. Takes ~1 min, creates ~100MB of data (gitignored).

## Schema

**Always use the `azure_company_all` schema** - this aggregates across all subscriptions:

```sql
-- CORRECT: Uses aggregator across all subscriptions
SELECT * FROM azure_company_all.azure_subscription LIMIT 5

-- WRONG: No schema prefix
SELECT * FROM azure_subscription
```

## Commands

```bash
# Run a SQL query
~/.dataops-assistant/bin/steampipe-query.sh "SELECT * FROM azure_company_all.azure_subscription LIMIT 5"

# List available tables (optionally filtered)
~/.dataops-assistant/bin/steampipe-query.sh tables
~/.dataops-assistant/bin/steampipe-query.sh tables kubernetes

# Describe a table's columns
~/.dataops-assistant/bin/steampipe-query.sh describe azure_kubernetes_cluster
```

## Common Query Patterns

### AKS Clusters
```sql
SELECT name, resource_group, location, kubernetes_version,
       power_state_code, provisioning_state
FROM azure_company_all.azure_kubernetes_cluster
WHERE name ILIKE '%cluster-name%'
```

### Virtual Machines
```sql
SELECT name, power_state, vm_size, resource_group, location
FROM azure_company_all.azure_compute_virtual_machine
WHERE resource_group ILIKE '%resource-group%'
```

### Storage Accounts
```sql
SELECT name, resource_group, location, sku_tier, provisioning_state
FROM azure_company_all.azure_storage_account
WHERE name ILIKE '%name%'
```

### Resource Groups
```sql
SELECT name, location, provisioning_state
FROM azure_company_all.azure_resource_group
ORDER BY name
```

### Subscriptions
```sql
SELECT subscription_id, display_name, state
FROM azure_company_all.azure_subscription
```

## Workflow

1. **Understand the query** - What Azure resource info is needed?
2. **Find the table** - Use `tables` command if unsure which table
3. **Check columns** - Use `describe` to see available fields
4. **Run query** - Execute SQL with `azure_company_all` schema prefix
5. **Format output** - Present results as markdown table

## Output Format

```markdown
## Azure Query: {description}

| Property | Value |
|----------|-------|
| Name | {value} |
| Status | {value} |

**Resources found:** {count}
```

For no results:
```markdown
## Azure Query: {description}

No resources found matching query.

**Suggestions:**
- Check resource name spelling
- Verify subscription access via `az account show`
- Try broader search pattern (use ILIKE '%partial%')
```

## Error Handling

**Auth errors:**
1. Check `az login` status: `az account show`
2. Re-authenticate: `az login`

**Table not found:**
1. List tables: `steampipe-query.sh tables`
2. Check spelling - tables are prefixed with `azure_`

**No results:**
- The aggregator queries all 113 subscriptions
- Use `ILIKE '%partial%'` for fuzzy matching
- Check if resource exists in Azure Portal
