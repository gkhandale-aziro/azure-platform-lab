# How I Built a Production-Grade Kubernetes Platform on Azure in 6 Iterations

I needed to learn Azure for a Platform Engineer interview and had 30 days of Free Trial credit. Here's what I built end-to-end.

## TL;DR

A complete platform engineering reference implementation:
- Terraform-managed AKS cluster, ACR, networking
- Istio service mesh with mTLS
- Three-tier app (React + Node + Postgres) deployed via Helm
- **Two parallel CI/CD pipelines**: Jenkins (in-cluster) and GitHub Actions (GitOps via ArgoCD)
- **Progressive delivery**: Argo Rollouts blue/green with Prometheus-driven analysis gates
- Built in 6 reviewable iterations, ~$140/month at full footprint (~$5/month idle)

Repo: https://github.com/gkhandale-aziro/azure-platform-lab

## Why iterations, not one big push

Real platforms aren't built top-down. They evolve. Each iteration ships a working slice that survives a code review:

| Iter | Adds | Validates |
|---|---|---|
| 1 | tfstate SA + VNet + NSGs | Terraform backend pattern works |
| 2 | ACR + AKS | RBAC and role assignments wired |
| 3 | Istio + ArgoCD + Jenkins on cluster | Platform components scheduled with right resource budgets |
| 4 | 3-tier Helm chart + namespaces + VirtualServices | App reaches the right namespace via Host header |
| 5 | Real app code + Jenkins pipeline | CI runs in-cluster, kaniko pushes to ACR |
| 6 | GitHub Actions + Argo Rollouts + Prometheus AnalysisTemplate | Progressive delivery with metric gates |

## The three things I learned that aren't in tutorials

### 1. NSG explicit-deny rules at high priority break cluster-internal traffic

I added a `DenyAllInboundExplicit` rule at priority 4000 thinking I was being thorough. Pod-to-pod traffic across nodes died when I scaled to 2 nodes. Load balancer health probes failed.

**Why:** Azure has implicit allows at priority 65000 (AllowVnetInBound) and 65001 (AllowAzureLoadBalancerInBound). An explicit deny at 4000 fires first. Fix: add explicit `AllowVnetInbound` (1000) and `AllowAzureLoadBalancerInbound` (1100) BEFORE your deny.

Lesson: "default deny" in NSGs isn't just "drop everything I didn't allow" — it shadows implicit allows you depend on.

### 2. Free Trial SKU policy ≠ vCPU quota

I planned for B2s nodes (4 vCPU = 2 nodes fits the 4 vCPU/family/region quota). But Free Trial blocks B-series in eastus2 entirely via a SKU allowlist, separate from quota.

Quota says "how much you can use." SKU policy says "what SKUs you're allowed to use at all." Check both:

```bash
az vm list-skus --location eastus2 --resource-type virtualMachines -o table
```

Ended up on D2s_v3 — same 2 vCPU per node but $0.10/hr vs B2s's $0.04/hr.

### 3. Istio sidecar CPU requests pile up and break scheduling

After deploying Istio + ArgoCD + Jenkins + the 3-tier app, dev pods stuck in `Init:1/2` for 28 minutes. `kubectl describe` showed `Insufficient cpu`.

Default Istio sidecar request: 100m CPU per pod. With 8 app pods × 100m = 800m just for sidecars. On a 2 vCPU node with system pods already consuming 1100m, scheduler couldn't fit them.

Three-part fix:
1. Per-pod annotations to trim sidecars: `sidecar.istio.io/proxyCPU: "10m"`
2. Opt the database out of injection entirely (no need for mTLS to itself): `sidecar.istio.io/inject: "false"`
3. Scale cluster from 1 → 2 nodes

Saved ~270m CPU per namespace.

## The CI/CD pattern that actually matters: GitOps with progressive delivery

The interesting part isn't "I have a CI pipeline." It's:

```
GitHub Actions:
  build image with git SHA tag
  edit values.yaml to point at new SHA
  commit + push to master
  STOP

ArgoCD:
  detect Git change on master
  sync helm chart to cluster
  STOP

Argo Rollouts:
  notice Rollout spec has new image tag
  create green ReplicaSet alongside blue
  run prePromotionAnalysis:
    - min-traffic gate: must see >= 1 req/sec on green
    - success-rate gate: >= 95% non-5xx over 2 min
  on pass: promote green → active, scale down blue after 30s
  on fail: abort, blue keeps serving
```

What's special:

- **CI never touches the cluster.** No kubeconfig in GitHub. The only secret is the ACR push credential.
- **Git is the source of truth.** Every deploy is a reviewable commit. Rollback = `git revert`.
- **Build once, deploy many.** Same image SHA flows dev → prod. Not a rebuild. The image you scanned is the exact image that goes to prod.
- **Metric-gated promotion.** The `min-traffic` gate is the one most teams forget. Without it, Prometheus returns empty `result[]` for a zero-traffic preview, your success-rate query crashes the analyzer, and you have to handle that. Adding `or vector(1)` returns 1.0 (100% success) — but that means **zero traffic = automatic success**, which is wrong. Two-gate analysis (min-traffic + success-rate) fixes the false-positive.

## The interview honesty section

What I'd add for production:

1. **External Secrets Operator + Azure Key Vault** — kill hardcoded DB passwords in values.yaml
2. **Workload Identity for ACR** — replace the SP credential with a workload identity binding
3. **Cosign image signing + Kyverno admission policy** — verify images at admission, not just scan them
4. **Branch protection on master** — require PR + 1 approval + green CI before merge
5. **Automated rollback on SLO breach** — Prometheus alert → webhook → `kubectl argo rollouts abort`
6. **Private AKS cluster** — no public API endpoint, bastion + jumpbox for access
7. **Multi-environment state files** — separate Terraform state per environment
8. **Velero for backups** — automated PV snapshots and cluster state

The architecture is production-aligned. The hardening is what's missing.

## The cost line

D2s_v3 burns $0.10/hour. Two of them 24/7 = ~$140/month. The trick:

```bash
az aks stop -g gskplat-rg-platform -n gskplat-aks-shared    # nights/weekends
az aks start -g gskplat-rg-platform -n gskplat-aks-shared
```

Control plane stays free when stopped. ACR + LAW + state SA accumulate ~$5/month idle.

## Closing

Six iterations. Real Terraform modules, real app code, real CI/CD with two patterns side-by-side, real progressive delivery with metric gates. Started from `az login` and ended with `kubectl argo rollouts promote frontend -n dev` after watching success-rate climb in Grafana.

Code: [github.com/gkhandale-aziro/azure-platform-lab](https://github.com/gkhandale-aziro/azure-platform-lab)
Architecture diagrams: [`docs/architecture.md`](architecture.md)
Demo script: [`docs/interview-demo-script.md`](interview-demo-script.md)
