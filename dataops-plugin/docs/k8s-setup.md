# Kubernetes Skills Setup

Query Kubernetes clusters (EKS, AKS) via Steampipe SQL or fetch pod logs via stern.

## Prerequisites

- `yq` - `brew install yq`
- `kubectl` - `brew install kubectl`
- `stern` - `brew install stern` (for k8s-logs skill)
- For AKS: `kubelogin` - `brew install Azure/kubelogin/kubelogin`
- For EKS: `aws-vault` with configured profiles

## How It Works

The plugin ships a **cluster registry** with known clusters. You provide **overrides** that configure authentication for clusters you have access to. The bootstrap script merges both and produces a kubeconfig.

AKS clusters are pre-configured to use `kubelogin` with Azure CLI auth. You just need `az login`.

EKS clusters require you to add your `aws-vault` profile in the user config.

## Setup

### 1. Create user config (EKS only)

If you only use AKS clusters, skip this step.

Create `~/.dataops-assistant/k8s/clusters.yaml`:

**Example**

```yaml
clusters:
  - anchor: dss-eks-platform-dev
    kubeconfig:
      override:
        users:
          - name: arn:aws:eks:us-west-2:159625199976:cluster/dss-eks-platform-dev
            user:
              exec:
                apiVersion: client.authentication.k8s.io/v1beta1
                command: aws-vault
                args: [exec, YOUR_PROFILE_USED_TO_ACCESS_CLUSTER, --, aws, eks, get-token, --region, us-west-2, --cluster-name, dss-eks-platform-dev, --output, json]
```

The `anchor` must match a cluster in the shipped registry. The `users[0].name` must match the ARN that the obtain command generates.

### 2. Run bootstrap

```bash
./lib/k8s/bootstrap.sh
```

This will:
- Merge shipped registry with your overrides
- Fetch kubeconfig for each configured cluster
- Apply auth overrides
- Write combined kubeconfig to `~/.dataops-assistant/k8s/kubeconfig`

### 3. Verify

```bash
KUBECONFIG=~/.dataops-assistant/k8s/kubeconfig kubectl config get-contexts
```

## Available Clusters

Run bootstrap with no user config to see what's available:

| Anchor | Provider | Description |
|--------|----------|-------------|
| dss-eks-platform-dev | AWS | Development workloads |
| dss-eks-platform-prod | AWS | Production workloads |
| dev-experiment-cluster | Azure | Dev workloads (connectivity) |
| stage-experiment-cluster | Azure | Staging (PHI/PII) |
| datascience-primary-cluster | Azure | Flyte workloads |
| mathom-primary-cluster | Azure | Mathom team workloads |