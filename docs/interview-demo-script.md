# Interview Demo Script — Azure Platform Lab

A 5-minute walkthrough designed to land the "I built this end-to-end" message in an interview.

Open three browser tabs before you start:
1. **GitHub Actions** — https://github.com/gkhandale-aziro/azure-platform-lab/actions
2. **ArgoCD UI** — http://localhost:58443/
3. **Live app** — http://dev.lvh.me:59999/

Open one terminal tab with `ssh azurelab` and `kubectl argo rollouts get rollout frontend -n dev --watch` running.

---

## 30-second elevator pitch (before you start clicking)

> "I built a platform engineering lab on Azure that demonstrates modern CI/CD: GitOps with ArgoCD, progressive delivery with Argo Rollouts, blue/green deployments gated by Prometheus metrics. Infrastructure is Terraform-managed AKS with Istio service mesh. CI runs in two parallel systems — Jenkins inside the cluster and GitHub Actions outside — so I can speak to both patterns. Let me show you the GitHub Actions flow because that's the more modern one."

---

## 1-minute architecture (the slide)

Show the ASCII diagram from the README:

```
GitHub Actions → builds image → commits values.yaml to Git
       ↓
ArgoCD (auto-sync) → applies Helm chart to cluster
       ↓
Argo Rollouts → creates green ReplicaSet alongside blue
       ↓
AnalysisRun → Prometheus queries for min-traffic + success-rate
       ↓
On pass → auto-promote (dev) OR await human (prod)
```

Key things to point out:
- **GitHub Actions never touches the cluster** — it just commits Git
- **Git is the source of truth** — every deploy is a reviewable commit
- **Two-gate analysis** — min-traffic prevents false-positive promotions on zero traffic

---

## 2-minute live demo

### Step 1 — Show the workflow trigger

> "I trigger the pipeline manually with `workflow_dispatch` — production teams would do this on PR merge."

Click **Run workflow** in GitHub Actions.

While it runs, narrate the jobs:

> "Resolve-tag computes the image tag as the git short SHA — `sha-abc1234`. That's immutable and traceable to a specific commit. CI checks run in parallel — npm test, lint, gitleaks for secrets. Then build with kaniko-equivalent (buildx + GHA cache), trivy scans report-only. The deploy job is just a Python script that edits values-dev.yaml and pushes to master. GitHub never gets a kubeconfig."

### Step 2 — Switch to ArgoCD UI

When the workflow's `update-dev-tags` job completes, refresh the ArgoCD UI:

> "ArgoCD picked up the Git change within 3 minutes (default polling). It detected an image tag change in the Rollout spec, applied it."

Click on `three-tier-dev` → see Rollout resource shows new image.

### Step 3 — Switch to the terminal

> "Argo Rollouts creates the green ReplicaSet. Watch the analysis run."

```
Status:          ◌ Progressing
Message:         active service cutover pending
Images:          gskplatacrn73d5y.azurecr.io/three-tier/frontend:sha-OLD (stable, active)
                 gskplatacrn73d5y.azurecr.io/three-tier/frontend:sha-NEW (preview)
```

Point at the AnalysisRun row:

> "Two-gate analysis: min-traffic requires at least 1 req/sec on the preview Service. Without this, the rollout would falsely auto-promote on zero traffic because `or vector(1)` would score 100% success. Min-traffic forces real traffic to flow first."

### Step 4 — Drive traffic to satisfy min-traffic

In another terminal:

```bash
kubectl port-forward -n dev svc/frontend-preview 8081:80 &
for i in $(seq 1 100); do curl -s http://localhost:8081/ >/dev/null; sleep 0.3; done
```

> "I'm driving traffic to the preview Service. In production this would be automated smoke tests."

Watch the rollout — both gates flip to ✔ 3, then auto-promote (dev has `autoPromotionEnabled: true`).

### Step 5 — Verify live

```bash
curl -s "http://localhost:9999/api/info" -H "Host: dev.gskplat.local"
```

> "Live URL now returns the new SHA. Dev deployment complete with zero manual `kubectl` commands."

### Step 6 — Show prod gate

Back in GitHub Actions — workflow is paused at `approve-prod`:

> "Prod requires a manual approval in the GitHub Environments UI. This is the change-management gate. In a real team this would integrate with ServiceNow or a release manager."

Click **Review deployments** → approve.

> "Watch this — prod gets the SAME SHA. Not a rebuild. Same image, same scan results, same digest. That's image promotion — build once, deploy many."

```bash
curl -s "http://localhost:9999/api/info" -H "Host: prod.gskplat.local"
```

Same SHA returns.

---

## 30-second wrap (the "what I'd add" honesty)

> "This is the architectural pattern. What I'd add for production: External Secrets Operator with Azure Key Vault to kill the hardcoded DB passwords, Cosign image signing with Kyverno admission policy, Workload Identity instead of long-lived SP credentials, branch protection on master, and Prometheus-driven automated rollback on SLO breach. The patterns are production-aligned; the hardening is what's missing."

---

## Common interview questions you'll get & how to answer

| Question | Answer anchor |
|---|---|
| Why git SHA as image tag? | Immutable, traceable to commit, makes rollback to "version before commit X" trivial. |
| Why GitOps over `kubectl apply`? | Auditability — every deploy is a reviewable commit. Rollback = git revert. Cluster state is always derivable from Git. |
| Why blue/green not canary? | Simpler reasoning: 100% on one version. Canary is better for risky changes where 10% sample is meaningful (recommendation engines etc.). Both supported by Argo Rollouts. |
| What if no traffic hits preview? | That's why min-traffic gate exists. Without it, `or vector(1)` returns 1.0 = false-positive success. With it, rollout aborts after 3 failed checks until traffic is driven. |
| How do you rollback? | `kubectl argo rollouts undo` for instant rollback (old blue alive for 30s). Or `git revert <bump-commit>` for the audit-trail-friendly path — ArgoCD reverts the cluster. |
| Why two CI systems? | Demonstrates both patterns. Jenkins runs *inside* the cluster (no kubeconfig export needed). GitHub Actions runs *outside* — natural fit for GitOps where CI just commits to Git. Production picks one based on whether team wants self-hosted vs SaaS. |
| Why ArgoCD `Suspended` health when paused? | That's correct! Rollout is intentionally paused at `BlueGreenPause` waiting for human decision. Not broken — it's the production safety gate working as designed. |
| Where's image scanning? | Trivy in CI — report-only mode so it doesn't block on flaky CVE databases. Reports archived as workflow artifacts. In production you'd block on Critical and use Renovate to auto-PR base image bumps. |
| What's missing for production? | Image signing (Cosign), workload identity (no SP secrets), External Secrets (Key Vault), branch protection, SLO-driven auto-rollback, private AKS cluster. |

---

## Failure mode demo (advanced)

If interviewer wants to see rollback, after promote:

```bash
kubectl argo rollouts undo frontend -n dev
```

> "Instant rollback. Old blue is kept for 30s after promote, so this is literally a Service selector flip — no pod restart."

---

## Where the code lives (citations)

- `.github/workflows/ci-cd.yaml` — workflow with all four production patterns (git SHA, image promotion, auto-promote dev, min-traffic gate)
- `kubernetes/apps/three-tier/charts/frontend/templates/rollout.yaml` — Rollout CRD with blueGreen strategy
- `kubernetes/apps/three-tier/charts/frontend/templates/analysistemplate.yaml` — two-gate Prometheus analysis
- `kubernetes/argocd/applications/three-tier-{dev,prod}.yaml` — ArgoCD Apps with `automated: { selfHeal: true }`
- `kubernetes/apps/three-tier/values-{dev,prod}.yaml` — env-specific config (dev auto-promotes, prod manual)
