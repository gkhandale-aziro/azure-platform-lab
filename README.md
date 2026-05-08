# Azure Platform Lab

Hands-on lab to deploy a 3-tier app (React + Node/Express + PostgreSQL) on **AKS** with **Istio**, **ArgoCD** (drift detection), **Helm**, and **Jenkins** CI/CD. Two namespaces — `dev` and `prod` — share a single cluster.

## Stack at a glance

| Layer | Choice |
| --- | --- |
| Cloud | Azure (Free Trial, $200 credit, East US 2) |
| IaC | Terraform 1.5+ / azurerm provider ~> 3.0 |
| Cluster | AKS, kubenet, 2x Standard_B2s, public API + IP allowlist |
| Registry | Azure Container Registry (Basic SKU) |
| GitOps | ArgoCD (drift detection); Jenkins drives all deploys via `helm upgrade` |
| Mesh | Istio (mTLS PERMISSIVE, ingress gateway) |
| App | React frontend, Node/Express API, PostgreSQL |
| Observability | Azure Monitor for containers → shared Log Analytics workspace |

## Repo layout

```text
azure-platform-lab/
├── terraform/
│   ├── bootstrap/                # one-time: creates the tfstate Storage Account
│   ├── modules/
│   │   └── network/              # VNet, 3 subnets, NSGs (default-deny)
│   └── live/                     # the cluster — composes all modules
│       ├── main.tf
│       ├── variables.tf
│       ├── backend.tf            # azurerm remote backend (partial config)
│       └── terraform.tfvars      # gitignored — your real values
├── kubernetes/                   # iteration 3+: istio, argocd, jenkins, apps
├── pipelines/                    # iteration 5: Jenkinsfile, shared library
└── docs/
    ├── 00-azure-cli-prereqs.md       # PowerShell prereqs
    └── 00-azure-cli-prereqs-linux.md # bash prereqs (Ubuntu/Debian)
```

## Run order

### Iteration 1 — what's in this commit

1. **Read** the prereq doc for your OS and run every command in it. You need an SP, env vars, and a registered subscription before Terraform will work.
   - Windows / PowerShell: [`docs/00-azure-cli-prereqs.md`](docs/00-azure-cli-prereqs.md)
   - Linux / bash (Ubuntu/Debian): [`docs/00-azure-cli-prereqs-linux.md`](docs/00-azure-cli-prereqs-linux.md)

2. **Bootstrap** the state Storage Account (uses local backend — chicken-and-egg solved):

   ```bash
   cd terraform/bootstrap
   cp terraform.tfvars.example terraform.tfvars
   # edit terraform.tfvars (set owner email)
   terraform init
   terraform plan
   terraform apply
   terraform output backend_init_command_live   # copy this command, you'll need it next
   ```

3. **Apply the live config** — VNet + subnets + NSGs + Log Analytics workspace + the platform Resource Group:

   ```bash
   cd ../live
   cp terraform.tfvars.example terraform.tfvars
   # edit terraform.tfvars: set admin_ip_cidr to YOUR /32 (curl https://api.ipify.org)

   # Paste the command from step 2's output, e.g.:
   terraform init \
     -backend-config="resource_group_name=gskplat-rg-tfstate" \
     -backend-config="storage_account_name=gskplattfstateab12cd" \
     -backend-config="container_name=tfstate" \
     -backend-config="key=live.terraform.tfstate"

   terraform plan
   terraform apply
   ```

After iteration 1 you have: state storage, a platform RG, a shared LAW, a VNet with 3 subnets, and 3 NSGs. **Nothing compute-bound is running yet — monthly cost is < $1.**

### Future iterations

| # | Adds | Roughly |
| --- | --- | --- |
| 2 | `modules/acr` + `modules/aks` + wire into `live` | AKS cluster up, ACR live, kubectl works |
| 3 | `kubernetes/istio` + `kubernetes/argocd` + `kubernetes/jenkins` | Platform pods on cluster |
| 4 | `kubernetes/apps/three-tier/` Helm charts | App deployed manually to dev ns |
| 5 | `pipelines/Jenkinsfile` | Full CI/CD: test → lint → secret scan → build → trivy → deploy dev → e2e → deploy prod |

## Cost expectations (Free Trial: $200 / 30 days)

| State | Approx. monthly |
| --- | --- |
| Iteration 1 only (this commit) | < $1 |
| Iteration 2 + cluster running 24/7 | ~$60 |
| Iteration 2 + cluster scaled to 0 most of the time | ~$10–15 |
| Full lab running 24/7 | ~$80–100 |

The single biggest lever is **scaling the AKS node pool to zero when you're not actively using it.** A 2-node B2s cluster burns ~$0.083/hr; left running 24/7 that's ~$60/mo. Use `az aks stop` / `az aks start` between sessions.

## vCPU quota — the binding constraint

Free Trial: **4 vCPU per region per VM family.**

- 2x B2s = 4 vCPU = **at the cap**.
- You cannot run a separate prod cluster simultaneously. That's why dev/prod are namespaces, not separate clusters.

If you upgrade to Pay-as-you-go, the default is 10 vCPU (raisable on request).

## Tagging convention

Every resource carries:

| Tag | Value |
| --- | --- |
| `Environment` | `shared` (cluster-wide) — namespaces carry their own labels |
| `Project` | `azure-platform-lab` |
| `Owner` | your email |
| `ManagedBy` | `terraform` |

Modules add a `Component` tag (`bootstrap`, `network`, `aks`, etc.) on top.

## Teardown

When you're done for the day:

```bash
# Cheapest: just stop the cluster (control plane stays free, nodes stop billing)
az aks stop -g gskplat-rg-platform -n <cluster-name>
```

When you're done for good:

```bash
cd terraform/live
terraform destroy

cd ../bootstrap
terraform destroy
```

Then in the portal, delete `sp-gskplat-terraform` from Azure AD if you don't plan to reuse it.
