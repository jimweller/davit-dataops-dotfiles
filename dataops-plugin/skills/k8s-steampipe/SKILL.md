---
description: "Query Kubernetes clusters via Steampipe SQL. Requires explicit cluster selection."
allowed-tools: ["Bash", "Read"]
model: sonnet
context: fork
status-check: scripts/status.sh
---


# K8s Steampipe

Query Kubernetes clusters using Steampipe SQL with explicit cluster selection.

## What This Skill Does

- **Bypasses MCP** - Calls `steampipe` CLI directly for portability
- **User-scoped environment** - Uses `~/.dataops-assistant/steampipe-k8s/` (survives plugin updates)
- **Explicit cluster selection** - No aggregator; specify which cluster to query
- **Unified registry** - Shipped defaults + user overrides merged by anchor

## Prerequisites

1. `steampipe` CLI installed
2. `yq` CLI installed (`brew install yq`)
3. `kubectl` installed
4. For EKS clusters: `aws-vault` configured with appropriate profiles
5. For AKS clusters: `az login` + `kubelogin` installed

## Setup

**One-time bootstrap** (after creating user config):

```bash
~/.dataops-assistant/run skills/k8s-steampipe/scripts/bootstrap.sh
```

This:
- Merges shipped registry with your overrides
- Runs obtain commands for each configured cluster
- Applies auth overrides (aws-vault, kubelogin)
- Generates steampipe config with per-cluster connections

### User Configuration

Create `~/.dataops-assistant/k8s-clusters.yaml` with your cluster overrides:

```yaml
clusters:
  # EKS cluster with aws-vault auth
  - anchor: dss-eks-platform-dev
    kubeconfig:
      override:
        users:
          - name: dss-eks-platform-dev
            user:
              exec:
                apiVersion: client.authentication.k8s.io/v1
                command: aws-vault
                args: [exec, mcg_dev_dev_access, --, aws, eks, get-token, --region, us-west-2, --cluster-name, dss-eks-platform-dev]

  # AKS cluster with kubelogin
  - anchor: datascience-primary-cluster
    kubeconfig:
      override:
        users:
          - name: tfv69qrbokiz6o57
            user:
              exec:
                apiVersion: client.authentication.k8s.io/v1
                command: kubelogin
                args: [get-token, --login, azurecli]
```

**Note:** Only clusters with non-empty `override` sections are configured. Clusters without overrides are skipped.

## Available Clusters

| Anchor | Provider | Description | Keywords |
|--------|----------|-------------|----------|
| `dss-eks-platform-dev` | AWS | Development workloads (preferred) | dev, dss, aws |
| `dss-eks-platform-prod` | AWS | Production workloads | prod, dss, aws |
| `dev-experiment-cluster` | Azure | Development (Azure connectivity) | dev, azure, datascience |
| `stage-experiment-cluster` | Azure | Staging (sensitive, PHI/PII) | stage, azure |
| `datascience-primary-cluster` | Azure | Flyte primary (sensitive) | prod, datascience, flyte |
| `mathom-primary-cluster` | Azure | Mathom team (requires SG membership) | prod, mathom, flyte |

Use the `clusters` command to see which clusters are configured:

```bash
./scripts/k8s-steampipe.sh clusters
```

## Schema

**Each cluster has its own schema** - anchors with dashes become underscores:

```sql
-- Query dev cluster
SELECT * FROM k8s_dss_eks_platform_dev.kubernetes_pod LIMIT 5

-- Query prod cluster
SELECT * FROM k8s_dss_eks_platform_prod.kubernetes_namespace
```

## Commands

```bash
# List configured clusters
~/.dataops-assistant/bin/k8s-steampipe.sh clusters

# List all clusters (including unconfigured)
~/.dataops-assistant/bin/k8s-steampipe.sh clusters --all

# Run a SQL query
~/.dataops-assistant/bin/k8s-steampipe.sh dss-eks-platform-dev query "SELECT name, namespace FROM k8s_dss_eks_platform_dev.kubernetes_pod LIMIT 5"

# List available tables (optionally filtered)
~/.dataops-assistant/bin/k8s-steampipe.sh dss-eks-platform-dev tables
~/.dataops-assistant/bin/k8s-steampipe.sh dss-eks-platform-dev tables pod

# Describe a table's columns
~/.dataops-assistant/bin/k8s-steampipe.sh dss-eks-platform-dev describe kubernetes_pod
```

## Common Query Patterns

### Pods

```sql
-- All pods in a namespace
SELECT name, namespace, phase, host_ip, pod_ip
FROM k8s_dss_eks_platform_dev.kubernetes_pod
WHERE namespace = 'kube-system'

-- Pods not running
SELECT name, namespace, phase, restart_count
FROM k8s_dss_eks_platform_dev.kubernetes_pod
WHERE phase != 'Running'

-- Pods with high restart count
SELECT name, namespace, restart_count
FROM k8s_dss_eks_platform_dev.kubernetes_pod
WHERE restart_count > 5
ORDER BY restart_count DESC
```

### Deployments

```sql
-- All deployments
SELECT name, namespace, replicas, ready_replicas, available_replicas
FROM k8s_dss_eks_platform_dev.kubernetes_deployment

-- Deployments not fully available
SELECT name, namespace, replicas, available_replicas
FROM k8s_dss_eks_platform_dev.kubernetes_deployment
WHERE replicas != available_replicas
```

### Services

```sql
-- All services
SELECT name, namespace, type, cluster_ip
FROM k8s_dss_eks_platform_dev.kubernetes_service

-- LoadBalancer services
SELECT name, namespace, cluster_ip,
       selector::text as selector
FROM k8s_dss_eks_platform_dev.kubernetes_service
WHERE type = 'LoadBalancer'
```

### ConfigMaps and Secrets

```sql
-- ConfigMaps in namespace
SELECT name, namespace
FROM k8s_dss_eks_platform_dev.kubernetes_config_map
WHERE namespace = 'default'

-- Secrets by type
SELECT name, namespace, type
FROM k8s_dss_eks_platform_dev.kubernetes_secret
WHERE type = 'kubernetes.io/tls'
```

### Namespaces

```sql
-- All namespaces
SELECT name, phase, labels
FROM k8s_dss_eks_platform_dev.kubernetes_namespace

-- Non-system namespaces
SELECT name, phase
FROM k8s_dss_eks_platform_dev.kubernetes_namespace
WHERE name NOT LIKE 'kube-%'
  AND name NOT IN ('default', 'gatekeeper-system')
```

### Nodes

```sql
-- Node status
SELECT name,
       allocatable_cpu, allocatable_memory,
       capacity_cpu, capacity_memory
FROM k8s_dss_eks_platform_dev.kubernetes_node
```

### Events

```sql
-- Recent warning events
SELECT namespace, involved_object_name, reason, message, count
FROM k8s_dss_eks_platform_dev.kubernetes_event
WHERE type = 'Warning'
ORDER BY last_timestamp DESC
LIMIT 20
```

## Cluster Selection Hints

When user mentions keywords, suggest appropriate cluster:

| User says | Suggest |
|-----------|---------|
| "dev", "development", "sandbox" | `dss-eks-platform-dev` |
| "prod", "production" | `dss-eks-platform-prod` (AWS) or `datascience-primary-cluster` (Azure) |
| "flyte", "workflows" | `datascience-primary-cluster` or `mathom-primary-cluster` |
| "datascience", "data science" | `datascience-primary-cluster` |
| "mathom" | `mathom-primary-cluster` |
| "staging", "stage" | `stage-experiment-cluster` |

## Workflow

1. **Identify cluster** - Ask user which cluster or use keyword hints
2. **List tables** - If unsure which table, use `tables` command
3. **Check columns** - Use `describe` to see available fields
4. **Run query** - Execute SQL with correct schema prefix
5. **Format output** - Present results as markdown table

## Output Format

```markdown
## K8s Query: {description}

**Cluster:** {cluster}

| Name | Namespace | Status |
|------|-----------|--------|
| ... | ... | ... |

**Resources found:** {count}
```

For no results:
```markdown
## K8s Query: {description}

**Cluster:** {cluster}

No resources found matching query.

**Suggestions:**
- Check namespace spelling
- Verify cluster selection
- Try broader search pattern (use ILIKE '%partial%')
```

## Error Handling

**Not bootstrapped:**
```bash
~/.dataops-assistant/run skills/k8s-steampipe/scripts/bootstrap.sh
```

**Cluster not configured:**
- Check available clusters: `k8s-steampipe.sh clusters --all`
- Add override to `~/.dataops-assistant/k8s-clusters.yaml`
- Re-run bootstrap

**Auth errors (EKS):**
- Verify aws-vault profile: `aws-vault exec <profile> -- aws sts get-caller-identity`
- Check profile has EKS permissions

**Auth errors (AKS):**
- Verify Azure CLI auth: `az account show`
- Check kubelogin: `kubelogin --version`
- Re-authenticate: `az login`

**Table not found:**
- List tables: `k8s-steampipe.sh <cluster> tables`
- Tables are prefixed with `kubernetes_`
