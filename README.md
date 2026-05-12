# Azure Platform Lab

End-to-end platform engineering lab on Azure: Terraform-provisioned AKS cluster running a real React + Node + PostgreSQL three-tier app, behind Istio, deployed by Jenkins, watched by ArgoCD for drift. Built in 5 reviewable iterations from a clean Free Trial subscription.

This is a learning artifact and an interview talking-point set, not a production reference. Lab-grade choices are called out inline.

---

## What this demonstrates

- **Infrastructure-as-Code** discipline — Terraform modules, remote state, no click-ops
- **AKS networking realities** — kubenet vs Azure CNI tradeoffs, NSG explicit-deny gotchas, cross-node pod traffic
- **Service mesh basics** — Istio Gateway + VirtualService, sidecar sizing, host-header-based routing
- **Hybrid CI/CD model** — Jenkins drives `helm upgrade`; ArgoCD watches for drift (no auto-sync)
- **Cost-aware engineering** — Free Trial constraints force real decisions: single cluster + namespaces, sidecar trimming, `az aks stop` when idle
- **Real app code** — React+Vite frontend, Node+Express backend, Jest/Vitest tests, multi-stage Dockerfiles

---

## Architecture — three layers

```
[ Layer 3: App         ] React + Node + Postgres in dev/prod namespaces
                          (Helm umbrella chart at kubernetes/apps/three-tier/)
                                       v   ^
[ Layer 2: Platform    ] Istio (mesh + ingress) | ArgoCD (drift) | Jenkins (CI)
                          (Helm-installed into istio-system, argocd, jenkins ns)
                                       v   ^
[ Layer 1: Infra       ] AKS cluster, ACR, VNet, Log Analytics, NSGs, tfstate SA
                          (Terraform in terraform/{bootstrap,live,modules}/)
                                       v
                                 Azure Subscription
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
| Cluster | AKS, kubenet, `Standard_D2s_v3` nodes (B-series blocked by Free Trial SKU policy in eastus2), public API + IP allowlist |
| Default node count | 1 (variables.tf default); bump to 2 in `terraform.tfvars` when running the full app + Jenkins footprint |
| Registry | Azure Container Registry, Basic SKU, RBAC-only auth (admin user disabled) |
| Mesh | Istio (mTLS PERMISSIVE, public ingress gateway, sidecar CPU trimmed to 10m on app pods) |
| GitOps | ArgoCD — **drift detection only**, no auto-sync (Jenkins is the deployer) |
| CI host | Jenkins on cluster, Kubernetes-plugin agents OR fat-image agents (see "Known cleanup items") |
| App | React 18 + Vite frontend, Node 20 + Express backend, postgres:15-alpine StatefulSet |
| Observability | Container Insights (OMS agent) into a shared Log Analytics workspace |

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
