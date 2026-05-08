# Fresh Claude session — kickoff prompt

Paste the block below into a new Claude conversation when memory isn't loaded (e.g. running Claude on a different machine, or working in a different project directory). It re-establishes everything in one shot.

Update the **Current state** line each time you finish an iteration so the next session knows where to resume.

---

```
I'm Gopal, Senior DevOps Engineer (6.6y AWS-primary, CKA + AWS SAA),
prepping for a Platform Engineer interview and ramping up on Azure.
Working on a hands-on lab on Ubuntu VM (via SSH from my laptop).

GOAL: Deploy a 3-tier app (React + Node/Express + PostgreSQL) on AKS
with Istio + Helm + ArgoCD (drift detection only) + Jenkins CI/CD.
Two namespaces (dev, prod) on the same cluster.

Pinned decisions — don't re-ask:
- Naming prefix: gskplat
- Region: eastus2
- Subscription: Azure Free Trial ($200, hard cap of 4 vCPU per region per family)
- VM size: Standard_D2s_v3 (B-series is policy-blocked in this trial; D2s_v3 is the cheapest allowed amd64 SKU)
- Node count: 1 (single-node lab; bump to 2 within 4-vCPU cap if HA needed)
- AKS network plugin: kubenet (NOT Azure CNI)
- AKS API server: public, IP-allowlisted to my home /32
- Single cluster, dev and prod are namespaces (NOT separate clusters)
- Tags on every resource: Environment, Project, Owner, ManagedBy
- Terraform >= 1.5, azurerm provider ~> 3.0
- CICD pattern: HYBRID — Jenkins drives all deploys via `helm upgrade`;
  ArgoCD installed for drift detection only (NOT GitOps pull model)

Iteration plan:
1. Bootstrap (tfstate SA) + network module + live composition + az CLI prereq doc
2. ACR module + AKS module wired into live/
3. K8s manifests: Istio + ArgoCD + Jenkins on cluster
4. Helm charts for 3-tier app + values-dev.yaml + values-prod.yaml
5. Jenkinsfile: unit test → lint → secret scan → quality gate → docker build →
   trivy scan → deploy dev → e2e tests → deploy prod

Repo: https://github.com/<your-username>/azure-platform-lab
Working dir on VM: ~/azure-platform-lab
OS on VM: Ubuntu (bash, apt). Earlier docs/00-azure-cli-prereqs.md is PowerShell;
docs/00-azure-cli-prereqs-linux.md is the bash version I follow.

Coding standards:
- Use locals for repeated values
- terraform.tfvars gitignored, *.tfvars.example committed
- Modules under terraform/modules/ (each adds Component=<module-name> tag), environments composed under terraform/live/
- README run-order kept up to date
- Don't introduce abstractions/features I didn't ask for

Current state: iter 1 + iter 2 applied. Iter 1: tfstate SA + RG + LAW + VNet + 3 subnets + 3 NSGs. Iter 2: ACR (Basic) + AKS (1× D2s_v3, K8s 1.34, kubenet, public API allowlisted) + role assignments (kubelet→AcrPull, SP→Cluster Admin). SP has Contributor + User Access Administrator at sub scope. Cluster reachable via `az aks get-credentials -g gskplat-rg-platform -n gskplat-aks-shared`.

Next: <STATE WHAT YOU WANT — e.g. "generate iter 2: ACR + AKS modules">
```

---

## How to use it on the VM

```bash
cat ~/azure-platform-lab/docs/fresh-session-kickoff.md
# Copy the fenced block, edit the last line, paste into new Claude session.
```

## What to update before pasting

- **Repo URL** — replace `<your-username>` with your actual GitHub handle
- **Current state** — change to reflect the last iteration you finished
- **Next** — replace the placeholder with what you want done

That's it. Everything else is stable across iterations.
