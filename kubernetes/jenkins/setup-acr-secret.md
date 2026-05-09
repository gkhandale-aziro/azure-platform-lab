# Jenkins setup — manual one-time steps

Most of the Jenkins infra is in code (`kubernetes/jenkins/values.yaml` for the chart, `kubernetes/jenkins/rbac.yaml` for permissions, `pipelines/Jenkinsfile` for the pipeline). Two things need a human in the loop the first time:

1. Create the ACR docker-config secret in the `jenkins` namespace (kaniko mounts this to push images)
2. Create the Pipeline job in the Jenkins UI pointing at this repo

After that, every push to `master` (once you wire a webhook or trigger) runs the full pipeline.

---

## 1. Apply the RBAC

```bash
kubectl apply -f ~/azure-platform-lab/kubernetes/jenkins/rbac.yaml
```

Verify:

```bash
kubectl get rolebinding -n dev jenkins-deployer-dev
kubectl get rolebinding -n prod jenkins-deployer-prod
```

## 2. Create the ACR docker-config secret

The pipeline's kaniko container mounts a Kubernetes secret named `acr-docker-config` containing a `.dockerconfigjson` that authenticates to the ACR.

The Terraform SP already has `Contributor` at subscription scope, which includes ACR push. Reuse those creds:

```bash
# Make sure you've sourced your env file so ARM_CLIENT_ID / ARM_CLIENT_SECRET are set
source ~/.azure-lab.env

# Create the secret in jenkins ns
kubectl create secret docker-registry acr-docker-config \
  --namespace jenkins \
  --docker-server=gskplatacrn73d5y.azurecr.io \
  --docker-username="$ARM_CLIENT_ID" \
  --docker-password="$ARM_CLIENT_SECRET"
```

Verify (without printing the password):

```bash
kubectl get secret acr-docker-config -n jenkins -o jsonpath='{.type}{"\n"}'
# Should print: kubernetes.io/dockerconfigjson
```

> **Rotation note:** when you rotate the SP secret (via `az ad sp credential reset`), this Kubernetes secret must be recreated. Easy `kubectl delete secret acr-docker-config -n jenkins && kubectl create secret …` cycle.

## 3. Create the Jenkins pipeline job

a. Get the admin password:

```bash
cat ~/.jenkins-admin-password
```

b. Open Jenkins (port-forward + SSH tunnel to your laptop):

```bash
# On VM
kubectl port-forward -n jenkins svc/jenkins 8080:8080

# On laptop (separate terminal)
ssh -L 8080:localhost:8080 aziro@<vm-ip>

# In laptop browser: http://localhost:8080
# Login: admin / <password from step a>
```

c. In the Jenkins UI:

1. **New Item** → enter name `three-tier` → **Pipeline** → OK
2. In the configuration:
   - **Pipeline → Definition:** "Pipeline script from SCM"
   - **SCM:** Git
   - **Repository URL:** your GitHub repo (e.g. `https://github.com/<you>/azure-platform-lab.git`)
   - **Branch Specifier:** `*/master`
   - **Script Path:** `pipelines/Jenkinsfile`
3. Save

d. **Build Now** to run the pipeline.

## 4. (Optional) Webhook for auto-trigger on push

In your GitHub repo: Settings → Webhooks → Add webhook
- **Payload URL:** `http://<jenkins-public-url>/github-webhook/`
- **Content type:** `application/json`
- **Events:** Just the push event

For the lab, easier to leave this manual ("Build Now" when you push) since exposing Jenkins publicly needs more network plumbing.

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Pod fails to start with `acr-docker-config not found` | Step 2 was skipped or wrong namespace |
| kaniko push fails with `unauthorized: 401` | SP creds rotated; re-create the secret |
| `helm upgrade` fails with `forbidden` | RBAC from step 1 not applied |
| `e2e tests on dev` step times out | Backend pod failed readiness; check `kubectl logs -n dev deploy/backend` |
| Jenkins pipeline pod stuck Pending | Cluster CPU pressure; agent's request doesn't fit. Reduce Jenkinsfile `resources.requests` or scale node pool |
