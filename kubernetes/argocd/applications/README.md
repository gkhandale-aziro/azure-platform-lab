# ArgoCD Applications — drift detection only

Two ArgoCD Applications watch the three-tier app's Helm chart in this repo and report drift between Git and cluster state. **Sync is manual only** — there's no `automated` block in either application.

## Why this shape (and not full GitOps)

The lab uses a **hybrid CI/CD pattern** (pinned decision):
- **Jenkins** drives all deploys via `helm upgrade --set image.repository=... --set image.tag=...`
- **ArgoCD** monitors and surfaces "OutOfSync" when cluster ≠ Git

Because Jenkins overrides image refs via `--set` (not committed to Git), ArgoCD will report **OutOfSync** after every successful Jenkins deploy. That's by design — an operator reviewing the ArgoCD UI sees:

- Which environments are drifted (always, after a Jenkins deploy)
- What specifically differs (image repository / tag mostly)
- An audit trail of the divergence

For a pure GitOps flow, Jenkins would commit the new image tag to Git and ArgoCD would auto-sync. We're not doing that here.

## Apply

```bash
kubectl apply -f ~/azure-platform-lab/kubernetes/argocd/applications/three-tier-dev.yaml
kubectl apply -f ~/azure-platform-lab/kubernetes/argocd/applications/three-tier-prod.yaml

kubectl get applications -n argocd
```

You should see both Applications listed, status starts as `Unknown` then transitions to `OutOfSync` (since the deployed images aren't the chart defaults).

## Verify in the ArgoCD UI

```bash
# Get admin password
cat ~/.argocd-admin-password

# Port-forward
kubectl port-forward -n argocd svc/argocd-server 9443:80

# In laptop browser (with SSH tunnel): http://localhost:9443
# Login: admin / <password>
```

Both `three-tier-dev` and `three-tier-prod` Applications will appear on the dashboard. Click into one to see the resource tree (Deployment, Service, ConfigMap, etc.) and the diff between Git and live cluster state.

## Triggering a drift comparison

ArgoCD refreshes every ~3 minutes by default. To force-refresh:

- UI: click the Application → **Refresh** button
- CLI: `argocd app get three-tier-dev --refresh`

## What "drift" looks like in practice

After Jenkins runs the iter-5b pipeline, you'll see drift like:

```
LIVE:                                         GIT:
image: gskplatacrn73d5y.azurecr.io/three-     image: nginx:alpine
       tier/frontend:build-42
useConfigMapHTML: false                       useConfigMapHTML: true
```

This is the correct expected state — the operator confirms the drift matches a known Jenkins deploy and doesn't sync (which would revert to the placeholder).
