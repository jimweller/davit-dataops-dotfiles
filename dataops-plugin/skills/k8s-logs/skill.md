---
description: "Fetch pod logs from Kubernetes clusters via stern. Requires explicit cluster selection"
allowed-tools: ["Bash"]
model: sonnet
context: fork
---

# k8s-logs

## Prerequisites

- `stern` CLI installed (`brew install stern`)
- `kubectl` CLI installed
- K8s bootstrap completed (shared with k8s-steampipe)

## Usage

```bash
# List configured clusters
~/.dataops-assistant/bin/k8s-logs.sh clusters

# List namespaces in a cluster
~/.dataops-assistant/bin/k8s-logs.sh <cluster> namespaces

# List pods in a namespace
~/.dataops-assistant/bin/k8s-logs.sh <cluster> pods <namespace>

# Fetch logs (stern query)
~/.dataops-assistant/bin/k8s-logs.sh <cluster> <namespace> <pod-query> [options]
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--since <duration>` | Show logs since (e.g., 5m, 1h) | 5m |
| `--tail <lines>` | Number of lines to tail | 100 |
| `--container <name>` | Container name (multi-container pods) | all |
| `--timestamps` | Include timestamps | off |
| `--previous` | Show logs from previous instance | off |

## Cluster Selection

**CRITICAL**: You MUST ask the user which cluster to query. Never assume or default.

Available clusters (run `clusters` command to get current list):
- EKS: dss-eks-platform-dev, dss-eks-platform-prod
- AKS: datascience-primary-cluster, mathom-primary-cluster, dev-experiment-cluster, stage-experiment-cluster

## Instructions

1. Ask the user which cluster to query (show available options)
2. List namespaces to help them identify the right one
3. List pods to identify the query pattern
4. Fetch logs with appropriate options

## Examples

```bash
# Flyte workflow logs (last 5 min)
~/.dataops-assistant/bin/k8s-logs.sh datascience-primary-cluster flyte "workflow-*"

# CoreDNS logs with timestamps
~/.dataops-assistant/bin/k8s-logs.sh dss-eks-platform-dev kube-system "coredns-*" --timestamps

# Previous container instance logs
~/.dataops-assistant/bin/k8s-logs.sh mathom-primary-cluster default my-pod --previous

# Last hour of logs
~/.dataops-assistant/bin/k8s-logs.sh dss-eks-platform-prod app "api-*" --since 1h --tail 500
```

## Notes

- Pod query uses stern's regex matching (e.g., `api-.*` matches api-abc, api-xyz)
- Use `--container` for pods with sidecars to filter specific container
- The `--no-follow` flag is used automatically (no streaming)
