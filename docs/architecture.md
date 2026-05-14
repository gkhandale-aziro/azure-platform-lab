# Architecture

ASCII diagrams checked into source. For a polished version, paste these into [Excalidraw](https://excalidraw.com/) or [diagrams.net](https://app.diagrams.net/).

---

## High-level: 3 layers

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Layer 3 — Application (Helm umbrella chart: kubernetes/apps/three-tier/) │
│                                                                          │
│   ┌──────────┐    ┌──────────┐    ┌──────────────┐                       │
│   │ frontend │    │ backend  │    │  database    │                       │
│   │ Rollout  │───▶│ Rollout  │───▶│ StatefulSet  │                       │
│   │ (B/G)    │    │ (B/G)    │    │ (Postgres)   │                       │
│   └──────────┘    └──────────┘    └──────────────┘                       │
│        │              │                                                  │
│   ┌────┴────┐    ┌────┴────┐                                             │
│   │ active  │    │ active  │   ◄── Services. Active serves prod traffic, │
│   │ preview │    │ preview │       Preview lets you smoke-test the green │
│   └─────────┘    └─────────┘       version before Argo Rollouts promotes │
│                                                                          │
│   Deployed independently to: dev ns + prod ns                            │
└──────────────────────────────────────────────────────────────────────────┘
                              ▲
                              │ helm chart applied by ArgoCD on Git change
                              │
┌──────────────────────────────────────────────────────────────────────────┐
│ Layer 2 — Platform                                                       │
│                                                                          │
│   ┌──────────┐  ┌──────────┐  ┌──────────────┐  ┌─────────────────────┐  │
│   │  Istio   │  │ ArgoCD   │  │ Argo Rollouts│  │  Prometheus + Grafana│ │
│   │  (mesh + │  │ (sync    │  │ (B/G + Canary│  │  (metrics for       │  │
│   │  ingress)│  │  Git→k8s)│  │  controller) │  │  analysis gates)    │  │
│   └──────────┘  └──────────┘  └──────────────┘  └─────────────────────┘  │
│                                                                          │
│   ┌──────────┐  ┌────────────────┐                                       │
│   │ Jenkins  │  │ GitHub Actions │  ◄── Two parallel CI patterns         │
│   │ (in-     │  │ (outside, GH-  │      Jenkins: helm direct from cluster│
│   │  cluster)│  │  hosted runner)│      GHA: commit to Git → ArgoCD      │
│   └──────────┘  └────────────────┘                                       │
└──────────────────────────────────────────────────────────────────────────┘
                              ▲
                              │ kubeconfig
                              │
┌──────────────────────────────────────────────────────────────────────────┐
│ Layer 1 — Infrastructure (Terraform: terraform/{bootstrap,live,modules}) │
│                                                                          │
│   AKS cluster (kubenet, 2× D2s_v3)                                       │
│   ACR (Basic, RBAC-only)                                                 │
│   VNet (10.0.0.0/16): snet-aks, snet-apps, snet-mgmt                     │
│   NSGs (default-deny + explicit AllowVnet/AllowLB)                       │
│   Log Analytics Workspace (Container Insights)                           │
│   Storage Account (tfstate backend)                                      │
└──────────────────────────────────────────────────────────────────────────┘
                              ▲
                              │
                       Azure Subscription
                       (Free Trial, eastus2)
```

---

## CI/CD flow (GitHub Actions + ArgoCD + Argo Rollouts)

```
Developer pushes commit to feature branch
                  │
                  ▼  (workflow_dispatch manual trigger; OR PR after branch protection)
GitHub Actions workflow
  │
  ├── resolve-tag ────────────────► tag = sha-abc1234 (git short SHA, immutable)
  │
  ├── backend-ci, frontend-ci, secret-scan  ─── parallel ───┐
  │                                                         │
  │   npm test + lint                                       │
  │   gitleaks for committed secrets                        │
  │                                                         │
  ├── build-backend, build-frontend ─── parallel ────────── ▼
  │                                                         │
  │   docker buildx → ACR :sha-abc1234, :latest             │
  │   GHA cache (type=gha) to speed subsequent builds       │
  │                                                         │
  ├── trivy-scan (matrix backend/frontend) ─── parallel ──  ▼
  │                                                         │
  │   Scan ACR images, report-only (exit-code 0)            │
  │   Upload trivy-{image}.txt as workflow artifact         │
  │                                                         │
  ├── update-dev-tags                                       │
  │                                                         │
  │   Python: edit values-dev.yaml                          │
  │   - frontend.image.tag: sha-abc1234                     │
  │   - backend.image.tag: sha-abc1234                      │
  │   - backend.env.APP_VERSION: sha-abc1234                │
  │   Git commit + push to master                           │
  │                                                         │
  │           ┌─────────────────────────────────────┐       │
  │           │ ArgoCD detects Git change           │       │
  │           │ → applies updated Helm chart        │       │
  │           │ → Rollout spec gets new image tag   │       │
  │           └─────────────────────────────────────┘       │
  │                                                         │
  │           ┌─────────────────────────────────────┐       │
  │           │ Argo Rollouts:                      │       │
  │           │  1. Create green ReplicaSet         │       │
  │           │  2. Run prePromotionAnalysis        │       │
  │           │     Gate 1: min-traffic >= 1 req/s  │       │
  │           │     Gate 2: success-rate >= 95%     │       │
  │           │  3. On pass: auto-promote (dev)     │       │
  │           │  4. On fail: abort, green killed    │       │
  │           └─────────────────────────────────────┘       │
  │                                                         │
  ├── approve-prod (GitHub Environment, required reviewer)  ▼
  │                                                         │
  │   Pause — wait for human click                          │
  │                                                         │
  ├── update-prod-tags                                      │
  │                                                         │
  │   Same SHA as dev → values-prod.yaml                    │
  │   Git commit + push                                     │
  │                                                         │
  │           ┌─────────────────────────────────────┐       │
  │           │ Same flow as dev, but:              │       │
  │           │  - autoPromotionEnabled: false      │       │
  │           │  - Operator manually promotes       │       │
  │           │  - kubectl argo rollouts promote    │       │
  │           └─────────────────────────────────────┘       │
  ▼
Done
```

---

## Request flow (user → app)

```
laptop browser
   │
   │  http://dev.lvh.me:59999/
   │  (lvh.me public DNS resolves *.lvh.me to 127.0.0.1)
   ▼
laptop:59999
   │
   │  SSH LocalForward via `ssh azurelab` config
   ▼
vm:9999
   │
   │  kubectl port-forward to istio-ingress Service
   ▼
istio-ingress LoadBalancer Service (k8s)
   │
   ▼
istio-ingress pod (Envoy)
   │
   │  Match VirtualService by Host header:
   │   - dev.lvh.me / dev.gskplat.local → three-tier-dev VS
   │   - prod.lvh.me / prod.gskplat.local → three-tier-prod VS
   │
   │  Route by URI prefix:
   │   - /api/* → backend.<ns>.svc.cluster.local:5678
   │   - /     → frontend.<ns>.svc.cluster.local:80
   ▼
Service (active or preview, picked by Argo Rollouts)
   │
   ▼
Pod (nginx for frontend, node for backend) + istio-proxy sidecar
   │
   │  Sidecar emits istio_requests_total → Prometheus
   │  Prometheus → AnalysisTemplate (during rollouts) + Grafana dashboards
   ▼
Response
```

---

## Observability flow

```
┌─────────────────────┐
│  App pod (frontend, │
│  backend, database) │
│                     │
│  ┌───────────────┐  │
│  │ istio-proxy   │──┼──► /stats/prometheus on :15090
│  │ (sidecar)     │  │
│  └───────────────┘  │
└─────────────────────┘
            │
            │  PodMonitor envoy-stats-monitor scrapes every 15s
            ▼
   ┌─────────────────────┐
   │  Prometheus         │
   │  (kube-prom-stack)  │
   └─────────────────────┘
            │
            ├──► AnalysisTemplate queries
            │    (during Argo Rollouts pre-promotion)
            │
            └──► Grafana dashboards (Istio Service, Workload, Mesh)
                 http://localhost:53000/
```

---

## Two CI/CD patterns side-by-side

| Aspect | Jenkins (iter 5) | GitHub Actions (iter 6) |
|---|---|---|
| **Where it runs** | Inside the cluster | Outside (GH-hosted) |
| **Image build** | kaniko (rootless, no Docker daemon) | docker buildx + GHA cache |
| **Deploy method** | helm upgrade directly | Commit values.yaml to Git |
| **Cluster access** | ServiceAccount + RBAC | None — never touches cluster |
| **GitOps** | No (cluster diverges from Git silently) | Yes (Git = source of truth) |
| **Rollback** | helm rollback + tag swap | git revert |
| **Audit trail** | Jenkins build logs | Git commit history + Actions logs |
| **Best for** | On-prem, self-hosted clusters, secrets stay in cluster | Cloud-managed clusters, multi-team, audit-heavy environments |
```
