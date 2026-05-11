Jenkins agent requirements

Required tools on Jenkins build agents (recommended versions):
- docker (20+)
- az CLI (2.0+)
- jq
- yq (mikefarah/yq) — preferred for YAML edits
- trivy — for image vulnerability scanning
- gitleaks or trufflehog — secret scanning
- pytest (for running Python tests)

Install notes:
- yq (https://mikefarah.gitbook.io/yq/): curl -sL https://github.com/mikefarah/yq/releases/download/v4.35.1/yq_linux_amd64 -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq
- trivy: https://github.com/aquasecurity/trivy#installation
- gitleaks: https://github.com/zricethezav/gitleaks

Agent images:
- Use a custom Docker image with the above tools installed, or provision an agent VM with these packages.

Notes:
- The Jenkinsfile prefers yq; an awk fallback exists but is fragile. For production agents, install yq to avoid YAML corruption.