# Azure Platform Lab

End-to-end platform engineering lab on Azure: Terraform-provisioned AKS cluster running a real React + Node + PostgreSQL three-tier app, behind Istio, with **two parallel CI/CD systems** (Jenkins + GitHub Actions), **GitOps via ArgoCD**, and **progressive delivery via Argo Rollouts** with **Prometheus-driven analysis gates**.

This is a learning artifact and interview talking-point set, not a production reference. Lab-grade choices are called out inline.

---

## What this demonstrates

- **Infrastructure-as-Code** — Terraform modules, remote state, no click-ops
- **AKS networking realities** — kubenet, NSG explicit-deny gotchas, cross-node pod traffic
- **Service mesh** — Istio Gateway + VirtualService, sidecar sizing, host-header-based routing
- **Two CI/CD models in parallel:**
  - **Jenkins** — in-cluster, uses kaniko + helm directly (was iter 5; works inside the cluster, no kubeconfig export needed)
  - **GitHub Actions** — GitOps pattern: build images, commit image-tag changes to Git, let ArgoCD apply them
- **GitOps with ArgoCD auto-sync** — Git is the source of truth for deployments
- **Progressive delivery with Argo Rollouts** — blue/green deployment with preview Service, manual promote
- **Automated analysis gates** — Prometheus queries `istio_requests_total` for success rate before promotion
- **Container security** — Trivy CVE scanning (report mode), gitleaks secret scanning
- **Cost-aware engineering** — single cluster + namespaces, sidecar trimming, `az aks stop` when idle
- **Real app code** — React+Vite frontend, Node+Express backend, Jest/Vitest tests, multi-stage Dockerfiles, npm ci with locked deps

---

## Architecture — three layers

```
[ Layer 3: App + Delivery ] React + Node + Postgres in dev/prod namespaces
                            Helm umbrella chart (kubernetes/apps/three-tier/)
                            Frontend + Backend deployed as Argo Rollouts
                            (blue/green strategy, preview Service, Prometheus analysis)
                                       v   ^
[ Layer 2: Platform       ] Istio (mesh + ingress) | ArgoCD (auto-sync) | Argo Rollouts
                            Jenkins (CI option A) | Prometheus (metrics) | GitHub Actions (CI option B)
                                       v   ^
[ Layer 1: Infra          ] AKS cluster, ACR, VNet, Log Analytics, NSGs, tfstate SA
                            (Terraform in terraform/{bootstrap,live,modules}/)
                                       v
                                 Azure Subscription
```

## CI/CD flow (GitHub Actions + ArgoCD + Argo Rollouts)

```
Developer pushes to master
   ↓
GitHub Actions workflow (manual trigger via workflow_dispatch)
   ├─ CI checks (parallel): npm test + lint (backend, frontend), gitleaks secret scan
   ├─ Build & push images (parallel): docker buildx → ACR with GHA cache
   ├─ Trivy scan (parallel, report-only): SARIF + table reports uploaded as artifacts
   ├─ update-dev-tags: python3 edits values-dev.yaml → commit → push to master
   ↓
ArgoCD detects Git change on master (auto-sync enabled)
   ↓
ArgoCD applies the helm chart → cluster
   ↓
Argo Rollouts creates a "green" ReplicaSet alongside the live "blue"
   ↓
prePromotionAnalysis fires:
   Prometheus query: success_rate of istio_requests_total on frontend-preview Service
   Pass if result[0] >= 0.95 over 3 checks (30s interval)
   `or vector(1)` handles no-traffic case (returns 1.0 = 100% success)
   ↓
On success → BlueGreenPause: rollout waits for manual `kubectl argo rollouts promote`
On failure → auto-abort: green scaled down, blue keeps serving
   ↓
Manual promote → green becomes active, blue scales down after 30s
   ↓
GitHub manual approval gate (prod environment requires reviewer)
   ↓
update-prod-tags: same flow on values-prod.yaml → ArgoCD → prod cluster
```

### Request flow (when you hit the app from a browser)

```
laptop browser  -- http://dev.lvh.me:59999/
   |  (lvh.me public DNS resolves *.lvh.me to 127.0.0.1)
laptop:59999
   |  (SSH -L tunnel)
vm:9999
   |  (kubectl port-forward to istio-ingress Service)
istio-ingress LoadBalancer Service
   |
istio-ingress pod (Envoy)
   |  Host: dev.lvh.me matches VirtualService three-tier-dev
   |  /api/* rewrites to backend, / routes to frontend
frontend Service in dev ns -> frontend Pod (nginx + Istio sidecar)
```

---

## Stack at a glance

| Layer | Choice |
| --- | --- |
| Cloud | Azure (Free Trial, $200 credit, East US 2) |
| IaC | Terraform >= 1.5 / azurerm provider ~> 3.0 |
| Cluster | AKS, kubenet, `Standard_D2s_v3` nodes, public API + IP allowlist |
| Registry | Azure Container Registry, Basic SKU, RBAC-only auth |
| Mesh | Istio (mTLS PERMISSIVE, sidecar CPU trimmed to 10m on app pods) |
| **GitOps** | **ArgoCD with auto-sync** — Git is source of truth for image tags |
| **Progressive delivery** | **Argo Rollouts** — blue/green for frontend + backend, preview Service, scaleDownDelay 30s |
| **Analysis gates** | **Prometheus AnalysisTemplate** — queries `istio_requests_total` for success rate; gates blue/green promotion |
| CI option A | **Jenkins** on cluster, Kubernetes-plugin agents (kaniko + helm + trivy + gitleaks in one pod), npm/trivy DB cached on PVCs, kaniko ACR layer cache |
| CI option B | **GitHub Actions** workflow with manual `workflow_dispatch` trigger, GHA build cache, commits image tags to Git → triggers ArgoCD |
| Container scanning | Trivy (report-only mode in CI; reports uploaded as artifacts) |
| Secret scanning | gitleaks (gates the build) |
| App | React 18 + Vite frontend, Node 20 + Express backend, postgres:15-alpine StatefulSet |
| Observability | Container Insights (OMS agent), kube-prometheus-stack for AnalysisRun metrics |

---

## Repo layout

```text
azure-platform-lab/
├── terraform/
│   ├── bootstrap/             # one-time: tfstate Storage Account (local backend)
│   ├── modules/
│   │   ├── network/           # VNet, 3 subnets, NSGs (with AllowVnet + AllowLB rules)
│   │   ├── acr/               # Azure Container Registry
│   │   └── aks/               # AKS cluster
│   └── live/                  # composes the modules (remote backend in tfstate SA)
├── kubernetes/
│   ├── README.md              # platform install order
│   ├── istio/                 # istiod-values.yaml, gateway-values.yaml
│   ├── argocd/
│   │   ├── values.yaml        # ArgoCD chart values
│   │   └── applications/      # three-tier-{dev,prod}.yaml — drift-detection apps
│   ├── jenkins/
│   │   ├── values.yaml        # Jenkins chart values (single replica, 8Gi PVC)
│   │   ├── rbac.yaml          # ClusterRole + RoleBindings for the deployer SA
│   │   └── setup-acr-secret.md # one-time manual steps (ACR secret, job creation)
│   └── apps/
│       ├── namespaces/        # dev.yaml, prod.yaml (with istio-injection labels)
│       └── three-tier/        # umbrella Helm chart
│           ├── Chart.yaml
│           ├── values-dev.yaml / values-prod.yaml
│           ├── charts/
│           │   ├── frontend/  # nginx OR real React image (toggle via useConfigMapHTML)
│           │   ├── backend/   # http-echo OR real Node image (toggle via useEchoArgs)
│           │   └── database/  # Postgres StatefulSet + Secret + PVC
│           └── istio/         # Gateway + VirtualService for dev and prod
├── apps/                      # real application source (iter 5)
│   ├── backend/               # Node + Express, /health and /api/info, Jest tests
│   └── frontend/              # React + Vite, fetches /api/info, Vitest tests
├── pipelines/
│   └── Jenkinsfile            # multi-container Kubernetes-agent pipeline (this is the iter-5 design)
├── Jenkinsfile                # alternative single-agent pipeline (Copilot-assisted; see "Known cleanup items")
├── ci/jenkins/
│   ├── agent/Dockerfile       # fat-image Jenkins agent (alternative to multi-container)
│   ├── build-agent-image.sh
│   └── README.md
└── docs/
    ├── 00-azure-cli-prereqs.md       # PowerShell prereqs
    ├── 00-azure-cli-prereqs-linux.md # bash prereqs (Ubuntu/Debian)
    └── fresh-session-kickoff.md      # prompt template for resuming on a different machine
```

---

## Run order

Each iteration is a separate commit on `master`. Run them top-to-bottom from a clean Azure Free Trial.

### Iteration 0 — prereqs (one-time)

Read your OS's prereq doc and run every command in it. You need: Azure CLI, Terraform, kubectl, Helm, a logged-in `az`, an SP with **`Contributor` + `User Access Administrator`** at subscription scope (Contributor alone is not enough — see [feedback memory on RBAC gotchas](docs/00-azure-cli-prereqs-linux.md) section 7), and `ARM_*` env vars exported.

- Windows / PowerShell: [`docs/00-azure-cli-prereqs.md`](docs/00-azure-cli-prereqs.md)
- Linux / bash: [`docs/00-azure-cli-prereqs-linux.md`](docs/00-azure-cli-prereqs-linux.md)

### Iteration 1 — bootstrap + network

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # edit owner email
terraform init
terraform apply       # Plan: 4 to add (RG, SA, container, random_string)
terraform output backend_init_command_live   # save this command

cd ../live
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set admin_ip_cidr to YOUR /32

terraform init   # paste the command from `backend_init_command_live`
terraform apply       # Plan: 12 to add (RG, LAW, VNet, 3 subnets, 3 NSGs, 3 NSG assoc)
```

After iter 1: state SA, platform RG, Log Analytics, VNet/subnets/NSGs. **Cost < $1/mo.**

### Iteration 2 — ACR + AKS

Same `terraform/live/` directory; modules wired in. Re-run:

```bash
terraform apply       # Plan: ~5 new (ACR, AKS, AcrPull role, Cluster Admin role, random_string)
```

AKS provisioning takes ~10 min. After: ACR live, AKS cluster up, `az aks get-credentials …` (in tfoutput `kubeconfig_command`) populates kubectl.

### Iteration 3 — platform components (Helm, no Terraform)

```bash
# Istio (base + istiod + ingress gateway)
helm repo add istio https://istio-release.storage.googleapis.com/charts && helm repo update istio
helm install istio-base   istio/base    -n istio-system --create-namespace --wait
helm install istiod       istio/istiod  -n istio-system --values kubernetes/istio/istiod-values.yaml --wait
helm install istio-ingress istio/gateway -n istio-system --values kubernetes/istio/gateway-values.yaml --wait

# ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update argo
helm install argocd argo/argo-cd -n argocd --create-namespace --values kubernetes/argocd/values.yaml --wait

# Jenkins
helm repo add jenkins https://charts.jenkins.io && helm repo update jenkins
helm install jenkins jenkins/jenkins -n jenkins --create-namespace --values kubernetes/jenkins/values.yaml --wait --timeout 10m
```

After iter 3: the three platform tools are installed. The Istio ingress gateway has a public IP (`kubectl get svc -n istio-system istio-ingress`).

### Iteration 4 — three-tier app

```bash
# Namespaces with istio-injection label
kubectl apply -f kubernetes/apps/namespaces/dev.yaml
kubectl apply -f kubernetes/apps/namespaces/prod.yaml

# Istio Gateway (shared)
kubectl apply -f kubernetes/apps/three-tier/istio/gateway.yaml

# Build chart dependencies, deploy dev + prod
cd kubernetes/apps/three-tier
helm dependency update

helm upgrade --install three-tier . -n dev  --values values-dev.yaml  --wait --timeout 5m
helm upgrade --install three-tier . -n prod --values values-prod.yaml --wait --timeout 5m

# VirtualServices
kubectl apply -f istio/virtualservice-dev.yaml
kubectl apply -f istio/virtualservice-prod.yaml
```

After iter 4: app running in both namespaces with placeholder images (nginx + http-echo). The chart toggles to real images via `--set useConfigMapHTML=false --set useEchoArgs=false`.

### Iteration 5 — pipeline + drift detection

Wire Jenkins permissions and ACR creds:

```bash
kubectl apply -f kubernetes/jenkins/rbac.yaml

# ACR secret kaniko mounts to push images
source ~/.azure-lab.env   # ARM_CLIENT_ID etc.
kubectl create secret docker-registry acr-docker-config \
  -n jenkins \
  --docker-server=<your-acr>.azurecr.io \
  --docker-username="$ARM_CLIENT_ID" \
  --docker-password="$ARM_CLIENT_SECRET"
```

Register the ArgoCD Applications (drift detection):

```bash
kubectl apply -f kubernetes/argocd/applications/three-tier-dev.yaml
kubectl apply -f kubernetes/argocd/applications/three-tier-prod.yaml
```

**Then in the Jenkins UI** (port-forward + browser): create a Pipeline job pointing at `pipelines/Jenkinsfile`, **Build Now**. Full one-time setup is in [`kubernetes/jenkins/setup-acr-secret.md`](kubernetes/jenkins/setup-acr-secret.md).

After iter 5: Jenkins builds the real React/Node images, pushes to ACR, swaps the chart values, `helm upgrade`s dev+prod. ArgoCD reports OutOfSync (expected — Jenkins overrides image refs via `--set`, not committed back to Git).

---

### Iteration 6 — GitHub Actions (alternative CI) + GitOps deploy

In iter 5 Jenkins did the deploy directly (`helm upgrade` from inside the cluster). In iter 6 we switch to a GitOps model:

```bash
# Install Argo Rollouts controller + CLI plugin
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# kubectl plugin
curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x kubectl-argo-rollouts-linux-amd64
sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts

# Install Prometheus (lightweight, no grafana/alertmanager) for AnalysisTemplate
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.enabled=false --set alertmanager.enabled=false \
  --wait
```

Enable auto-sync on the ArgoCD Applications (was drift-only in iter 5). Then enable blue/green + analysis in `values-dev.yaml`:

```yaml
frontend:
  blueGreen:
    enabled: true
    autoPromotionEnabled: false
    analysis:
      enabled: true
backend:
  blueGreen:
    enabled: true
    autoPromotionEnabled: false
```

Set up GitHub repo secrets and trigger the workflow manually from the Actions tab.

| Secret | Value |
| --- | --- |
| `ACR_CLIENT_ID` | SP appId for ACR push |
| `ACR_CLIENT_SECRET` | SP password |

(No KUBECONFIG needed — GitHub Actions doesn't touch the cluster directly.)

### How a deploy flows in iter 6

1. GitHub Actions: build images → push to ACR → run `python3` to edit `values-dev.yaml` → commit → push to `master`
2. ArgoCD detects Git change → applies updated Helm chart → cluster has new Rollout spec
3. Argo Rollouts:
   - Sees new image tag in Rollout spec
   - Creates new "green" ReplicaSet (revision N+1)
   - `prePromotionAnalysis` fires: queries Prometheus for success rate
   - `or vector(1)` makes the query resilient to zero-traffic preview Services
   - If success rate ≥ 95% over 3 × 30s checks → `BlueGreenPause`
   - If success rate < 95% → auto-abort
4. Operator runs `kubectl argo rollouts get rollout frontend -n dev` to verify
5. Smoke test against `frontend-preview` Service:
   ```bash
   kubectl port-forward -n dev svc/frontend-preview 8081:80
   curl http://localhost:8081/
   ```
6. `kubectl argo rollouts promote frontend -n dev` → green becomes active, blue scales down after 30s
7. (For prod) GitHub Actions workflow proceeds to `update-prod-tags` job which is gated by GitHub Environment `prod` required reviewers

### Demo flow (after iter 6)

```bash
# 1. Trigger workflow on master
# Actions → "Three-Tier CI/CD" → Run workflow

# 2. Watch the rollout (green pod comes up, analysis runs)
kubectl argo rollouts get rollout frontend -n dev --watch

# 3. When status = Paused (BlueGreenPause), check the AnalysisRun
kubectl get analysisrun -n dev

# 4. Verify green works via preview Service
kubectl port-forward -n dev svc/frontend-preview 8081:80
curl http://localhost:8081/

# 5. Promote
kubectl argo rollouts promote frontend -n dev

# 6. Verify on live URL
curl -s "http://localhost:9999/api/info" -H "Host: dev.gskplat.local"
# Should now show the new build tag
```

### Rollback

```bash
# Instant rollback to previous revision (old blue still alive for 30s after promote)
kubectl argo rollouts undo frontend -n dev

# Or abort an in-progress green deployment
kubectl argo rollouts abort frontend -n dev
```

---

## What you learn (interview talking points)

Pick a few that match the role. Each has a one-liner answer ready to expand.

| Question | Anchor for your answer |
| --- | --- |
| Why two Terraform configs (bootstrap + live)? | Chicken-and-egg: Terraform needs a backend before you can use one. Bootstrap creates the state SA with a local backend; live uses the SA as remote backend. |
| Why kubenet not Azure CNI? | Free Trial constraint, simpler IP planning; kubenet keeps pods off the VNet (NAT via node IP). Tradeoff: cross-cluster pod-direct routing isn't possible. |
| Why Contributor + User Access Administrator on the SP? | Contributor lets the SP create resources but explicitly excludes `Microsoft.Authorization/*`. UAA adds the ability to create role assignments. Without UAA, iter 2's AcrPull + Cluster Admin role assignments fail. |
| What broke when you scaled AKS to 2 nodes? | Pod-to-pod cross-node traffic and LB health probes. Our explicit `DenyAllInboundExplicit` at priority 4000 overrode Azure's implicit allows at 65000/65001. Fix: add explicit `AllowVnetInbound` (1000) and `AllowAzureLoadBalancerInbound` (1100). |
| Why ArgoCD without auto-sync? | Hybrid CI/CD model. Jenkins is the deployer (it `helm upgrade --set image.tag=…`). ArgoCD's role is drift auditing — it shows "OutOfSync" after every Jenkins deploy, which is the point. Operators review divergence; they don't auto-fix. |
| Why mTLS PERMISSIVE not STRICT? | Permissive accepts both plaintext and mTLS. Lets you roll out sidecars gradually without breaking workloads that don't have one yet (e.g., the Postgres pod opts out via `sidecar.istio.io/inject: false`). Tighten to STRICT later with a PeerAuthentication policy. |
| Why single-cluster dev+prod? | Free Trial 4 vCPU per family quota — can't run a second cluster. In production you'd separate. Compensate here with namespace isolation + NSGs. |
| How did you debug the iter-4 deploy failure? | Pods stuck `Init:1/2` for 28 min. `describe pod` + `get events` showed scheduler `Insufficient cpu`. Per-sidecar 100m default was the culprit; trimmed to 10m with pod annotations (`sidecar.istio.io/proxyCPU`), opted Postgres out of injection entirely, scaled cluster to 2 nodes. |
| How do users hit the app from a browser? | Public LB IP if their network allows it; otherwise `lvh.me` (public DNS that resolves any subdomain to 127.0.0.1) over an SSH tunnel + kubectl port-forward. The Istio VirtualService matches on Host header (`dev.lvh.me` and `prod.lvh.me`). |
| Why two CI systems (Jenkins + GitHub Actions)? | Jenkins runs *inside* the cluster — kaniko, helm, trivy execute directly with cluster RBAC. No need to expose AKS API. GitHub Actions runs *outside* the cluster, so the GitOps pattern (commit values.yaml → ArgoCD applies) is the natural fit. Both work; production teams pick one based on whether they want self-hosted vs SaaS. |
| Why GitOps instead of Jenkins `helm upgrade --set`? | Auditability and rollback. Every deploy is a Git commit reviewable in `git log`. To rollback, `git revert <commit>` — ArgoCD reverts the cluster. With direct `helm --set`, the cluster diverges from Git silently. |
| Why blue/green not canary? | Blue/green is simpler to reason about: 100% of traffic is on one version or the other; no weighted routing complexity. Used for frontend + backend in this lab. For services where partial rollout makes sense (e.g., recommendation engines where 5% sample is meaningful), canary fits better. Argo Rollouts supports both. |
| How does the AnalysisTemplate work without traffic? | The Prometheus query for `istio_requests_total` returns an empty result if no requests have hit the preview Service yet. `reflect: slice index out of range` crashes the analyzer. Fix: append `or vector(1)` to the query so empty results return 1.0 (100% success). In production you'd add a separate "min-traffic" gate that fails fast if the preview gets zero requests. |
| What happens on analysis failure? | The rollout auto-aborts: green ReplicaSet scaled down to 0, blue keeps serving. The Rollout enters Degraded state. To retry: `kubectl argo rollouts retry rollout frontend -n dev` (re-runs the same revision) or fix the underlying issue and push a new image (creates a new revision). |
| What's the kubectl `restart` vs `retry` vs `undo`? | `restart` triggers a rolling restart of pods (no spec change). `retry` re-runs an aborted/failed rollout with the same spec. `undo` reverts to the previous revision. `promote` advances a paused rollout to active. `abort` cancels an in-progress rollout, scaling green down. |

---

## Cost expectations (Free Trial: $200 / 30 days)

| State | Approx. monthly |
| --- | --- |
| Iter 1 only (network + LAW, no compute) | < $1 |
| Iter 2 single node 24/7 | ~$75 (1× D2s_v3 + ACR + LB) |
| Iter 4 two nodes 24/7 | ~$140 |
| Two nodes + `az aks stop` overnight/weekends | ~$35–40 |
| Full lab idle on weekend | < $5 (just ACR + LAW + state SA) |

A D2s_v3 node burns ~$0.10/hr; two of them 24/7 is your biggest expense. **Stop the cluster when not in use** — control plane stays free:

```bash
az aks stop  -g gskplat-rg-platform -n gskplat-aks-shared
az aks start -g gskplat-rg-platform -n gskplat-aks-shared
```

---

## vCPU quota — the binding constraint

Free Trial: **4 vCPU per region per VM family.**

- 1× D2s_v3 = 2 vCPU. Half the cap.
- 2× D2s_v3 = 4 vCPU. At the cap. Needed once you've layered Istio + ArgoCD + Jenkins + the app — sidecar CPU requests pile up.
- You cannot run a separate prod cluster simultaneously.

**SKU policy gotcha:** Free Trial subscriptions in some regions block B-series and many others via a SKU allowlist that's separate from quota. Quota says "how much you can use"; SKU policy says "what SKUs you're allowed to use at all." Check the allowlist with `az vm list-skus --location eastus2 --resource-type virtualMachines -o table` if you hit `VM size X is not allowed in your subscription`.

---

## Operating the lab

### Browser access via SSH tunnel

```bash
# On laptop (PowerShell)
ssh -L 50080:localhost:8080 `
    -L 50090:localhost:9090 `
    -L 58443:localhost:8443 `
    -L 58444:localhost:8444 `
    -L 59999:localhost:9999 `
    aziro@<vm-ip>
```

Inside that SSH session, start the relevant port-forward(s):

```bash
nohup kubectl port-forward -n istio-system  svc/istio-ingress         9999:80   > /dev/null 2>&1 &
nohup kubectl port-forward -n argocd        svc/argocd-server         8443:80   > /dev/null 2>&1 &
nohup kubectl port-forward -n jenkins       svc/jenkins               8080:8080 > /dev/null 2>&1 &
nohup helm dashboard --port=9090 --no-browser --no-analytics                    > /dev/null 2>&1 &
nohup kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard 8444:443 > /dev/null 2>&1 &
```

Then on the laptop:

| URL | UI |
| --- | --- |
| http://dev.lvh.me:59999/ | dev frontend |
| http://prod.lvh.me:59999/ | prod frontend |
| http://localhost:50080/ | Jenkins |
| http://localhost:50090/ | Helm Dashboard |
| http://localhost:58443/ | ArgoCD |
| https://localhost:58444/ | Kubernetes Dashboard (HTTPS — accept self-signed cert) |

UI passwords/tokens are kept in `~/.argocd-admin-password`, `~/.jenkins-admin-password`, `~/.k8s-dash-token` on the VM (chmod 600).

### Common diagnostics

```bash
kubectl top nodes                                  # CPU/memory usage
kubectl describe node | grep -A 8 "Allocated"      # CPU/memory REQUESTS (scheduler's view)
kubectl get pods -A --field-selector=status.phase!=Running   # anything not happy
kubectl get events -A --sort-by='.lastTimestamp' | tail -30  # recent cluster events
```

---

## Tagging convention

Every resource carries:

| Tag | Value |
| --- | --- |
| `Environment` | `shared` (cluster-wide) — namespaces carry their own `env` label |
| `Project` | `azure-platform-lab` |
| `Owner` | your email |
| `ManagedBy` | `terraform` |

Each module adds a `Component` tag (`bootstrap`, `network`, `acr`, `aks`).

---

## Known cleanup items / TODOs

Be honest — these are open as of the current state. Don't claim production-quality without fixing them.

1. **Two Jenkinsfiles** — `pipelines/Jenkinsfile` (the iter-5 multi-container Kubernetes-plugin design) and `/Jenkinsfile` at repo root (a later Copilot-assisted single-agent version). Pick one, delete the other. The root one has stages that swallow failures with `|| true` — that needs fixing if kept.
2. **Two Jenkins agent patterns** — `pipelines/Jenkinsfile` uses a multi-container agent Pod (one container per tool); `ci/jenkins/agent/Dockerfile` builds a single fat image with all tools. Choose one architecturally.
3. **Hardcoded placeholder DB passwords** — `kubernetes/apps/three-tier/values-{dev,prod}.yaml` ship with `*-superSecret-change-me`. Wire Azure Key Vault + CSI Secret Store Driver before any non-lab use.
4. **ACR name hardcoded in pipeline + docs** — should be a Jenkins build parameter or sourced from a secret.
5. **ArgoCD `applicationSet.enabled: false` value didn't take** — the controller pod still came up. Likely a key-name change in the newer chart; needs investigation.
6. **Network module's NSG explicit-deny is verbose** — the explicit deny + AllowVnet + AllowLB rules technically duplicate Azure's implicit allows; they're there for audit clarity but trip a learner up (see iter-4 NSG fix story). Document or simplify.
7. **OIDC-based workload identity for ACR push** would be cleaner than mounting an SP secret — explore in a follow-up.

---

## Teardown

When you're done for the day:

```bash
az aks stop -g gskplat-rg-platform -n gskplat-aks-shared
```

When you're done for good:

```bash
cd terraform/live
terraform destroy

cd ../bootstrap
terraform destroy
```

Then in the portal, delete `sp-gskplat-terraform` from Azure AD if you don't plan to reuse it.

---

## References

- [`docs/00-azure-cli-prereqs.md`](docs/00-azure-cli-prereqs.md) — Windows / PowerShell setup
- [`docs/00-azure-cli-prereqs-linux.md`](docs/00-azure-cli-prereqs-linux.md) — Linux / bash setup
- [`docs/fresh-session-kickoff.md`](docs/fresh-session-kickoff.md) — prompt template if you ever start a fresh chat about this repo on a different machine
- [`kubernetes/argocd/applications/README.md`](kubernetes/argocd/applications/README.md) — why ArgoCD shows OutOfSync after every Jenkins deploy
- [`kubernetes/jenkins/setup-acr-secret.md`](kubernetes/jenkins/setup-acr-secret.md) — one-time Jenkins UI steps
