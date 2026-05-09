# Kubernetes manifests

Iteration 3+ lives here. Unlike `terraform/` (which provisions cloud infra), this directory holds Helm values files for installing platform components into the AKS cluster.

## Install order

Each component has a `values.yaml` (or split files) plus copy-paste install commands. Run in order:

1. **`istio/`** — service mesh, ingress gateway (cluster's public entry point)
2. **`argocd/`** — drift-detection only (NOT pull-mode GitOps)
3. **`jenkins/`** — controller + Kubernetes-plugin agents; drives all deploys via `helm upgrade`

## Why this order

- Istio first because it owns the public LoadBalancer + IP
- ArgoCD before Jenkins so Jenkins can trigger ArgoCD refreshes if needed
- Jenkins last because it's the only thing that *runs other deploys* — needs the rest in place

## Re-running an install

Every install command uses `helm upgrade --install`, which is idempotent — safe to re-run after editing a values file.

## Resource budget on this lab cluster

Single D2s_v3 (2 vCPU / 8 GB). Values files set explicit, modest resource requests on every chart so the scheduler doesn't try to fit default-sized workloads (Istio in particular requests 2 GiB by default — would not schedule).
