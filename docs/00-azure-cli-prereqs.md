# Azure CLI Prerequisites

Run these commands once on your laptop **before** you touch any Terraform. Commands assume PowerShell on Windows. Adapt syntax for bash if needed (e.g. `$env:VAR=...` becomes `export VAR=...`).

## 1. Install tooling

| Tool       | Min version | Install                                     |
| ---------- | ----------- | ------------------------------------------- |
| Azure CLI  | 2.55+       | `winget install -e --id Microsoft.AzureCLI` |
| Terraform  | 1.5+        | `winget install -e --id Hashicorp.Terraform`|
| kubectl    | 1.28+       | `winget install -e --id Kubernetes.kubectl` |
| Helm       | 3.12+       | `winget install -e --id Helm.Helm`          |
| Git        | any         | `winget install -e --id Git.Git`            |

Verify:

```powershell
az version
terraform version
kubectl version --client
helm version
```

## 2. Log in and pick your subscription

```powershell
az login

# List all subs your account can see
az account list --output table

# Pick the Free Trial subscription (look for "Azure subscription 1" or similar)
az account set --subscription "<SUBSCRIPTION_ID>"

# Confirm
az account show --query "{Name:name, ID:id, TenantID:tenantId}" -o table
```

## 3. Register required resource providers

Providers are subscription-scoped and registration is idempotent. Run once.

```powershell
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.KeyVault
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.Insights
az provider register --namespace Microsoft.Compute
```

Wait for them all to finish (takes 1-3 min):

```powershell
az provider list --query "[?registrationState=='Registering'].namespace" -o table
# Re-run until the list is empty.
```

## 4. Sanity-check your vCPU quota

Free Trial caps you at **4 vCPUs per region per VM family**. We're using B-series (B2s = 2 vCPU). That ceiling is the single most important constraint in this lab.

```powershell
az vm list-usage --location eastus2 `
  --query "[?contains(name.value, 'standardBSFamily')].{Family:localName, Used:currentValue, Limit:limit}" `
  -o table
```

You should see `limit: 4` for `Standard BS Family vCPUs`. If not, you'll need to raise a quota request via the Azure portal (Subscriptions → Usage + quotas).

## 5. Capture your home public IP

Used as the AKS API allowlist later, and for SSH on the mgmt subnet.

```powershell
$myIp = (Invoke-WebRequest -Uri "https://api.ipify.org" -UseBasicParsing).Content
"$myIp/32"
```

Copy the `1.2.3.4/32` value into `terraform/live/terraform.tfvars` as `admin_ip_cidr`.

## 6. Create a Service Principal for Terraform

Terraform authenticates as a non-human identity. We give it Contributor at the subscription level — broad, but appropriate for a single-developer lab. (In a real org you would scope to a single resource group and add narrower roles like AcrPush, AKS Cluster Admin, etc.)

```powershell
$subId = (az account show --query id -o tsv)

az ad sp create-for-rbac `
  --name "sp-gskplat-terraform" `
  --role "Contributor" `
  --scopes "/subscriptions/$subId" `
  --years 1 `
  --output json | Tee-Object -FilePath sp-terraform.json
```

This prints (and saves to `sp-terraform.json`):

```json
{
  "appId":          "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "displayName":    "sp-gskplat-terraform",
  "password":       "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "tenant":         "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

**Treat `password` like a secret.** It's gitignored via `sp-*.json` in the root `.gitignore`, but don't paste it anywhere public.

### 6a. Export the SP credentials as env vars

The azurerm provider reads these automatically — no Terraform code change needed.

```powershell
$sp = Get-Content sp-terraform.json | ConvertFrom-Json

$env:ARM_CLIENT_ID       = $sp.appId
$env:ARM_CLIENT_SECRET   = $sp.password
$env:ARM_TENANT_ID       = $sp.tenant
$env:ARM_SUBSCRIPTION_ID = $subId
```

These env vars are session-scoped. To make them persist across PowerShell sessions, add them to your `$PROFILE`, or use a `.envrc` + direnv pattern.

### 6b. Verify Terraform can authenticate

```powershell
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap plan
```

If you see `Acquiring state lock... Plan: N to add` you're good. If you see `AuthorizationFailed`, the env vars aren't set in this shell.

## 7. Granting the SP extra roles you'll need later

These aren't needed for iteration 1 (bootstrap + network), but flagging now so you don't get blocked later:

| Role                              | Scope                | Why                                                              |
| --------------------------------- | -------------------- | ---------------------------------------------------------------- |
| `AcrPush` / `AcrPull`             | ACR resource         | Jenkins pushes images, AKS pulls them                            |
| `Azure Kubernetes Service Cluster Admin Role` | AKS cluster | kubectl admin from local machine                                 |
| `Key Vault Secrets User`          | Key Vault (optional) | If you add Key Vault CSI later                                   |

Terraform will assign most of these automatically when those modules land. The Contributor role from step 6 covers role assignment itself.

---

**Once steps 1-6 are green, you're ready to apply the bootstrap config.** See the root `README.md` for the run order.
