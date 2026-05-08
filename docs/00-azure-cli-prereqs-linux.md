# Azure CLI Prerequisites — Linux (Ubuntu/Debian)

Bash equivalent of `00-azure-cli-prereqs.md`. Run these on your Ubuntu VM after you've SSHed in.

## 1. Install tooling

```bash
sudo apt-get update
sudo apt-get install -y curl gnupg lsb-release software-properties-common ca-certificates jq git
```

### Azure CLI
```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

### Terraform (HashiCorp apt repo)
```bash
wget -O- https://apt.releases.hashicorp.com/gpg \
  | gpg --dearmor \
  | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt-get update && sudo apt-get install -y terraform
```

### kubectl
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
```

### Helm
```bash
curl https://baltocdn.com/helm/signing.asc \
  | gpg --dearmor \
  | sudo tee /usr/share/keyrings/helm.gpg > /dev/null

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" \
  | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list

sudo apt-get update && sudo apt-get install -y helm
```

### Verify
```bash
az version
terraform version
kubectl version --client
helm version
git --version
```

## 2. Log in & set subscription

On a headless VM you must use device code (no browser):

```bash
az login --use-device-code
# Open the printed URL on your laptop, paste the code

az account list --output table
az account set --subscription "<SUBSCRIPTION_ID>"
az account show --query "{Name:name, ID:id, TenantID:tenantId}" -o table
```

## 3. Register providers (idempotent)

```bash
for p in Microsoft.ContainerService Microsoft.ContainerRegistry \
         Microsoft.Storage Microsoft.Network Microsoft.KeyVault \
         Microsoft.OperationalInsights Microsoft.Insights Microsoft.Compute; do
  az provider register --namespace "$p"
done

# Wait until the list is empty (1-3 min):
az provider list --query "[?registrationState=='Registering'].namespace" -o table
```

## 4. vCPU quota check

```bash
az vm list-usage --location eastus2 \
  --query "[?contains(name.value,'standardBSFamily')].{Family:localName,Used:currentValue,Limit:limit}" \
  -o table
# Expect Limit = 4 for Standard BS Family vCPUs
```

## 5. Capture the IP for the AKS allowlist

The `admin_ip_cidr` variable should be **whichever public IP will run `kubectl`** against the cluster. Two common choices:

```bash
# Option A — the VM itself (if you'll run kubectl from this VM)
VM_IP=$(curl -s https://api.ipify.org)
echo "${VM_IP}/32"

# Option B — your laptop (if you'll run kubectl from your laptop too)
# Run on the laptop: curl https://api.ipify.org
# Or allow both as a comma-separated list later in the AKS module.
```

For iteration 1 only NSGs use this value (mgmt subnet SSH). The AKS API allowlist is wired up in iteration 2.

## 6. Create the Service Principal for Terraform

```bash
SUB_ID=$(az account show --query id -o tsv)

az ad sp create-for-rbac \
  --name "sp-gskplat-terraform" \
  --role "Contributor" \
  --scopes "/subscriptions/$SUB_ID" \
  --years 1 \
  --output json | tee sp-terraform.json
```

`sp-terraform.json` contains a secret. It's gitignored via `sp-*.json`. Don't paste the password anywhere public.

### 6a. Export credentials (current shell)

```bash
export ARM_CLIENT_ID=$(jq -r .appId       sp-terraform.json)
export ARM_CLIENT_SECRET=$(jq -r .password sp-terraform.json)
export ARM_TENANT_ID=$(jq -r .tenant       sp-terraform.json)
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

### 6b. Persist across SSH sessions

Add to `~/.bashrc` (or better, a separate file you `source` before working):

```bash
cat >> ~/.bashrc <<EOF

# Azure Platform Lab — Terraform SP creds
export ARM_CLIENT_ID="$(jq -r .appId sp-terraform.json)"
export ARM_CLIENT_SECRET="$(jq -r .password sp-terraform.json)"
export ARM_TENANT_ID="$(jq -r .tenant sp-terraform.json)"
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
EOF
```

### 6c. Verify Terraform can authenticate

```bash
cd ~/azure-platform-lab/terraform/bootstrap
terraform init
terraform plan   # should show "Plan: 3 to add"
```

If you see `AuthorizationFailed`, the env vars aren't set in this shell — re-run 6a or `source ~/.bashrc`.

## 7. Future SP roles you'll need (flagged for later)

| Role | Scope | Why |
|------|-------|-----|
| `AcrPush` / `AcrPull` | ACR resource | Jenkins pushes images, AKS pulls |
| `Azure Kubernetes Service Cluster Admin Role` | AKS cluster | kubectl admin from outside |

Terraform will assign these in iteration 2 — Contributor at sub level is enough to delegate them.
