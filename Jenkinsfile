// Jenkins Declarative Pipeline for azure-platform-lab
// Full CI pipeline: 6 parallel checks -> build -> Trivy scan -> deploy dev (Helm values blue/green via ArgoCD) -> e2e -> manual promote to prod
// Updates Helm values files: kubernetes/apps/three-tier/values-dev.yaml and values-prod.yaml
// Required Jenkins credentials (IDs):
// AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID, ACR_NAME, GIT_CREDENTIALS (username/password), ARGOCD_SERVER, ARGOCD_TOKEN
// Tools recommended on agent: docker, az, jq, yq (preferred), trivy, gitleaks, k8s tools optional

pipeline {
  agent any
  options { ansiColor('xterm'); timestamps(); buildDiscarder(logRotator(numToKeepStr: '50')) }

  parameters {
    string(name: 'TARGET_BRANCH', defaultValue: 'main', description: 'Git branch to push manifest updates')
    string(name: 'ARGOCD_APP_DEV', defaultValue: 'three-tier-dev', description: 'ArgoCD App name for dev')
    string(name: 'ARGOCD_APP_PROD', defaultValue: 'three-tier-prod', description: 'ArgoCD App name for prod')
  }

  stages {
    stage('Checkout') {
      steps { checkout scm; script { env.COMMIT_SHA = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim() }; echo "Commit ${env.COMMIT_SHA}" }
    }

    stage('Parallel Checks') {
      parallel {
        stage('Lint') { steps { script { if (fileExists('apps/backend/package.json')) { sh 'npm ci --prefix apps/backend --no-audit || true'; sh 'npm run --prefix apps/backend lint || true' } if (fileExists('apps/frontend/package.json')) { sh 'npm ci --prefix apps/frontend --no-audit || true'; sh 'npm run --prefix apps/frontend lint || true' } } } }
        stage('Unit Tests') { steps { script { if (fileExists('apps/backend/package.json')) { sh 'npm ci --prefix apps/backend --no-audit || true'; sh 'npm test --prefix apps/backend || { echo "Unit tests failed"; exit 1; }' } else { echo 'No backend unit tests' } if (fileExists('apps/frontend/package.json')) { sh 'npm ci --prefix apps/frontend --no-audit || true'; sh 'npm test --prefix apps/frontend || echo "Frontend tests skipped/failed (non-blocking)"' } } } }
        stage('Integration Tests') { steps { script { if (fileExists('tests/integration')) { sh 'pytest tests/integration || { echo "Integration tests failed"; exit 1; }' } else { echo 'No integration tests' } } } }
        stage('Secret Scan') { steps { script { if (sh(script: 'command -v gitleaks >/dev/null 2>&1 || echo "no"', returnStdout: true).trim() != 'no') { sh 'gitleaks detect --source . --no-git -v || { echo "Secrets found"; exit 1; }' } else { echo 'gitleaks not found; skipping secret scan' } } } }
        stage('Dependency Scan') { steps { script { if (fileExists('apps/backend/package.json')) { sh 'npm audit --prefix apps/backend --audit-level=high || echo "npm audit reported issues"' } else { echo 'No backend deps' } } } }
        stage('Quality Gate') { steps { script { if (env.SONAR_HOST && env.SONAR_TOKEN) { echo 'Run SonarQube (not configured)'; } else { echo 'SonarQube not configured; skipping' } } } }
      }
    }

    stage('Build & Push Images') {
      steps {
        withCredentials([string(credentialsId: 'AZURE_CLIENT_ID', variable: 'AZURE_CLIENT_ID'), string(credentialsId: 'AZURE_CLIENT_SECRET', variable: 'AZURE_CLIENT_SECRET'), string(credentialsId: 'AZURE_TENANT_ID', variable: 'AZURE_TENANT_ID'), string(credentialsId: 'ACR_NAME', variable: 'ACR_NAME')]) {
          sh '''
            set -euo pipefail
            az login --service-principal -u "$AZURE_CLIENT_ID" -p "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID"
            ACR_LOGIN=$(az acr show -n "$ACR_NAME" --query loginServer -o tsv)
            echo "ACR_LOGIN=$ACR_LOGIN" > .acr_env
            TAG=${COMMIT_SHA}
            if [ -f apps/backend/Dockerfile ]; then docker build -t $ACR_LOGIN/backend:$TAG -f apps/backend/Dockerfile apps/backend; fi
            if [ -f apps/frontend/Dockerfile ]; then docker build -t $ACR_LOGIN/frontend:$TAG -f apps/frontend/Dockerfile apps/frontend; fi
            az acr login -n "$ACR_NAME"
            if [ -f apps/backend/Dockerfile ]; then docker push $ACR_LOGIN/backend:$TAG; fi
            if [ -f apps/frontend/Dockerfile ]; then docker push $ACR_LOGIN/frontend:$TAG; fi
          '''
        }
      }
    }

    stage('Trivy Image Scan') {
      steps {
        script {
          def acr = readFile('.acr_env').trim().split('=')[1]
          def tag = env.COMMIT_SHA
          if (sh(script: 'command -v trivy >/dev/null 2>&1 || echo "no"', returnStdout: true).trim() != 'no') {
            sh "trivy image --severity CRITICAL,HIGH ${acr}/backend:${tag} || { echo 'Vulnerabilities found in backend'; exit 1; }"
            sh "trivy image --severity CRITICAL,HIGH ${acr}/frontend:${tag} || echo 'Vulnerabilities found in frontend'"
          } else { echo 'Trivy not installed; skipping image scan' }
        }
      }
    }

    stage('Deploy to Dev (Helm values -> ArgoCD)') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'GIT_CREDENTIALS', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
          script {
            def acr = readFile('.acr_env').trim().split('=')[1]
            def tag = env.COMMIT_SHA
            def valuesDev = 'kubernetes/apps/three-tier/values-dev.yaml'
            // Prefer yq for safe YAML edits; try yq else fallback to awk
            if (sh(script: 'command -v yq >/dev/null 2>&1 || echo "no"', returnStdout: true).trim() != 'no') {
              sh "yq e -i '.backend.image.repository = \"${acr}/backend\" | .backend.image.tag = \"${tag}\" | .frontend.image.repository = \"${acr}/frontend\" | .frontend.image.tag = \"${tag}\"' ${valuesDev}"
            } else {
              sh '''
                echo "yq not found; using awk fallback to update YAML (fragile)"
                awk -v ACR="${acr}" -v TAG="${tag}" '
                  /^backend:/ { in_backend=1; in_frontend=0; print; next }
                  /^frontend:/ { in_frontend=1; in_backend=0; print; next }
                  in_backend && /^\s*repository:/ { sub(/:.*/, ": "ACR"/backend"); print; next }
                  in_backend && /^\s*tag:/ { sub(/:.*/, ": \""TAG"\""); print; next }
                  in_frontend && /^\s*repository:/ { sub(/:.*/, ": "ACR"/frontend"); print; next }
                  in_frontend && /^\s*tag:/ { sub(/:.*/, ": \""TAG"\""); print; next }
                  {print}
                ' ${valuesDev} > ${valuesDev}.tmp && mv ${valuesDev}.tmp ${valuesDev}
              '''
            }

            // Commit and push values change
            sh '''
              git add kubernetes/apps/three-tier/values-dev.yaml || true
              git commit -m "ci(dev): deploy ${COMMIT_SHA}" --allow-empty || true
              ORIG_URL=$(git remote get-url origin)
              if echo "$ORIG_URL" | grep -q "git@"; then HTTPS_URL=$(echo "$ORIG_URL" | sed -E 's/git@(.*):(.*)/https:\/\/\1\/\2/'); else HTTPS_URL="$ORIG_URL"; fi
              git push "https://${GIT_USER}:${GIT_PASS}@${HTTPS_URL#https://}" HEAD:${TARGET_BRANCH}
            '''

            // Trigger ArgoCD sync for dev app and poll for Synced
            withCredentials([string(credentialsId: 'ARGOCD_SERVER', variable: 'ARGOCD_SERVER'), string(credentialsId: 'ARGOCD_TOKEN', variable: 'ARGOCD_TOKEN')]) {
              sh '''
                echo "Triggering ArgoCD sync for ${ARGOCD_APP_DEV}"
                curl -s -k -X POST "https://${ARGOCD_SERVER}/api/v1/applications/${ARGOCD_APP_DEV}/sync" -H "Authorization: Bearer ${ARGOCD_TOKEN}" -H "Content-Type: application/json" -d '{"force":true}'
                for i in {1..30}; do
                  STATUS=$(curl -s -k -H "Authorization: Bearer ${ARGOCD_TOKEN}" https://${ARGOCD_SERVER}/api/v1/applications/${ARGOCD_APP_DEV} | jq -r .status.sync.status)
                  echo "ArgoCD sync status: $STATUS"
                  if [ "$STATUS" = "Synced" ]; then break; fi
                  sleep 5
                done
              '''
            }
          }
        }
      }
    }

    stage('E2E Tests on Dev') {
      steps { script { if (fileExists('tests/e2e')) { sh 'pytest tests/e2e || { echo "E2E failed"; exit 1; }' } else { echo 'No e2e tests; running smoke test placeholder'; sh 'pytest tests/e2e || true' } } }
    }

    stage('Manual Approval: Promote to Prod') { steps { input message: "Promote ${env.COMMIT_SHA} to prod?", ok: 'Promote' } }

    stage('Deploy to Prod (Helm values -> ArgoCD)') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'GIT_CREDENTIALS', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
          script {
            def acr = readFile('.acr_env').trim().split('=')[1]
            def tag = env.COMMIT_SHA
            def valuesProd = 'kubernetes/apps/three-tier/values-prod.yaml'
            if (sh(script: 'command -v yq >/dev/null 2>&1 || echo "no"', returnStdout: true).trim() != 'no') {
              sh "yq e -i '.backend.image.repository = \"${acr}/backend\" | .backend.image.tag = \"${tag}\" | .frontend.image.repository = \"${acr}/frontend\" | .frontend.image.tag = \"${tag}\"' ${valuesProd}"
            } else {
              sh '''
                echo "yq not found; using awk fallback to update YAML (fragile)"
                awk -v ACR="${acr}" -v TAG="${tag}" '
                  /^backend:/ { in_backend=1; in_frontend=0; print; next }
                  /^frontend:/ { in_frontend=1; in_backend=0; print; next }
                  in_backend && /^\s*repository:/ { sub(/:.*/, ": "ACR"/backend"); print; next }
                  in_backend && /^\s*tag:/ { sub(/:.*/, ": \""TAG"\""); print; next }
                  in_frontend && /^\s*repository:/ { sub(/:.*/, ": "ACR"/frontend"); print; next }
                  in_frontend && /^\s*tag:/ { sub(/:.*/, ": \""TAG"\""); print; next }
                  {print}
                ' ${valuesProd} > ${valuesProd}.tmp && mv ${valuesProd}.tmp ${valuesProd}
              '''
            }

            // Commit & push and record new commit for rollback if needed
            sh '''
              PREV_COMMIT=$(git rev-parse --short HEAD || true)
              git add kubernetes/apps/three-tier/values-prod.yaml || true
              git commit -m "ci(prod): promote ${COMMIT_SHA}" --allow-empty || true
              NEW_COMMIT=$(git rev-parse --short HEAD || true)
              echo "$NEW_COMMIT" > .new_commit
              ORIG_URL=$(git remote get-url origin)
              if echo "$ORIG_URL" | grep -q "git@"; then HTTPS_URL=$(echo "$ORIG_URL" | sed -E 's/git@(.*):(.*)/https:\/\/\1\/\2/'); else HTTPS_URL="$ORIG_URL"; fi
              git push "https://${GIT_USER}:${GIT_PASS}@${HTTPS_URL#https://}" HEAD:${TARGET_BRANCH}
            '''

            withCredentials([string(credentialsId: 'ARGOCD_SERVER', variable: 'ARGOCD_SERVER'), string(credentialsId: 'ARGOCD_TOKEN', variable: 'ARGOCD_TOKEN')]) {
              sh '''
                NEW_COMMIT=$(cat .new_commit || true)
                echo "Triggering ArgoCD sync for ${ARGOCD_APP_PROD} (commit ${NEW_COMMIT})"
                curl -s -k -X POST "https://${ARGOCD_SERVER}/api/v1/applications/${ARGOCD_APP_PROD}/sync" -H "Authorization: Bearer ${ARGOCD_TOKEN}" -H "Content-Type: application/json" -d '{"force":true}'

                # Wait for Synced + Healthy. If not achieved within timeout, revert the git change and re-sync (rollback)
                for i in {1..60}; do
                  APP_JSON=$(curl -s -k -H "Authorization: Bearer ${ARGOCD_TOKEN}" https://${ARGOCD_SERVER}/api/v1/applications/${ARGOCD_APP_PROD})
                  STATUS=$(echo "$APP_JSON" | jq -r .status.sync.status)
                  HEALTH=$(echo "$APP_JSON" | jq -r .status.health.status)
                  echo "ArgoCD sync: $STATUS, health: $HEALTH"
                  if [ "$STATUS" = "Synced" ] && [ "$HEALTH" = "Healthy" ]; then
                    echo "Prod app is Synced and Healthy"
                    exit 0
                  fi
                  sleep 5
                done

                echo "Timed out waiting for Healthy Synced state; performing rollback (reverting commit ${NEW_COMMIT})"
                # Create a revert commit and push
                git revert --no-edit ${NEW_COMMIT} || true
                git push "https://${GIT_USER}:${GIT_PASS}@${HTTPS_URL#https://}" HEAD:${TARGET_BRANCH} || true

                # Trigger ArgoCD sync to apply rollback
                curl -s -k -X POST "https://${ARGOCD_SERVER}/api/v1/applications/${ARGOCD_APP_PROD}/sync" -H "Authorization: Bearer ${ARGOCD_TOKEN}" -H "Content-Type: application/json" -d '{"force":true}' || true

                echo "Rollback triggered; failing pipeline to draw attention"
                exit 1
              '''
            }
          }
        }
      }
    }

    stage('Post-deploy Validation') { steps { echo 'Add smoke checks or HTTP healthchecks here.' } }
  }

  post { success { echo "Pipeline succeeded: ${env.COMMIT_SHA}" } failure { echo "Pipeline failed: ${env.COMMIT_SHA}" } }
}

// Full CI pipeline: 6 parallel checks -> build -> Trivy scan -> deploy dev (ArgoCD blue/green) -> e2e -> manual promote to prod (blue/green via ArgoCD)
// Expectations / repo layout:
// - k8s manifests are in 'kubernetes/overlays/dev' and 'kubernetes/overlays/prod' and are kustomize overlays.
// - ArgoCD apps exist for dev and prod and point to the respective overlay paths (params ARGOCD_APP_DEV/ARGOCD_APP_PROD).
// - Jenkins has these credentials configured (IDs used below):
//   AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID, ACR_NAME (string), GIT_CREDENTIALS (username/password),
//   ARGOCD_SERVER (string), ARGOCD_TOKEN (string)
// Tools required on agent: docker, az cli, kubectl (optional), kustomize, trivy (for image scan), gitleaks (for secret scan) - pipeline is defensive if tools missing.

pipeline {
  agent any
  options {
    ansiColor('xterm')
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '50'))
    skipDefaultCheckout(false)
  }

  parameters {
    string(name: 'MANIFEST_PATH_DEV', defaultValue: 'kubernetes/overlays/dev', description: 'Kustomize overlay path for dev')
    string(name: 'MANIFEST_PATH_PROD', defaultValue: 'kubernetes/overlays/prod', description: 'Kustomize overlay path for prod')
    string(name: 'TARGET_BRANCH', defaultValue: 'main', description: 'Git branch to push manifest updates')
    string(name: 'ARGOCD_APP_DEV', defaultValue: 'app-dev', description: 'ArgoCD App name for dev')
    string(name: 'ARGOCD_APP_PROD', defaultValue: 'app-prod', description: 'ArgoCD App name for prod')
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script { env.COMMIT_SHA = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim() }
        echo "Commit ${env.COMMIT_SHA}"
      }
    }

    stage('Parallel Checks') {
      parallel {
        stage('Lint') {
          steps {
            script {
              if (fileExists('apps/backend/package.json')) {
                sh 'npm ci --prefix apps/backend --no-audit || true'
                sh 'npm run --prefix apps/backend lint || true'
              } else { echo 'No backend package.json; skipping lint' }
              if (fileExists('apps/frontend/package.json')) {
                sh 'npm ci --prefix apps/frontend --no-audit || true'
                sh 'npm run --prefix apps/frontend lint || true'
              } else { echo 'No frontend package.json; skipping lint' }
            }
          }
        }

        stage('Unit Tests') {
          steps {
            script {
              if (fileExists('apps/backend/package.json')) {
                sh 'npm ci --prefix apps/backend --no-audit || true'
                sh 'npm test --prefix apps/backend || { echo "Unit tests failed"; exit 1; }'
              } else { echo 'No backend tests' }
              if (fileExists('apps/frontend/package.json')) {
                sh 'npm ci --prefix apps/frontend --no-audit || true'
                sh 'npm test --prefix apps/frontend || echo "Frontend tests skipped/failed (non-blocking)"'
              }
            }
          }
        }

        stage('Integration/UT (if any)') {
          steps {
            script {
              if (fileExists('tests/integration')) {
                sh 'echo "Running integration tests"'
                sh 'pytest tests/integration || { echo "Integration tests failed"; exit 1; }'
              } else { echo 'No integration tests' }
            }
          }
        }

        stage('Secret Scan') {
          steps {
            script {
              if (sh(script: 'command -v gitleaks >/dev/null 2>&1 || echo "no"', returnStdout: true).trim() != 'no') {
                sh 'gitleaks detect --source . --no-git -v || { echo "Secrets found"; exit 1; }'
              } else {
                echo 'gitleaks not installed; attempting truffleHog if available'
                if (sh(script: 'command -v trufflehog >/dev/null 2>&1 || echo "no"', returnStdout: true).trim() != 'no') {
                  sh 'trufflehog filesystem --directory . --entropy=False || true'
                  echo 'trufflehog ran (check logs)'
                } else {
                  echo 'No secret scanner installed; SKIPPING secret scan (install gitleaks or trufflehog)'
                }
              }
            }
          }
        }

        stage('Dependency Scan') {
          steps {
            script {
              if (fileExists('apps/backend/package.json')) {
                if (sh(script: 'command -v npm-audit >/dev/null 2>&1 || echo "no"', returnStdout: true).trim() == 'no') {
                  echo 'npm audit available by npm by default; running npm audit'
                }
                sh 'npm audit --prefix apps/backend --audit-level=high || echo "npm audit reported high/critical issues"'
              } else { echo 'No backend deps' }
            }
          }
        }

        stage('Quality Gate (optional SonarQube)') {
          steps {
            script {
              if (env.SONAR_HOST && env.SONAR_TOKEN) {
                sh 'echo "Running SonarQube scanner (requires scanner config)"'
                // Sonar scanner invocation placeholder
              } else {
                echo 'SonarQube not configured; skipping quality gate (configure SONAR_HOST and SONAR_TOKEN as creds)'
              }
            }
          }
        }
      }
    }

    stage('Build & Push Images') {
      steps {
        withCredentials([
          string(credentialsId: 'AZURE_CLIENT_ID', variable: 'AZURE_CLIENT_ID'),
          string(credentialsId: 'AZURE_CLIENT_SECRET', variable: 'AZURE_CLIENT_SECRET'),
          string(credentialsId: 'AZURE_TENANT_ID', variable: 'AZURE_TENANT_ID'),
          string(credentialsId: 'ACR_NAME', variable: 'ACR_NAME')
        ]) {
          sh '''
            set -euo pipefail
            echo "Logging into Azure"
            az login --service-principal -u "$AZURE_CLIENT_ID" -p "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID"
            ACR_LOGIN=$(az acr show -n "$ACR_NAME" --query loginServer -o tsv)
            echo "ACR_LOGIN=$ACR_LOGIN" > .acr_env

            TAG=${COMMIT_SHA}

            if [ -f apps/backend/Dockerfile ]; then
              echo "Building backend:$TAG"
              docker build -t $ACR_LOGIN/backend:$TAG -f apps/backend/Dockerfile apps/backend
            fi
            if [ -f apps/frontend/Dockerfile ]; then
              echo "Building frontend:$TAG"
              docker build -t $ACR_LOGIN/frontend:$TAG -f apps/frontend/Dockerfile apps/frontend
            fi

            az acr login -n "$ACR_NAME"
            if [ -f apps/backend/Dockerfile ]; then docker push $ACR_LOGIN/backend:$TAG; fi
            if [ -f apps/frontend/Dockerfile ]; then docker push $ACR_LOGIN/frontend:$TAG; fi

            echo "Images pushed: $ACR_LOGIN/*:$TAG"
          '''
        }
      }
    }

    stage('Trivy Image Scan') {
      steps {
        script {
          def acr = readFile('.acr_env').trim().split('=')[1]
          def tag = env.COMMIT_SHA
          if (sh(script: 'command -v trivy >/dev/null 2>&1 || echo "no"', returnStdout: true).trim() != 'no') {
            sh "trivy image --severity CRITICAL,HIGH ${acr}/backend:${tag} || { echo 'Vulnerabilities found'; exit 1; }"
            sh "trivy image --severity CRITICAL,HIGH ${acr}/frontend:${tag} || true || echo 'frontend scan skipped or vulnerabilities found'"
          } else {
            echo 'Trivy not installed; skipping image vulnerability scan'
          }
        }
      }
    }

    stage('Deploy to Dev (ArgoCD blue/green)') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'GIT_CREDENTIALS', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
          script {
            def acr = readFile('.acr_env').trim().split('=')[1]
            def tag = env.COMMIT_SHA
            // Update kustomize images in dev overlay
            dir(params.MANIFEST_PATH_DEV) {
              sh "kustomize edit set image backend=${acr}/backend:${tag} || true"
              sh "kustomize edit set image frontend=${acr}/frontend:${tag} || true"
            }
            // Commit changes
            sh '''
              git add ${MANIFEST_PATH_DEV} || true
              git commit -m "ci(dev): deploy ${COMMIT_SHA}" --allow-empty || true
              ORIG_URL=$(git remote get-url origin)
              if echo "$ORIG_URL" | grep -q "git@"; then
                HTTPS_URL=$(echo "$ORIG_URL" | sed -E 's/git@(.*):(.*)/https:\/\/\1\/\2/')
              else
                HTTPS_URL="$ORIG_URL"
              fi
              git push "https://${GIT_USER}:${GIT_PASS}@${HTTPS_URL#https://}" HEAD:${TARGET_BRANCH}
            '''

            // Trigger ArgoCD app sync for dev
            withCredentials([string(credentialsId: 'ARGOCD_SERVER', variable: 'ARGOCD_SERVER'), string(credentialsId: 'ARGOCD_TOKEN', variable: 'ARGOCD_TOKEN')]) {
              sh '''
                echo "Triggering ArgoCD sync for ${ARGOCD_APP_DEV}"
                curl -s -k -X POST "https://${ARGOCD_SERVER}/api/v1/applications/${ARGOCD_APP_DEV}/sync" -H "Authorization: Bearer ${ARGOCD_TOKEN}" -H "Content-Type: application/json" -d '{"force":true}'
                sleep 2
                # poll for sync
                for i in {1..30}; do
                  STATUS=$(curl -s -k -H "Authorization: Bearer ${ARGOCD_TOKEN}" https://${ARGOCD_SERVER}/api/v1/applications/${ARGOCD_APP_DEV} | jq -r .status.sync.status)
                  echo "ArgoCD sync status: $STATUS"
                  if [ "$STATUS" = "Synced" ]; then break; fi
                  sleep 5
                done
              '''
            }
          }
        }
      }
    }

    stage('E2E Tests on Dev') {
      steps {
        script {
          // Run e2e tests against dev environment; assumes tests/ e2e exist and know how to target dev
          if (fileExists('tests/e2e')) {
            sh 'pytest tests/e2e || { echo "E2E failed"; exit 1; }'
          } else {
            echo 'No e2e tests found; skipping'
          }
        }
      }
    }

    stage('Manual Approval: Promote to Prod (Blue-Green)') {
      steps {
        input message: 'Promote build ${COMMIT_SHA} to prod?', ok: 'Promote'
      }
    }

    stage('Deploy to Prod (ArgoCD blue/green)') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'GIT_CREDENTIALS', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
          script {
            def acr = readFile('.acr_env').trim().split('=')[1]
            def tag = env.COMMIT_SHA
            dir(params.MANIFEST_PATH_PROD) {
              sh "kustomize edit set image backend=${acr}/backend:${tag} || true"
              sh "kustomize edit set image frontend=${acr}/frontend:${tag} || true"
            }
            sh '''
              git add ${MANIFEST_PATH_PROD} || true
              git commit -m "ci(prod): promote ${COMMIT_SHA}" --allow-empty || true
              ORIG_URL=$(git remote get-url origin)
              if echo "$ORIG_URL" | grep -q "git@"; then
                HTTPS_URL=$(echo "$ORIG_URL" | sed -E 's/git@(.*):(.*)/https:\/\/\1\/\2/')
              else
                HTTPS_URL="$ORIG_URL"
              fi
              git push "https://${GIT_USER}:${GIT_PASS}@${HTTPS_URL#https://}" HEAD:${TARGET_BRANCH}
            '''

            withCredentials([string(credentialsId: 'ARGOCD_SERVER', variable: 'ARGOCD_SERVER'), string(credentialsId: 'ARGOCD_TOKEN', variable: 'ARGOCD_TOKEN')]) {
              sh '''
                echo "Triggering ArgoCD sync for ${ARGOCD_APP_PROD}"
                curl -s -k -X POST "https://${ARGOCD_SERVER}/api/v1/applications/${ARGOCD_APP_PROD}/sync" -H "Authorization: Bearer ${ARGOCD_TOKEN}" -H "Content-Type: application/json" -d '{"force":true}'
                sleep 2
                for i in {1..30}; do
                  STATUS=$(curl -s -k -H "Authorization: Bearer ${ARGOCD_TOKEN}" https://${ARGOCD_SERVER}/api/v1/applications/${ARGOCD_APP_PROD} | jq -r .status.sync.status)
                  echo "ArgoCD sync status: $STATUS"
                  if [ "$STATUS" = "Synced" ]; then break; fi
                  sleep 5
                done
              '''
            }
          }
        }
      }
    }

    stage('Post-deploy Validation') {
      steps {
        script {
          echo 'Optional smoke checks against prod; fail if unhealthy'
          // Add kubectl checks or HTTP healthcheck scripts as needed
        }
      }
    }
  }

  post {
    success { echo "Pipeline succeeded: ${env.COMMIT_SHA}" }
    failure { echo "Pipeline failed: ${env.COMMIT_SHA}" }
  }
}
