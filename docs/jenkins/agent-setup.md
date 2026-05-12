Agent setup commands

Quick install commands for a Debian/Ubuntu Jenkins agent (run as root or with sudo):

# Docker
apt-get update && apt-get install -y docker.io

# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# jq
apt-get install -y jq

# yq (Mike Farah)
wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/v4.35.1/yq_linux_amd64 && chmod +x /usr/local/bin/yq

# trivy
wget -qO- https://github.com/aquasecurity/trivy/releases/latest/download/trivy_$(uname -s)_$(uname -m).tar.gz | tar xz -C /tmp && mv /tmp/trivy /usr/local/bin/

# gitleaks
curl -sL https://github.com/zricethezav/gitleaks/releases/latest/download/gitleaks_$(uname -s)_$(uname -m).tar.gz | tar xz -C /tmp && mv /tmp/gitleaks /usr/local/bin/

# jq, python3-pip, pytest
apt-get install -y python3-pip && python3 -m pip install pytest

Notes:
- Adjust install commands for your OS (Alpine, RHEL, etc.).
- Prefer creating a custom agent Docker image that includes these tools for reproducibility.
